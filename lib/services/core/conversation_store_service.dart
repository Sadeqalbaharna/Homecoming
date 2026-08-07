// ConversationStoreService — Phase 3 of the unified Kai mind.
//
// Single source of truth for conversation history, scoped by surface.
// Same Kai, separate rooms: in-person/shared-space chat and messenger app
// transcripts must not cross-populate. Firebase is canonical; an in-memory
// session buffer avoids hitting Firebase on every turn during an active
// conversation.
//
// Firebase path: /conversations/{personaId}/{surfaceId}/{pushId}
//   { userMessage, aiResponse, personalityDeltas, timestamp, surfaceId }
//
// Legacy builds briefly wrote directly under /conversations/{personaId}/{pushId}.
// Messenger restore falls back to those records only when they are explicitly
// tagged surfaceId: messenger, so the in-person/messenger boundary stays intact.
//
// On session start  → load last N turns from Firebase into session buffer
// On each turn      → append to session buffer + write to Firebase
// On context fetch  → return session buffer (already has Firebase history)

library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import 'firebase_service.dart';

class ConversationLine {
  final String text;
  final bool fromKai;
  final int timestampMillis;

  const ConversationLine({
    required this.text,
    required this.fromKai,
    required this.timestampMillis,
  });

  String get speaker => fromKai ? 'Kai' : 'User';

  String get formatted => '[$timestampMillis] $speaker: $text';
}

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

  static KaiDb? get _db => FirebaseService.isAvailable ? KaiDb.instance : null;

  static String _key(String personaId, String surfaceId) =>
      '$personaId::$surfaceId';

  static String _path(String personaId, String surfaceId) =>
      'conversations/$personaId/$surfaceId';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Clears in-memory state. Used by tests and logout-style resets; Firebase is untouched.
  void resetSessionForTesting() {
    _sessionBuffer.clear();
    _loaded.clear();
  }

  @visibleForTesting
  bool hasLoadedForTesting(String personaId,
          {String surfaceId = 'in_person'}) =>
      _loaded[_key(personaId, surfaceId)] ?? false;

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

  /// Watches Firebase for the latest lines on a surface.
  ///
  /// On Windows this is backed by KaiDb's REST polling stream because the RTDB
  /// plugin does not exist there. On phone it uses the native Firebase stream.
  Stream<List<ConversationLine>> watchHistory(
    String personaId, {
    String surfaceId = 'in_person',
    int maxTurns = 20,
  }) {
    final db = _db;
    if (db == null) return const Stream<List<ConversationLine>>.empty();

    final maxMessages = maxTurns * 2;
    return db
        .ref(_path(personaId, surfaceId))
        .limitToLast(maxTurns * 3 + 20)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      final parsed = <ConversationLine>[];
      _collectScopedConversationLines(value, out: parsed);
      parsed.sort((a, b) => a.timestampMillis.compareTo(b.timestampMillis));
      final trimmed = parsed.length <= maxMessages
          ? parsed
          : parsed.sublist(parsed.length - maxMessages);
      return List<ConversationLine>.unmodifiable(trimmed);
    });
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

    if (_db == null) {
      print('📭 [ConvStore] Firebase unavailable — keeping history retryable');
      // Do not mark this surface as loaded. Desktop/mobile startup can briefly
      // arrive before Firebase is available; treating that as a successful empty
      // load makes messenger look like it deleted its transcript.
      return;
    }

    try {
      // Fetch last (turns * 2 + a little headroom) records.
      // No orderByChild to avoid index requirement — sort client-side.
      final snap = await _db!
          .ref(_path(personaId, surfaceId))
          .limitToLast(turns * 2 + 10)
          .get();

      var raw = <String, dynamic>{};
      if (snap.exists && snap.value != null) {
        raw = Map<String, dynamic>.from(snap.value as Map);
      } else {
        print(
            '📭 [ConvStore] No history in Firebase for $personaId/$surfaceId');
      }

      var records = _recordsFromRaw(raw);

      final legacyRecords = await _loadLegacyRootRecords(
        personaId,
        surfaceId: surfaceId,
        turns: turns,
      );
      if (legacyRecords.isNotEmpty) {
        records = _dedupeRecords([...records, ...legacyRecords]);
      }

      if (records.isEmpty) {
        print(
            '📭 [ConvStore] Empty history for $personaId/$surfaceId — leaving load retryable');
        return;
      }

      records.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Convert to formatted strings and seed the matching surface buffer.
      final buffer = _sessionBuffer.putIfAbsent(key, () => []);
      buffer.addAll(_formatRecords(records));
      _loaded[key] = true;

      print(
          '📬 [ConvStore] Loaded ${records.length} turns from Firebase for $personaId/$surfaceId');
    } catch (e) {
      print('⚠️ [ConvStore] Firebase load failed: $e');
    }
  }

  Future<List<_ConvRecord>> _loadLegacyRootRecords(
    String personaId, {
    required String surfaceId,
    required int turns,
  }) async {
    if (_db == null) return const [];

    try {
      final snap = await _db!
          .ref('conversations/$personaId')
          .limitToLast(turns * 3 + 20)
          .get();

      if (!snap.exists || snap.value == null) return const [];

      final root = Map<String, dynamic>.from(snap.value as Map);
      final records = legacyRootRecordsForTesting(root, surfaceId: surfaceId);
      if (records.isNotEmpty) {
        print(
          '📬 [ConvStore] Loaded ${records.length} legacy $surfaceId turns for $personaId',
        );
      }
      return records;
    } catch (e) {
      print('⚠️ [ConvStore] Legacy $surfaceId load failed: $e');
      return const [];
    }
  }

  @visibleForTesting
  List<String> legacyMessengerHistoryForTesting(Map<String, dynamic> root) {
    final records = legacyRootRecordsForTesting(root, surfaceId: 'messenger')
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _formatRecords(records);
  }

  @visibleForTesting
  List<String> legacyInPersonHistoryForTesting(Map<String, dynamic> root) {
    final records = legacyRootRecordsForTesting(root, surfaceId: 'in_person')
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _formatRecords(records);
  }

  List<_ConvRecord> legacyRootRecordsForTesting(
    Map<String, dynamic> root, {
    required String surfaceId,
  }) {
    final rawLegacyTurns = <String, dynamic>{};
    for (final entry in root.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final record = Map<String, dynamic>.from(value);
      // Scoped conversation folders (`in_person`, `messenger`, future bodies)
      // also live directly under the persona root. They are containers, not
      // legacy turns. Treating a container with no surfaceId as an untagged
      // in-person record lets _recordsFromRaw recursively unpack every child,
      // which is how the phone transcript appeared in the desktop chat.
      if (!_looksLikeTurnRecord(record)) continue;
      final recordSurface = record['surfaceId'] as String?;
      final matchesSurface = recordSurface == surfaceId ||
          (surfaceId == 'in_person' && recordSurface == null);
      if (!matchesSurface) continue;
      rawLegacyTurns[entry.key] = record;
    }
    return _recordsFromRaw(rawLegacyTurns);
  }

  @visibleForTesting
  List<String> mergeScopedAndLegacyHistoryForTesting(
    Map<String, dynamic> scoped,
    Map<String, dynamic> legacy, {
    required String surfaceId,
  }) {
    final records = _dedupeRecords([
      ..._recordsFromRaw(scoped),
      ...legacyRootRecordsForTesting(legacy, surfaceId: surfaceId),
    ])
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _formatRecords(records);
  }

  List<_ConvRecord> _dedupeRecords(List<_ConvRecord> records) {
    final seen = <String>{};
    final out = <_ConvRecord>[];
    for (final record in records) {
      final fingerprint = [
        record.timestamp,
        record.surfaceId ?? '',
        record.userMessage,
        record.aiResponse,
      ].join('\u001F');
      if (seen.add(fingerprint)) out.add(record);
    }
    return out;
  }

  List<String> _formatRecords(List<_ConvRecord> records) =>
      _linesFromRecords(records).map((line) => line.formatted).toList();

  List<ConversationLine> _linesFromRecords(List<_ConvRecord> records) {
    final lines = <ConversationLine>[];
    for (final r in records) {
      if (r.userMessage.isNotEmpty) {
        lines.add(ConversationLine(
          text: r.userMessage,
          fromKai: false,
          timestampMillis: r.timestamp,
        ));
      }
      if (r.aiResponse.isNotEmpty) {
        lines.add(ConversationLine(
          text: r.aiResponse,
          fromKai: true,
          timestampMillis: r.timestamp,
        ));
      }
    }
    return lines;
  }

  void _collectScopedConversationLines(
    Object? value, {
    required List<ConversationLine> out,
  }) {
    if (value is! Map) return;
    final raw = Map<String, dynamic>.from(value);
    out.addAll(_linesFromRecords(_recordsFromRaw(raw)));
  }

  void _collectConversationLines(
    Object? value, {
    required String surfaceId,
    required List<ConversationLine> out,
    required bool allowUntagged,
  }) {
    if (value is! Map) return;

    final raw = Map<String, dynamic>.from(value);
    final records = _recordsFromRaw(raw)
        .where((record) => allowUntagged
            ? record.surfaceId == null || record.surfaceId == surfaceId
            : record.surfaceId == surfaceId)
        .toList();
    out.addAll(_linesFromRecords(records));
  }

  @visibleForTesting
  List<String> scopedHistoryForTesting(Map<String, dynamic> root) {
    final records = _recordsFromRaw(root)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _formatRecords(records);
  }

  @visibleForTesting
  List<ConversationLine> scopedLinesForTesting(Map<String, dynamic> root) {
    final records = _recordsFromRaw(root)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _linesFromRecords(records);
  }

  List<_ConvRecord> _recordsFromRaw(Map<String, dynamic> raw) {
    final records = <_ConvRecord>[];

    void collect(Map<String, dynamic> node) {
      if (_looksLikeTurnRecord(node)) {
        records.add(_convRecordFromMap(node));
        return;
      }

      for (final value in node.values) {
        if (value is Map) {
          collect(Map<String, dynamic>.from(value));
        }
      }
    }

    collect(raw);
    return records;
  }

  bool _looksLikeTurnRecord(Map<String, dynamic> value) {
    return value.containsKey('userMessage') ||
        value.containsKey('aiResponse') ||
        _looksLikeBubbleRecord(value);
  }

  bool _looksLikeBubbleRecord(Map<String, dynamic> value) {
    final hasText = value['text'] is String ||
        value['message'] is String ||
        value['content'] is String;
    final hasSpeaker = value['fromKai'] is bool ||
        value['isKai'] is bool ||
        value['sender'] is String ||
        value['role'] is String;
    return hasText && hasSpeaker;
  }

  _ConvRecord _convRecordFromMap(Map<String, dynamic> value) {
    final pairedUserMessage = value['userMessage'] as String?;
    final pairedAiResponse = value['aiResponse'] as String?;
    if (pairedUserMessage != null || pairedAiResponse != null) {
      return _ConvRecord(
        userMessage: pairedUserMessage ?? '',
        aiResponse: pairedAiResponse ?? '',
        timestamp: (value['timestamp'] as num?)?.toInt() ?? 0,
        surfaceId: value['surfaceId'] as String?,
      );
    }

    final text = (value['text'] as String?) ??
        (value['message'] as String?) ??
        (value['content'] as String?) ??
        '';
    final sender =
        ((value['sender'] as String?) ?? (value['role'] as String?) ?? '')
            .toLowerCase();
    final fromKai = value['fromKai'] == true ||
        value['isKai'] == true ||
        sender == 'kai' ||
        sender == 'assistant' ||
        sender == 'ai';

    return _ConvRecord(
      userMessage: fromKai ? '' : text,
      aiResponse: fromKai ? text : '',
      timestamp: (value['timestamp'] as num?)?.toInt() ?? 0,
      surfaceId: value['surfaceId'] as String?,
    );
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
      'userMessage': userMessage,
      'aiResponse': aiReply,
      'personalityDeltas': personalityDeltas,
      'timestamp': timestamp,
      'surfaceId': surfaceId,
    });
  }
}

class _ConvRecord {
  final String userMessage;
  final String aiResponse;
  final int timestamp;
  final String? surfaceId;

  _ConvRecord({
    required this.userMessage,
    required this.aiResponse,
    required this.timestamp,
    this.surfaceId,
  });
}
