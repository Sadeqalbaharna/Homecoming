// Long-term memory: embedding-based retrieval backed by Firebase RTDB.
// Stores conversation summaries as shards; queries by cosine similarity.

import 'dart:async'; // unawaited — reinforcement must never block a reply
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/firebase_service.dart';
import '../core/kai_memory_scope.dart';
import '../core/kai_db.dart'; // desktop-safe RTDB (REST) — the write path
import 'ai_config.dart';

/// A single memory result from a similarity search.
class MemoryResult {
  final String id;
  final String summary;
  final double similarity;
  final String timestamp;
  final String shardId;
  final String shardRef;
  final KaiMemoryScope scope;
  final KaiMemoryProvenance provenance;
  final String? surfaceId;
  final String? worldId;

  const MemoryResult({
    required this.id,
    required this.summary,
    required this.similarity,
    required this.timestamp,
    required this.shardId,
    required this.shardRef,
    this.scope = KaiMemoryScope.legacyUnscoped,
    this.provenance = KaiMemoryProvenance.importedLegacy,
    this.surfaceId,
    this.worldId,
  });
}

/// Result set returned from [MemoryService.queryMemory].
class MemoryQueryResult {
  final List<MemoryResult> results;
  final String query;

  const MemoryQueryResult({required this.results, required this.query});

  /// Format results as a context block for the system prompt.
  String toContextString() {
    if (results.isEmpty) return '';
    final buf = StringBuffer('\n\n=== Relevant Memories ===\n');
    for (final r in results) {
      final pct = (r.similarity * 100).toStringAsFixed(0);
      buf.writeln('• [$pct% match] ${r.summary}');
    }
    return buf.toString();
  }
}

typedef MemoryEmbeddingProvider = Future<List<double>?> Function(String text);
typedef MemoryShardLoader = Future<List<Map<String, dynamic>>> Function(
  String personaId,
);

enum MemoryQuerySideEffects { enabled, disabled }

class MemoryService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // ── Public API ────────────────────────────────────────────────────────────

  /// Query long-term memory for [query], returning up to [limit] results.
  static Future<MemoryQueryResult?> queryMemory({
    required String personaId,
    required String query,
    int limit = 5,
    MemoryEmbeddingProvider? embeddingProvider,
    MemoryShardLoader? shardLoader,
    MemoryQuerySideEffects sideEffects = MemoryQuerySideEffects.enabled,
    KaiMemoryAccessPolicy? accessPolicy,
  }) async {
    try {
      // ── Don't search for nothing ────────────────────────────────────────
      //
      // Measured on a real turn: "okay that worked" cost 6,795ms of memory
      // retrieval — 27% of the entire 25-second reply — and returned, among
      // other things, "I dont think that worked" (the exact opposite) and a
      // pasted PowerShell prompt.
      //
      // An acknowledgement doesn't refer to anything in long-term memory. It
      // refers to the message immediately before it, which is already in the
      // history buffer. Embedding it and cosine-scoring it against every shard
      // he owns buys nothing and costs seven seconds of him standing there.
      //
      // The cheapest query is the one that never runs.
      if (!_worthSearching(query)) {
        print('🧠 [MemoryService] Not worth searching: "$query"');
        return MemoryQueryResult(results: const [], query: query);
      }

      // Tests can inject deterministic embeddings so recall quality is verified
      // offline, without OpenAI or secure-storage plugins.
      final queryEmbedding = await (embeddingProvider ?? _getEmbedding)(query);
      if (queryEmbedding == null) return null;

      // Tests can inject fixed shards so golden tests do not need Firebase.
      final shards = await (shardLoader ?? _loadShards)(personaId);
      if (shards.isEmpty) return MemoryQueryResult(results: [], query: query);

      // Score each shard. Existing data and the remember() write path may name
      // the vector either `embedding` or `vector`; accept both so stored memories
      // do not silently disappear from recall.
      final scored = <MemoryResult>[];
      for (final shard in shards) {
        final scope = parseKaiMemoryScope(shard['scope']);
        final memoryWorldId = shard['worldId']?.toString();
        final summary = shard['summary']?.toString() ?? '';
        if (accessPolicy != null &&
            (!accessPolicy.allows(
                  scope: scope,
                  memoryWorldId: memoryWorldId,
                ) ||
                !accessPolicy.allowsContent(summary))) {
          continue;
        }
        final rawVector = shard['embedding'] ?? shard['vector'];
        if (rawVector is! List) continue;

        final vec = rawVector.map((v) => (v as num).toDouble()).toList();
        var sim = _cosineSimilarity(queryEmbedding, vec);

        // ── The legacy recaps are still beating real memories ────────────────
        //
        // §7.1 diagnosed this and assumed it would resolve itself: "the old ones
        // will simply lose — they can't beat a memory that contains the actual
        // words." Measured, live, on a real turn:
        //
        //   0.35  "In the conversation, the user initiates a friendly…"
        //   0.35  "In the conversation, the user initiates interactio…"
        //   0.35  "In the conversation, the user engages in casual gr…"
        //   0.34  "Sadeq said: so what happens to chat history when I…"  ← real
        //
        // Sadeq asked about chat history. The memory containing those exact
        // words came FOURTH, behind three generic recaps.
        //
        // They don't lose because they're not competing on meaning. Every one
        // was written by a Cloud Function from the same boilerplate ("In the
        // conversation, the user…"), so the template dominates the vector and
        // they sit at a flat ~0.35 against literally any query. They're not
        // similar to the question — they're equidistant from everything, and
        // that's enough to outrank a real memory on a near-miss.
        //
        // Non-destructive: halve them so they fall under the 0.28 threshold and
        // stop crowding the results. The rows stay — they're history we didn't
        // author, and forgetWeak already refuses to touch shards with no clock.
        // If a legacy recap ever genuinely is the best match, it can still win
        // from 0.70+.
        final isLegacyRecap = (shard['source']?.toString() ?? '') != 'live' &&
            (shard['summary']?.toString() ?? '')
                .startsWith('In the conversation');
        if (isLegacyRecap) sim *= 0.5;

        scored.add(MemoryResult(
          id: shard['id']?.toString() ?? '',
          summary: summary,
          similarity: sim,
          timestamp: shard['timestamp']?.toString() ?? '',
          shardId: shard['shardId']?.toString() ?? '',
          shardRef: shard['shardRef']?.toString() ?? '',
          scope: scope,
          provenance: KaiMemoryProvenance.values.firstWhere(
            (value) => value.name == shard['provenance']?.toString(),
            orElse: () => KaiMemoryProvenance.importedLegacy,
          ),
          surfaceId: shard['surfaceId']?.toString(),
          worldId: memoryWorldId,
        ));
      }

      // Sort by similarity descending, take top [limit].
      scored.sort((a, b) => b.similarity.compareTo(a.similarity));
      final top = scored.take(limit).toList();

      // "What was I telling you just before?" is a temporal question, not a
      // semantic one. Its embedding contains none of the nouns in the answer,
      // so pure cosine search preferred an older Homecoming discussion over a
      // relationship memory written two minutes earlier on Messenger.
      //
      // Scope filtering has already happened above. Recency may reorder only
      // memories this surface is authorised to see, and only for language that
      // explicitly asks for immediate continuity. Ordinary recall remains
      // semantic, and stale memories do not become "just before" forever.
      if (_asksForRecentContinuity(query)) {
        final recent = scored.where((memory) {
          final at = DateTime.tryParse(memory.timestamp)?.toUtc();
          if (at == null) return false;
          final age = DateTime.now().toUtc().difference(at);
          return !age.isNegative && age <= const Duration(hours: 12);
        }).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (recent.isNotEmpty) {
          final latest = recent.first;
          top.removeWhere((memory) => memory.id == latest.id);
          top.insert(0, latest);
          if (top.length > limit) top.removeLast();
        }
      }

      // Retrieval is a memory-strengthening event. Offline evals disable this
      // side effect so tests never touch Firebase/cache mutation.
      if (sideEffects == MemoryQuerySideEffects.enabled) {
        for (final r in top) {
          if (r.similarity < 0.30) continue;
          unawaited(_strengthen(personaId, r.shardId));
        }
      }

      return MemoryQueryResult(
        results: top,
        query: query,
      );
    } catch (e) {
      print('❌ [MemoryService] queryMemory failed: $e');
      return null;
    }
  }

  static bool _asksForRecentContinuity(String query) {
    final lower = query.trim().toLowerCase();
    return lower.contains('just before') ||
        lower.contains('just now') ||
        lower.contains('last thing') ||
        lower.contains('what was i telling you') ||
        lower.contains('where were we') ||
        lower.contains('before i came in');
  }

  /// Pin a memory shard to "facts" — it will always be included in context.
  static Future<bool> pinMemoryToFacts({
    required String personaId,
    required String memoryId,
    required String summary,
    required String shardRef,
  }) async {
    try {
      if (!FirebaseService.isAvailable) return false;
      await FirebaseService.writeData(
        path: 'personas/$personaId/facts/$memoryId',
        data: {
          'summary': summary,
          'shardRef': shardRef,
          'pinnedAt': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      print('❌ [MemoryService] pinMemoryToFacts failed: $e');
      return false;
    }
  }

  /// Mark a memory shard as dismissed — it won't surface in future queries.
  static Future<bool> dismissMemory({
    required String personaId,
    required String memoryId,
    required String shardRef,
  }) async {
    try {
      if (!FirebaseService.isAvailable) return false;
      await FirebaseService.writeData(
        path: 'personas/$personaId/dismissed/$memoryId',
        data: {
          'shardRef': shardRef,
          'dismissedAt': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      print('❌ [MemoryService] dismissMemory failed: $e');
      return false;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Form a memory. THE WRITE PATH — which did not exist.
  ///
  /// This is the bug under every other bug. `MemoryService` could query, pin and
  /// dismiss… and never *remember*. The whole index was built once by a Cloud
  /// Function out of third-person recaps ("In the conversation, the user
  /// initiates contact with Kai…"), and the app added nothing to it, ever.
  ///
  /// Two consequences, both fatal:
  ///  1. He formed NO new memories. Every conversation was gone the moment it
  ///     scrolled away — which is exactly why he re-derived that 7-layer roadmap
  ///     from the code in front of him and graded himself 7/7. He wasn't lying;
  ///     he had nothing to check against.
  ///  2. Those recaps all share a boilerplate prefix, so every vector was
  ///     dominated by the template — all ~0.22 similarity to everything, i.e.
  ///     equidistant from every query. No threshold can rescue that. Retrieval
  ///     "found 5, used 0" on every single turn.
  ///
  /// So we embed the REAL exchange, in the words that were actually said. A
  /// question about "the opening line" now matches a memory that literally
  /// contains those words, instead of a recap *about* a conversation.
  ///
  /// Fire-and-forget by design: forming a memory must never delay or break a
  /// reply. Costs one `text-embedding-3-small` call (~$0.00002).
  ///
  /// Returns the new shard's id, or null if nothing was written.
  ///
  /// The id matters: it's the address of the actual words that were said, at
  /// `memory/embeddings/{persona}/{id}`. BrainExtractionService runs on the
  /// SAME exchange and stores this id on every node and edge it produces — so
  /// his knowledge can point at the memory that formed it. Those two systems
  /// have existed side by side this whole time without one reference between
  /// them: he knew things, and he remembered things, and nothing connected the
  /// two. This return value is that nerve.
  static Future<String?> remember({
    required String personaId,
    required String userText,
    required String kaiReply,
    KaiMemoryScope scope = KaiMemoryScope.privateCore,
    KaiMemoryProvenance provenance = KaiMemoryProvenance.directConversation,
    String? surfaceId,
    String? worldId,
    String? sessionId,
  }) async {
    try {
      final u = userText.trim();
      final r = kaiReply.trim();
      if (u.isEmpty && r.isEmpty) return null;

      // Skip his own machinery — a proactive seed is an instruction to himself,
      // not a thing Sadeq said, and it must never become a "memory" of him.
      if (u.startsWith('(proactive)') || u.startsWith('(tavern)')) return null;

      // ── Don't remember nothing ───────────────────────────────────────────
      // The cheapest prune is the one that never writes. Most turns are not
      // memories: "ok", "do it", "yes", "keep going". Storing those is how you
      // end up with ten thousand shards of noise that dilute every search — the
      // exact failure we just dug out of, where 5 results came back and none of
      // them meant anything.
      //
      // A person doesn't remember every "mhm" either. They remember the turn
      // where something was actually said.
      if (!_worthRemembering(u)) {
        print('🧠 [MemoryService] Not worth remembering: "$u"');
        return null;
      }

      // First person, real words, no template. This is what gets embedded AND
      // what he reads back, so it has to sound like a memory, not a report.
      final text = 'Sadeq said: $u\nI said: $r';

      final vector = await _getEmbedding(text);
      if (vector == null) return null;

      final ref = KaiDb.instance.ref('memory/embeddings/$personaId').push();
      final now = DateTime.now();
      await ref.set({
        ...buildScopedMemoryRecord(
          vector: vector,
          summary: text,
          timestamp: now.toIso8601String(),
          scope: scope,
          provenance: provenance,
          surfaceId: surfaceId,
          worldId: worldId,
          sessionId: sessionId,
          nowMs: now.millisecondsSinceEpoch,
        ),
      });
      print(
          '🧠 [MemoryService] Remembered: ${u.length > 60 ? "${u.substring(0, 60)}…" : u}');
      return ref.key;
    } catch (e) {
      print('⚠️ [MemoryService] remember failed: $e');
      return null;
    }
  }

  // ── Decay by use ───────────────────────────────────────────────────────────
  //
  // Forgetting isn't a cleanup job bolted on the side — it's how memory works.
  // You don't remember last Tuesday's lunch because you never once needed it.
  // So: strength fades with time, and RETRIEVAL RESETS THE CLOCK. What he uses,
  // he keeps. What he never reaches for, he loses. No cron, no quota, no
  // arbitrary "keep 5000 rows" — the same rule a person runs on.

  /// Half-life in days. At 45, a memory untouched for ~6 months is at ~6%
  /// strength and gets swept; one he touches monthly effectively never fades.
  static const double _halfLifeDays = 45.0;

  /// Strength after time-decay since it was last actually needed.
  static double decayedStrength(double strength, int lastAccessedMs) {
    if (lastAccessedMs <= 0)
      return strength; // legacy shard, no clock — leave it
    final days =
        (DateTime.now().millisecondsSinceEpoch - lastAccessedMs) / 86400000.0;
    if (days <= 0) return strength;
    // `dart:math` is imported unprefixed in this file — `pow`, not `math.pow`.
    return strength * pow(0.5, days / _halfLifeDays).toDouble();
  }

  /// Retrieval is a memory-strengthening event. Fire-and-forget: reinforcement
  /// must never slow down a reply.
  static Future<void> _strengthen(String personaId, String shardId) async {
    if (shardId.isEmpty) return;
    try {
      final ref = KaiDb.instance.ref('memory/embeddings/$personaId/$shardId');
      final snap = await ref.get();
      final m = snap.value;
      if (m is! Map) return;
      final s =
          (m['strength'] is num) ? (m['strength'] as num).toDouble() : 1.0;
      await ref.update({
        // Cap it: a memory he hits constantly shouldn't become immortal and
        // crowd out everything else. Strong is enough; permanent is a fact,
        // and facts live somewhere else.
        'strength': (s + 0.35).clamp(0.0, 4.0),
        'lastAccessed': DateTime.now().millisecondsSinceEpoch,
        'hits': ((m['hits'] is int) ? m['hits'] as int : 0) + 1,
      });
    } catch (_) {
      // A missed reinforcement is fine — it just fades a little sooner.
    }
  }

  /// Let go of what he hasn't needed. Returns how many he forgot.
  ///
  /// Deliberately timid: nothing under [minAgeDays] old is even considered, no
  /// matter how weak — a memory needs a fair chance to be needed before it can
  /// be lost. We can always prune harder later; we can never get one back.
  static Future<int> forgetWeak(
    String personaId, {
    double floor = 0.12,
    int minAgeDays = 30,
  }) async {
    try {
      final shards = await _loadShards(personaId);
      if (shards.length < 200) return 0; // nothing to prune yet — don't bother
      final now = DateTime.now().millisecondsSinceEpoch;
      var forgotten = 0;

      for (final s in shards) {
        final id = s['shardId']?.toString() ?? '';
        if (id.isEmpty) continue;
        final last = (s['lastAccessed'] is int) ? s['lastAccessed'] as int : 0;
        if (last <= 0) continue; // legacy/no clock — leave it alone
        final ageDays = (now - last) / 86400000.0;
        if (ageDays < minAgeDays) continue; // too young to forget

        final str =
            (s['strength'] is num) ? (s['strength'] as num).toDouble() : 1.0;
        if (decayedStrength(str, last) >= floor) continue;

        await KaiDb.instance.ref('memory/embeddings/$personaId/$id').remove();
        forgotten++;
      }
      if (forgotten > 0) {
        print(
            '🍂 [MemoryService] Let go of $forgotten memories he never needed.');
      }
      return forgotten;
    } catch (e) {
      print('⚠️ [MemoryService] forgetWeak failed: $e');
      return 0;
    }
  }

  /// Is this turn actually a memory, or just conversational grease?
  ///
  /// Deliberately conservative: it only rejects things that are *obviously*
  /// nothing. A memory system that forgets too eagerly is worse than one that
  /// keeps a bit of junk — we can prune junk later, but we can't recover a
  /// thought he threw away. When in doubt, remember.
  /// Is this turn worth a 7-second search of everything he knows?
  ///
  /// Different question from _worthRemembering. That one asks "did anything get
  /// SAID here". This asks "does this point at something OUTSIDE the last few
  /// turns" — because that's the only thing long-term memory can answer.
  ///
  /// "okay that worked" refers to the message directly above it. That message is
  /// already in the history buffer. Searching the archive for it cost 6.8
  /// seconds and returned the opposite sentiment plus a PowerShell prompt.
  static bool _worthSearching(String query) {
    final t = query.trim();
    if (t.length < 15) return false; // "ok", "nice", "do it", "go on", "yes"

    // Acknowledgement-shaped: opens with an ack and adds almost nothing. The
    // referent is the previous turn, never the archive.
    if (RegExp(
      r'^(ok(ay)?|yep|yeah|yes|nice|cool|great|perfect|done|thanks?|lol|haha)\b.{0,20}$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return false;
    }
    return true;
  }

  /// Terminal output, stack traces, log dumps. Sadeq pastes these constantly —
  /// they're how he SHOWS Kai something.
  ///
  /// Storing one as "Sadeq said: PS C:\code\homecoming_app> Get-Process…" is
  /// wrong twice over: he didn't say it, and it poisons recall forever. Two of
  /// the five memories returned for "okay that worked" were pasted logs.
  ///
  /// A paste is not a sentence. It's evidence — it belongs in the turn, and it
  /// does belong in the reply he gives, but it is not a thing to remember him
  /// having told you.
  static final _pastedOutput = <RegExp>[
    RegExp(r'^\s*PS [A-Z]:\\'), // PowerShell prompt
    RegExp(r'\bTraceback \(most recent call last\)'),
    RegExp(r'^\s*at [A-Za-z_$.<>]+\(', multiLine: true), // stack frames
    RegExp(r'\b\d+ issues? found\b'), // flutter analyze
    RegExp(r'^\s*(warning|info|error) - .+ - (lib|test)[\\/]', multiLine: true),
    RegExp(
        r'\[Agentic\]|\[MemoryService\]|\[Brain\]|BRAIN TRACE'), // his own logs
    RegExp(r'^\s*(Exception|Error|Failed assertion):', multiLine: true),
  ];

  static bool _looksPasted(String t) {
    if (_pastedOutput.any((r) => r.hasMatch(t))) return true;
    // A wall of lines that mostly aren't sentences.
    final lines = t.split('\n');
    if (lines.length >= 8) {
      final proseish = lines.where((l) {
        final s = l.trim();
        return s.length > 15 &&
            !s.contains(RegExp(r'^[\s\W]|\.dart:\d|=>|\{|\}'));
      }).length;
      if (proseish / lines.length < 0.4) return true;
    }
    return false;
  }

  static bool _worthRemembering(String userText) {
    final t = userText.trim().toLowerCase();
    if (t.length < 12) return false; // "ok", "do it", "yes", "go on"

    // He pasted a log, he didn't say a thing. See _looksPasted.
    if (_looksPasted(userText)) return false;

    // Pure acknowledgement, nothing else in it.
    const filler = {
      'ok',
      'okay',
      'yes',
      'yeah',
      'yep',
      'no',
      'nope',
      'sure',
      'thanks',
      'thank you',
      'do it',
      'go',
      'go on',
      'go ahead',
      'keep going',
      'continue',
      'nice',
      'cool',
      'great',
      'perfect',
      'lol',
      'haha',
      'hmm',
      'k',
      'kk',
      'do all',
      'do all of it',
      'do all the above',
      'do it all',
      'there you go',
      'and',
      'and?',
      'next',
      'now what',
    };
    final stripped = t.replaceAll(RegExp(r'[^a-z ?]'), '').trim();
    if (filler.contains(stripped)) return false;

    return true;
  }

  static Future<List<double>?> _getEmbedding(String text) async {
    try {
      final apiKey = await AIConfig.getOpenAIKey();
      if (apiKey.isEmpty) return null;

      final response = await _dio.post(
        'https://api.openai.com/v1/embeddings',
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'text-embedding-3-small',
          'input': text.length > 8000 ? text.substring(0, 8000) : text,
        },
      );
      final data = response.data['data'] as List;
      return List<double>.from(data[0]['embedding'] as List);
    } catch (e) {
      print('⚠️ [MemoryService] Embedding failed: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _loadShards(
      String personaId) async {
    // Try Firebase first
    if (FirebaseService.isAvailable) {
      try {
        // Cloud Functions store the embedding + summary together at
        // /memory/embeddings/{persona}/{shardId} as { vector, summary, shardRef }.
        // Map that server shape to what queryMemory expects (embedding/summary/…).
        // Never read this collection wholesale on a client. Each child carries
        // a 1,536-value vector; loading the full history exhausted Android's
        // 256 MB heap before Kai could reply. Retrieval remains client-side for
        // now, but its working set is deliberately bounded.
        final snapshot = await KaiDb.instance
            .uncachedRef('memory/embeddings/$personaId')
            .orderByChild('timestamp')
            .limitToLast(40)
            .get()
            .timeout(const Duration(seconds: 12));
        final data = snapshot.value;
        if (data != null && data is Map) {
          return data.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            return <String, dynamic>{
              'id': e.key,
              'shardId': e.key,
              'embedding': m['embedding'] ?? m['vector'],
              'summary': m['summary'] ?? '',
              'shardRef': m['shardRef'] ?? '/memory/shards/$personaId/${e.key}',
              'timestamp': (m['timestamp'] ?? m['createdAt'] ?? '').toString(),
              // Decay-by-use bookkeeping. Legacy Cloud-Function shards have
              // none of this — they get strength 1.0 and no clock, which means
              // they're never swept (we won't delete history we didn't author).
              'strength': m['strength'] ?? 1.0,
              'lastAccessed': m['lastAccessed'] ?? 0,
              'hits': m['hits'] ?? 0,
              'scope': m['scope'],
              'provenance': m['provenance'],
              'surfaceId': m['surfaceId'],
              'worldId': m['worldId'],
              'sessionId': m['sessionId'],
            };
          }).toList();
        }
      } catch (e) {
        print('⚠️ [MemoryService] Firebase shard load failed: $e');
      }
    }

    // Fall back to local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('memory_shards_$personaId');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return List<Map<String, dynamic>>.from(
            list.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (e) {
      print('⚠️ [MemoryService] Local shard load failed: $e');
    }
    return [];
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0.0 : dot / denom;
  }
}
