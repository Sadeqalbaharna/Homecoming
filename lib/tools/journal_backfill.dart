// journal_backfill.dart
// One-shot tool: reads all past conversations from Firebase and generates
// journal entries for the ones that would have qualified under JournalService
// thresholds. Run once, then delete (or just never call again).
//
// Usage: call JournalBackfill.run(personaId) from a debug screen or initState.

import '../services/core/kai_db.dart';
import '../services/core/journal_service.dart';
import '../services/core/firebase_service.dart';

class JournalBackfill {
  /// Reads conversations/{personaId}, filters for emotionally significant ones,
  /// generates journal entries, and writes them to /kai/{personaId}/journal/.
  ///
  /// [batchSize] controls how many GPT calls run concurrently (avoid rate limits).
  /// [dryRun] logs what would be written without actually writing.
  static Future<BackfillResult> run(
    String personaId, {
    int batchSize = 3,
    bool dryRun = false,
  }) async {
    if (!FirebaseService.isAvailable) {
      print('⚠️ [Backfill] Firebase not available');
      return const BackfillResult(processed: 0, written: 0, skipped: 0);
    }

    print('📓 [Backfill] Starting journal backfill for $personaId...');

    // ── 1. Load all past conversations ─────────────────────────────────────
    final db = KaiDb.instance;
    // No orderByChild — avoids requiring a server-side index.
    // We sort client-side below anyway.
    final snap = await db.ref('conversations/$personaId').get();

    if (!snap.exists || snap.value == null) {
      print('📓 [Backfill] No conversations found at conversations/$personaId');
      return const BackfillResult(processed: 0, written: 0, skipped: 0);
    }

    final raw = Map<String, dynamic>.from(snap.value as Map);
    final conversations = raw.entries.map((e) {
      final v = Map<String, dynamic>.from(e.value as Map);
      return _ConvRecord(
        id: e.key,
        userMessage: v['userMessage'] as String? ?? '',
        aiResponse:  v['aiResponse']  as String? ?? '',
        personalityDeltas: _parseDeltas(v['personalityDeltas']),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (v['timestamp'] as num?)?.toInt() ?? 0,
        ),
      );
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    print('📓 [Backfill] Found ${conversations.length} conversations');

    // ── 2. Load existing journal entries to avoid duplicates ───────────────
    final existingSnap = await db.ref('kai/$personaId/journal').get();
    final existingTriggers = <String>{};
    if (existingSnap.exists && existingSnap.value != null) {
      final existingRaw = Map<String, dynamic>.from(existingSnap.value as Map);
      for (final e in existingRaw.values) {
        final trigger = (e as Map)['trigger'] as String? ?? '';
        if (trigger.isNotEmpty) existingTriggers.add(trigger);
      }
    }
    print('📓 [Backfill] ${existingTriggers.length} existing journal entries found (will skip duplicates)');

    // ── 3. Filter for significant conversations ────────────────────────────
    final candidates = conversations.where((c) {
      if (c.userMessage.isEmpty || c.aiResponse.isEmpty) return false;
      final magnitude = c.personalityDeltas.values.fold(0, (s, v) => s + v.abs());
      final hasDeepSignal = c.personalityDeltas.values.any((v) => v.abs() >= 8);
      // Same threshold as JournalService.maybeWrite
      return magnitude >= 20 || hasDeepSignal;
    }).toList();

    print('📓 [Backfill] ${candidates.length} conversations qualify for journaling');

    // ── 4. Process in batches ──────────────────────────────────────────────
    final journal = JournalService();
    int written = 0;
    int skipped = 0;

    for (int i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((c) async {
        final triggerPreview = c.userMessage.length > 80
            ? '${c.userMessage.substring(0, 80)}…'
            : c.userMessage;

        // Skip if we already have an entry for this trigger
        if (existingTriggers.contains(triggerPreview)) {
          print('📓 [Backfill] Skipping duplicate: $triggerPreview');
          skipped++;
          return;
        }

        if (dryRun) {
          print('📓 [Backfill] DRY RUN — would journal: $triggerPreview');
          written++;
          return;
        }

        try {
          await journal.maybeWrite(
            personaId: personaId,
            userMessage: c.userMessage,
            aiReply: c.aiResponse,
            moodDeltas: c.personalityDeltas,
          );
          written++;
          print('📓 [Backfill] ✅ Wrote entry $written / ${candidates.length - skipped}');
          // Small delay between batches to avoid hammering the API
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('📓 [Backfill] ⚠️ Failed for "${triggerPreview.substring(0, 30)}...": $e');
          skipped++;
        }
      }));
    }

    print('📓 [Backfill] Done. Written: $written, Skipped: $skipped');
    return BackfillResult(
      processed: candidates.length,
      written: written,
      skipped: skipped,
    );
  }

  static Map<String, int> _parseDeltas(dynamic raw) {
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(raw as Map)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }
}

class _ConvRecord {
  final String id;
  final String userMessage;
  final String aiResponse;
  final Map<String, int> personalityDeltas;
  final DateTime timestamp;
  _ConvRecord({
    required this.id,
    required this.userMessage,
    required this.aiResponse,
    required this.personalityDeltas,
    required this.timestamp,
  });
}

class BackfillResult {
  final int processed;
  final int written;
  final int skipped;
  const BackfillResult({
    required this.processed,
    required this.written,
    required this.skipped,
  });
  @override
  String toString() =>
      'BackfillResult(processed: $processed, written: $written, skipped: $skipped)';
}
