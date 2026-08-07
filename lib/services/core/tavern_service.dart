// TavernService — Kai's awareness of The Tavern.
//
// Watches kingdom-ac44f RTDB /tables for NFC arrivals from the Pi stations.
// When a guest sits down:
//   1. Reads their profile from /users/{authUid}/profile (linked) or /tavern_guests/{nfcUid}
//   2. Reads /users/{authUid}/kai_memory for rich context
//   3. Asks Kai to generate a concise host briefing for Sadeq
//   4. Fires the onGuestArrival callback
//
// All reads are RTDB (kingdom-ac44f) — no Firestore dependency.

library;

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';
import '../ai/usage_tracking_service.dart';

const _rtdbBase = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app';

// ── Models ────────────────────────────────────────────────────────────────────

class TavernGuest {
  final String authUid;
  final String nfcUid;
  final String tableId;
  final String tableName;
  final String name;
  final String faction;
  final int    visitCount;
  final DateTime? lastVisit;
  final String notes;
  final String usualOrder;
  final bool   isVIP;
  final List<String> memoryFacts;

  const TavernGuest({
    required this.authUid,
    required this.nfcUid,
    required this.tableId,
    required this.tableName,
    required this.name,
    required this.faction,
    required this.visitCount,
    this.lastVisit,
    required this.notes,
    required this.usualOrder,
    required this.isVIP,
    required this.memoryFacts,
  });

  bool get isNewGuest => visitCount <= 1;

  String get lastVisitFormatted {
    if (lastVisit == null) return 'first visit';
    final diff = DateTime.now().difference(lastVisit!);
    if (diff.inDays == 0) return 'earlier today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7)  return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).round()} weeks ago';
    return '${(diff.inDays / 30).round()} months ago';
  }
}

typedef TavernArrivalCallback = void Function(TavernGuest guest, String briefing);

// ── Service ───────────────────────────────────────────────────────────────────

class TavernService {
  static final TavernService _instance = TavernService._internal();
  factory TavernService() => _instance;
  TavernService._internal();

  final _dio = Dio();
  StreamSubscription<DatabaseEvent>? _tablesSub;
  bool _watching = false;

  // Track last-seen arrivedAt per table to avoid re-firing on reconnect
  final _lastSeen = <String, int>{};

  TavernArrivalCallback? onGuestArrival;

  // ── Public API ──────────────────────────────────────────────────────────────

  void startWatching({TavernArrivalCallback? onArrival}) {
    if (_watching) return;
    _watching      = true;
    onGuestArrival = onArrival;

    final db  = FirebaseDatabase.instanceFor(app: Firebase.app('tavern'));
    _tablesSub = db.ref('tables').onValue.listen(
      (event) {
        final snap = event.snapshot;
        if (!snap.exists || snap.value == null) return;
        final tables = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in tables.entries) {
          _handleTableChange(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // The Tavern is an optional external body. A signed-in Homecoming user
        // may legitimately have no access to its Kingdom database; that must
        // never become an unhandled app-level stream error.
        print('⚠️ [Tavern] Arrival watch unavailable: $error');
        _tablesSub = null;
        _watching = false;
      },
      cancelOnError: true,
    );

    print('🍺 [Tavern] Watching RTDB tables for arrivals…');
  }

  void stopWatching() {
    _tablesSub?.cancel();
    _tablesSub = null;
    _watching  = false;
    print('🍺 [Tavern] Stopped watching');
  }

  // ── Private: arrival detection ──────────────────────────────────────────────

  void _handleTableChange(String tableId, Map<String, dynamic> data) {
    final authUid   = data['guestAuthUid'] as String?;
    final nfcUid    = data['guestNfcUid']  as String? ?? '';
    final arrivedAt = data['arrivedAt']    as int?;
    final tableName = data['tableName']    as String? ?? tableId;

    if (arrivedAt == null) return;

    // Skip stale events
    final prev = _lastSeen[tableId];
    if (prev != null && arrivedAt <= prev) return;

    final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(arrivedAt));
    if (age.inSeconds > 30) return; // too old — probably a reconnect

    _lastSeen[tableId] = arrivedAt;

    _processArrival(
      authUid:   authUid ?? '',
      nfcUid:    nfcUid,
      tableId:   tableId,
      tableName: tableName,
      data:      data,
    );
  }

  Future<void> _processArrival({
    required String authUid,
    required String nfcUid,
    required String tableId,
    required String tableName,
    required Map<String, dynamic> data,
  }) async {
    try {
      Map<String, dynamic> profile = {};
      List<String> memoryFacts     = [];

      if (authUid.isNotEmpty) {
        // Linked Kingdom user — read profile + memory from RTDB
        final results = await Future.wait([
          _rtdbGet('users/$authUid/profile'),
          _rtdbGet('users/$authUid/kai_memory'),
        ]);
        profile      = results[0] ?? {};
        final memRaw = results[1];
        if (memRaw != null) {
          final facts = memRaw['facts'];
          if (facts is List) memoryFacts = facts.cast<String>();
        }
      } else if (nfcUid.isNotEmpty) {
        // Unlinked guest
        profile = await _rtdbGet('tavern_guests/$nfcUid') ?? {};
      }

      // Prefer data already on the table record (written by Pi at tap time)
      final name       = data['guestName']  as String?
                         ?? profile['username'] as String?
                         ?? profile['name']     as String? ?? 'Guest';
      final visitCount = data['visitCount'] as int?
                         ?? profile['visitCount'] as int? ?? 1;
      final isVIP      = data['isVIP']      as bool?
                         ?? profile['isVIP']      as bool? ?? false;
      final usualOrder = data['usualOrder'] as String?
                         ?? profile['usualOrder'] as String? ?? '';
      final notes      = data['notes']      as String?
                         ?? profile['notes']      as String? ?? '';
      final faction    = profile['faction'] as String? ?? '';

      DateTime? lastVisit;
      final lv = profile['lastVisit'];
      if (lv is int) lastVisit = DateTime.fromMillisecondsSinceEpoch(lv);

      final guest = TavernGuest(
        authUid:     authUid,
        nfcUid:      nfcUid,
        tableId:     tableId,
        tableName:   tableName,
        name:        name,
        faction:     faction,
        visitCount:  visitCount,
        lastVisit:   lastVisit,
        notes:       notes,
        usualOrder:  usualOrder,
        isVIP:       isVIP,
        memoryFacts: memoryFacts,
      );

      print('🍺 [Tavern] ${guest.name} at $tableName (visit #${guest.visitCount})');

      final briefing = await _generateBriefing(guest);
      onGuestArrival?.call(guest, briefing);

    } catch (e) {
      print('⚠️ [Tavern] Arrival processing failed: $e');
    }
  }

  // ── RTDB fetch helper ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _rtdbGet(String path) async {
    try {
      final resp = await _dio.get('$_rtdbBase/$path.json');
      if (resp.data != null && resp.data is Map) {
        return Map<String, dynamic>.from(resp.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // ── Kai briefing ───────────────────────────────────────────────────────────

  static const _briefingSystem = '''
You are Kai, Sadeq's trusted AI co-host at The Tavern (a fantasy medieval bar in Bahrain).
A guest just tapped in. Give Sadeq a concise host briefing — like a colleague whispering in his ear.

Include: their name (use nickname if one is known), visit number, table, anything notable.
End with ONE small suggestion to make them feel special.

Rules:
• Under 40 words
• No greeting or preamble — straight to the briefing
• Warm and sharp, not robotic
• Use he/him pronouns for yourself
''';

  Future<String> _generateBriefing(TavernGuest guest) async {
    final ctx = _buildContext(guest);
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return _fallbackBriefing(guest);

    final local = await LocalLLMService().complete(
      system: _briefingSystem, user: ctx, maxTokens: 80,
    );
    if (local != null && local.isNotEmpty) return local;

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'system', 'content': _briefingSystem},
            {'role': 'user',   'content': ctx},
          ],
          'max_tokens': 80,
          'temperature': 0.7,
        },
      );

      final usage = response.data['usage'];
      if (usage != null) {
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o-mini',
          inputTokens:  usage['prompt_tokens']     as int? ?? 0,
          outputTokens: usage['completion_tokens'] as int? ?? 0,
          operation: 'tavern_briefing',
        ).catchError((_) {});
      }

      return (response.data['choices'] as List)[0]['message']['content']
             as String? ?? _fallbackBriefing(guest);
    } catch (e) {
      print('⚠️ [Tavern] Briefing GPT failed: $e');
      return _fallbackBriefing(guest);
    }
  }

  String _buildContext(TavernGuest guest) {
    final buf = StringBuffer();
    buf.writeln('Table: ${guest.tableName}');
    buf.writeln('Name: ${guest.name}');
    buf.writeln('Visit #: ${guest.visitCount}');
    buf.writeln('Last visit: ${guest.lastVisitFormatted}');
    if (guest.faction.isNotEmpty)    buf.writeln('Faction: ${guest.faction}');
    if (guest.usualOrder.isNotEmpty) buf.writeln('Usual order: ${guest.usualOrder}');
    if (guest.notes.isNotEmpty)      buf.writeln('Notes: ${guest.notes}');
    if (guest.isVIP)                 buf.writeln('VIP: yes');
    if (guest.isNewGuest)            buf.writeln('(First-time guest)');
    if (guest.memoryFacts.isNotEmpty) {
      buf.writeln('What Kai remembers:');
      for (final f in guest.memoryFacts) {
        buf.writeln('  • $f');
      }
    }
    return buf.toString().trim();
  }

  String _fallbackBriefing(TavernGuest guest) {
    // Reconstructed after file truncation — offline fallback used only when
    // the LLM briefing is unavailable. Uses existing TavernGuest getters.
    if (guest.isNewGuest) {
      final faction = guest.faction.isNotEmpty ? ' (${guest.faction})' : '';
      return '${guest.name}$faction \u2014 first time at ${guest.tableName}. '
          'Give him a warm welcome and make him feel at home.';
    }
    final parts = <String>[
      '${guest.name} is back \u2014 visit #${guest.visitCount} at ${guest.tableName}.',
    ];
    if (guest.isVIP) parts.add('VIP.');
    if (guest.usualOrder.isNotEmpty) parts.add('Usual: ${guest.usualOrder}.');
    if (guest.lastVisit != null) parts.add('Last in ${guest.lastVisitFormatted}.');
    parts.add('Greet him by name and offer his usual.');
    return parts.join(' ');
  }
}
