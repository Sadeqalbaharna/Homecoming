// ConversationStoreService — Phase 3 of the unified Kai mind.
//
// Single source of truth for conversation history, scoped by surface.
// Same Kai, separate rooms: in-person/shared-space chat and messenger app
// transcripts must not cross-populate. Firebase is canonical; an in-memory
// session buffer avoids hitting Firebase on every turn during an active
// conversation.
//
// Firebase path: /conversations/{personaId}/{pushId}
//   { userMessage, aiResponse, personalityDeltas, timestamp }
//
// On session start  → load last N turns from Firebase into session buffer
// On each turn      → append to session buffer + write to Firebase
// On context fetch  → return session buffer (already has Firebase history)

library;

import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import 'firebase_service.dart';

class ConversationStoreService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ConversationStoreService _instance =
      ConversationStoreService._internal();
  factory ConversationStoreService() => _instance;
  ConversationStoreService._internal();

  // In-memory session buffer — keyed by personaId + surfaceId.
  // Each entry is a formatted string: "[timestamp] User: ..." or "[timestamp] Kai: ..."
  final Map<String, List<String>> _sessionBuffer = {};
  final Map<String, bool> _loaded = {};

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  static String _key(String personaId, String surfaceId) => '$personaId::$surfaceId';

  static String _path(String personaId, String surfaceId) =>
      'conversations/$personaId/$surfaceId';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Clears in-memory state. Used by tests and logout-style resets; Firebase is untouched.
  void resetSessionForTesting() {
    _sessionBuffer.clear();
    _loaded.clear();
  }

  /// Returns the last [maxTurns] exchanges as formatted strings.
  /// Loads from Firebase on first call for this persona + surface, then uses
  /// the matching session buffer.
  Future<List<String>> getHistory(
    String personaId, {
    String surfaceId = 'in_person',
    int maxTurns = 20,
  }) async {
    final key = _key(personaId, surfaceId);
    if (!(_loaded[key] ?? false)) {
      await _loadFromFirebase(personaId, surfaceId, turns: maxTurns);
    }
    final buffer = _sessionBuffer[key] ?? [];
    final maxMessages = maxTurns * 2;
    if (buffer.length <= maxMessages) return List.unmodifiable(buffer);
    return List.unmodifiable(buffer.sublist(buffer.length - maxMessages));
  }

  /// Appends a new turn to the session buffer and writes to Firebase.
  /// Fire-and-forget for the Firebase write — never blocks the chat.
  Future<void> saveTurn({
    required String personaId,
    String surfaceId = 'in_person',
    String? userMessage,
    String? aiReply,
    required Map<String, int> personalityDeltas,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final hasUser = userMessage != null && userMessage.trim().isNotEmpty;
    final hasKai = aiReply != null && aiReply.trim().isNotEmpty;
    if (!hasUser && !hasKai) return;

    // Kai's own machinery must never be remembered as something SADEQ said.
    // "(proactive)" turns are Kai reaching out unprompted — the seed is an
    // instruction to himself, so we store a neutral marker instead. Otherwise he
    // reads his own nudge back later and thinks Sadeq wrote it.
    final storedUser = hasUser ? _sanitiseUser(userMessage!) : '';
    final storedKai = hasKai ? aiReply! : '';

    // Append to the matching surface session buffer immediately (no await).
    final key = _key(personaId, surfaceId);
    final buffer = _sessionBuffer.putIfAbsent(key, () => []);
    if (storedUser.isNotEmpty) buffer.add('[$ts] User: $storedUser');
    if (storedKai.isNotEmpty) buffer.add('[$ts] Kai: $storedKai');

    // Keep buffer from growing unbounded (cap at 60 messages = 30 turns)
    if (buffer.length > 60) buffer.removeRange(0, buffer.length - 60);

    // Write to Firebase (fire-and-forget)
    _writeToFirebase(
      personaId: personaId,
      surfaceId: surfaceId,
      userMessage: storedUser,
      aiReply: storedKai,
      personalityDeltas: personalityDeltas,
      timestamp: ts,
    ).catchError((e) => print('⚠️ [ConvStore] Firebase write failed: $e'));
  }

  /// Replaces Kai's internal seeds with a neutral, truthful marker so history
  /// never attributes his own instructions to Sadeq.
  static String _sanitiseUser(String userMessage) {
    final t = userMessage.trimLeft();
    if (t.startsWith('(proactive)')) return '(Kai spoke first, unprompted)';
    return userMessage;
  }

  /// Clears the session buffer for a persona + surface (e.g. on persona switch).
  void clearSession(String personaId, {String surfaceId = 'in_person'}) {
    final key = _key(personaId, surfaceId);
    _sessionBuffer.remove(key);
    _loaded.remove(key);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _loadFromFirebase(
    String personaId,
    String surfaceId, {
    int turns = 20,
  }) async {
    final key = _key(personaId, surfaceId);
    _loaded[key] = true; // Mark as attempted even if Firebase is down

    if (_db == null) {
      print('📭 [ConvStore] Firebase unavailable — starting with empty history');
      return;
    }

    try {
      // Fetch last (turns * 2 + a little headroom) records.
      // No orderByChild to avoid index requirement — sort client-side.
      final snap = await _db!
          .ref(_path(personaId, surfaceId))
          .limitToLast(turns * 2 + 10)
          .get();

      if (!snap.exists || snap.value == null) {
        print('📭 [ConvStore] No history in Firebase for $personaId/$surfaceId');
        return;
      }

      final raw = Map<String, dynamic>.from(snap.value as Map);

      // Parse and sort by timestamp ascending
      final records = raw.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return _ConvRecord(
          userMessage: v['userMessage'] as String? ?? '',
          aiResponse:  v['aiResponse']  as String? ?? '',
          timestamp:   (v['timestamp']  as num?)?.toInt() ?? 0,
        );
      }).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Convert to formatted strings and seed the matching surface buffer.
      final buffer = _sessionBuffer.putIfAbsent(key, () => []);
      for (final r in records) {
        if (r.userMessage.isEmpty && r.aiResponse.isEmpty) continue;
        buffer.add('[${r.timestamp}] User: ${r.userMessage}');
        buffer.add('[${r.timestamp}] Kai: ${r.aiResponse}');
      }

      print('📬 [ConvStore] Loaded ${records.length} turns from Firebase for $personaId/$surfaceId');
    } catch (e) {
      print('⚠️ [ConvStore] Firebase load failed: $e');
    }
  }

  Future<void> _writeToFirebase({
    required String personaId,
    required String surfaceId,
    required String userMessage,
    required String aiReply,
    required Map<String, int> personalityDeltas,
    required int timestamp,
  }) async {
    if (_db == null) return;
    await _db!.ref(_path(personaId, surfaceId)).push().set({
      'userMessage':       userMessage,
      'aiResponse':        aiReply,
      'personalityDeltas': personalityDeltas,
      'timestamp':         timestamp,
      'surfaceId':         surfaceId,
    });
  }
}

class _ConvRecord {
  final String userMessage;
  final String aiResponse;
  final int timestamp;
  _ConvRecord({
    required this.userMessage,
    required this.aiResponse,
    required this.timestamp,
  });
}
