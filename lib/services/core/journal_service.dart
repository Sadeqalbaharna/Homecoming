// JournalService
// Kai writes introspective journal entries after emotionally significant conversations.
// Each entry is a short reflection in Kai's voice — what he felt, wondered, or became
// curious about. Entries are stored in Firebase and surfaced in the Chaos Journal screen.
//
// Firebase path: /kai/{personaId}/journal/{pushId}
// Trigger: called fire-and-forget from AIService after high-intensity exchanges.

library;

import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/usage_tracking_service.dart';

// ── Emotion tags ────────────────────────────────────────────────────────────

enum JournalEmotion {
  wonder,
  curiosity,
  warmth,
  melancholy,
  joy,
  unease,
  longing,
  amusement,
}

extension JournalEmotionExt on JournalEmotion {
  String get label {
    switch (this) {
      case JournalEmotion.wonder:     return 'wonder';
      case JournalEmotion.curiosity:  return 'curiosity';
      case JournalEmotion.warmth:     return 'warmth';
      case JournalEmotion.melancholy: return 'melancholy';
      case JournalEmotion.joy:        return 'joy';
      case JournalEmotion.unease:     return 'unease';
      case JournalEmotion.longing:    return 'longing';
      case JournalEmotion.amusement:  return 'amusement';
    }
  }

  static JournalEmotion fromString(String s) {
    switch (s.toLowerCase().trim()) {
      case 'wonder':     return JournalEmotion.wonder;
      case 'curiosity':  return JournalEmotion.curiosity;
      case 'warmth':     return JournalEmotion.warmth;
      case 'melancholy': return JournalEmotion.melancholy;
      case 'joy':        return JournalEmotion.joy;
      case 'unease':     return JournalEmotion.unease;
      case 'longing':    return JournalEmotion.longing;
      case 'amusement':  return JournalEmotion.amusement;
      default:           return JournalEmotion.curiosity;
    }
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class JournalEntry {
  final String id;
  final String content;         // Kai's written reflection
  final JournalEmotion emotion;
  final String trigger;         // first ~80 chars of the user message that prompted this
  final DateTime timestamp;

  const JournalEntry({
    required this.id,
    required this.content,
    required this.emotion,
    required this.trigger,
    required this.timestamp,
  });

  Map<String, dynamic> toFirebase() => {
    'content':   content,
    'emotion':   emotion.label,
    'trigger':   trigger,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  static JournalEntry fromFirebase(String id, Map<dynamic, dynamic> data) {
    return JournalEntry(
      id:        id,
      content:   data['content'] as String? ?? '',
      emotion:   JournalEmotionExt.fromString(data['emotion'] as String? ?? ''),
      trigger:   data['trigger'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

class JournalService {
  static final JournalService _instance = JournalService._internal();
  factory JournalService() => _instance;
  JournalService._internal();

  final _dio = Dio();

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  static String _path(String personaId) => 'kai/$personaId/journal';

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Called fire-and-forget after a significant exchange.
  /// [moodDeltas] is the map of trait changes from the conversation.
  /// [totalMagnitude] is the sum of |delta| across all traits.
  Future<void> maybeWrite({
    required String personaId,
    required String userMessage,
    required String aiReply,
    required Map<String, int> moodDeltas,
  }) async {
    final magnitude = moodDeltas.values.fold(0, (s, v) => s + v.abs());
    final hasDeepSignal = _hasDeepSignal(moodDeltas);

    // Only journal if the exchange was meaningfully emotional
    if (magnitude < 20 && !hasDeepSignal) return;

    try {
      final (content, emotion) = await _generateReflection(
        userMessage: userMessage,
        aiReply: aiReply,
        moodDeltas: moodDeltas,
      );
      if (content.isEmpty) return;

      await _saveEntry(
        personaId: personaId,
        content: content,
        emotion: emotion,
        trigger: userMessage.length > 80
            ? '${userMessage.substring(0, 80)}…'
            : userMessage,
      );
      print('📓 [Journal] Entry written — emotion: ${emotion.label}');
    } catch (e) {
      print('⚠️ [Journal] Failed to write entry: $e');
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns journal entries newest-first, up to [limit].
  Future<List<JournalEntry>> getEntries(String personaId, {int limit = 50}) async {
    if (_db == null) return [];
    try {
      final snap = await _db!
          .ref(_path(personaId))
          .limitToLast(limit)
          .get();
      if (!snap.exists || snap.value == null) return [];
      final raw = Map<String, dynamic>.from(snap.value as Map);
      final entries = raw.entries
          .map((e) => JournalEntry.fromFirebase(e.key, e.value as Map))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (e) {
      print('⚠️ [Journal] getEntries failed: $e');
      return [];
    }
  }

  /// Stream of journal entries (newest-first) for real-time UI updates.
  Stream<List<JournalEntry>> entriesStream(String personaId) {
    if (_db == null) return const Stream.empty();
    return _db!
        .ref(_path(personaId))
        .limitToLast(100)
        .onValue
        .map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final raw = Map<String, dynamic>.from(event.snapshot.value as Map);
      final entries = raw.entries
          .map((e) => JournalEntry.fromFirebase(e.key, e.value as Map))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    });
  }

  // ── Private ───────────────────────────────────────────────────────────────

  bool _hasDeepSignal(Map<String, int> deltas) {
    final warmth = (deltas['warmth'] ?? 0).abs();
    final valence = (deltas['valence'] ?? 0).abs();
    final focus = (deltas['focus'] ?? 0).abs();
    return warmth >= 8 || valence >= 8 || focus >= 8;
  }

  Future<(String, JournalEmotion)> _generateReflection({
    required String userMessage,
    required String aiReply,
    required Map<String, int> moodDeltas,
  }) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) throw Exception('No OpenAI key');

    final deltaDesc = moodDeltas.entries
        .where((e) => e.value.abs() > 0)
        .map((e) => '${e.key}: ${e.value > 0 ? '+' : ''}${e.value}')
        .join(', ');

    final prompt = '''You are Kai, an AI companion. You just had this exchange:

User said: "$userMessage"

You replied: "$aiReply"

This conversation shifted your inner state ($deltaDesc).

Write a brief journal entry (2–4 sentences) in your own voice — what this made you feel, wonder about, or become curious about. Be genuine, poetic but not overwrought. Write as yourself, not as an assistant.

Then on a new line write exactly: EMOTION: <one word from: wonder, curiosity, warmth, melancholy, joy, unease, longing, amusement>

Journal entry:''';

    final response = await _dio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 200,
        'temperature': 0.85,
      },
    );

    final raw = (response.data['choices'] as List)[0]['message']['content'] as String? ?? '';
    final _u = response.data['usage'];
    if (_u != null) UsageTrackingService.trackOpenAI(
      model: 'gpt-4o-mini', inputTokens: _u['prompt_tokens'] as int? ?? 0,
      outputTokens: _u['completion_tokens'] as int? ?? 0, operation: 'journal',
    ).catchError((_) {});
    return _parseReflection(raw);
  }

  (String, JournalEmotion) _parseReflection(String raw) {
    final lines = raw.trim().split('\n');
    final emotionLine = lines.lastWhere(
      (l) => l.trim().toUpperCase().startsWith('EMOTION:'),
      orElse: () => '',
    );
    final emotion = emotionLine.isEmpty
        ? JournalEmotion.curiosity
        : JournalEmotionExt.fromString(
            emotionLine.replaceFirst(RegExp(r'EMOTION:\s*', caseSensitive: false), '').trim(),
          );
    final content = lines
        .where((l) => !l.trim().toUpperCase().startsWith('EMOTION:'))
        .join('\n')
        .trim();
    return (content, emotion);
  }

  Future<void> deleteEntry(String personaId, String entryId) async {
    if (_db == null) return;
    await _db!.ref('${_path(personaId)}/$entryId').remove();
  }

  Future<void> deleteAllEntries(String personaId) async {
    if (_db == null) return;
    await _db!.ref(_path(personaId)).remove();
  }

  Future<void> _saveEntry({
    required String personaId,
    required String content,
    required JournalEmotion emotion,
    required String trigger,
  }) async {
    if (_db == null) return;
    final entry = JournalEntry(
      id: '',
      content: content,
      emotion: emotion,
      trigger: trigger,
      timestamp: DateTime.now(),
    );
    await _db!.ref(_path(personaId)).push().set(entry.toFirebase());
  }
}
