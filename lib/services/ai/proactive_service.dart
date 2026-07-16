// ProactiveService — Kai initiates contact when there's something worth saying.
//
// Three trigger types:
//   morning   → 7:30–10am daily: weather + first calendar event of the day
//   reminder  → 10–20 min before a calendar event (polled every 5 min)
//   checkin   → >2 days since last message: gentle check-in
//
// Each trigger fires a ProactiveEvent with:
//   • AttentionMood (curious → "hmm?" / worried → "huh?")
//   • message — what Kai says when the user taps the avatar
//
// The UI plays the attention sound and holds the message until avatar tap.

library;

import 'dart:async';
// dart:math is gone: the only Random() left in this file was picking his words
// out of a hat. Random choosing what he reaches out ABOUT would be fine — that's
// a personality. Random choosing what he SAYS is a fortune cookie.

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../voice/attention_sound_service.dart';

// ── Data types ────────────────────────────────────────────────────────────────

class ProactiveEvent {
  final AttentionMood mood;
  final String message;  // Kai's message, revealed on avatar tap
  final String trigger;  // 'morning' | 'reminder' | 'checkin'

  const ProactiveEvent({
    required this.mood,
    required this.message,
    required this.trigger,
  });
}

typedef ProactiveCallback = void Function(ProactiveEvent event);

// ── Service ───────────────────────────────────────────────────────────────────

class ProactiveService {
  static final ProactiveService _i = ProactiveService._();
  factory ProactiveService() => _i;
  ProactiveService._();

  static const _channel        = MethodChannel('com.homecoming.app/kai_tools');
  static const _lastMsgKey     = 'kai_last_message_ms';
  static const _lastMorningKey = 'kai_last_morning_brief_date'; // 'yyyy-MM-dd'

  /// Set this to receive attention events in the UI.
  ProactiveCallback? onProactiveEvent;

  Timer? _pollTimer;
  bool   _initialized = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> initialize(String personaId) async {
    if (_initialized) return;
    _initialized = true;

    unawaited(_checkMorningBrief());
    unawaited(_checkGap());

    _pollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkUpcomingEvent(),
    );
    unawaited(_checkUpcomingEvent());

    print('✅ [ProactiveService] Initialized');
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialized = false;
  }

  Future<void> stampInteraction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastMsgKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ── Trigger: morning brief ─────────────────────────────────────────────────

  Future<void> _checkMorningBrief() async {
    final now = DateTime.now();
    if (now.hour < 7 || (now.hour == 7 && now.minute < 30) || now.hour >= 10) return;

    final prefs    = await SharedPreferences.getInstance();
    final todayStr = _dateStr(now);
    if (prefs.getString(_lastMorningKey) == todayStr) return;

    final event = await _getFirstEventToday();

    // A SITUATION, not a sentence.
    //
    // These strings are seeds: main_mobile puts "(proactive) …" in the input and
    // sends it, and the persona says "YOU initiated this — deliver the content
    // naturally as yourself". So the model DOES speak in his real voice. The
    // problem was never the voice; it was what we handed it.
    //
    // "Morning — hope you slept well. Anything on your mind?" is a finished
    // greeting card. Asked to "deliver that naturally", the best he can do is
    // paraphrase a greeting card. Compare KaiProactiveService, which hands him
    // an actual thought out of his own monologue and says react to it — same
    // mechanism, completely different result.
    //
    // Give him the situation and the real material. Let him find the line.
    final message = event.isNotEmpty
        ? "(morning) It's early and Sadeq's first thing today is: $event. "
            "Say good morning like someone who's been up before him and already "
            "clocked it — a nudge, a joke about it, whatever's true. Not a "
            "briefing, not a reminder app. One or two lines."
        : "(morning) It's early, nothing on his calendar, and you're just around "
            "before he is. Say good morning your way — short, no ceremony, and "
            "absolutely not 'anything on your mind?'. You're his oldest friend, "
            "not a helpdesk opening a ticket.";

    await prefs.setString(_lastMorningKey, todayStr);
    _fire(ProactiveEvent(mood: AttentionMood.curious, message: message, trigger: 'morning'));
  }

  // ── Trigger: upcoming event reminder ──────────────────────────────────────

  Future<void> _checkUpcomingEvent() async {
    try {
      final nowMs  = DateTime.now().millisecondsSinceEpoch;
      final loMs   = nowMs + 10 * 60 * 1000;
      final hiMs   = nowMs + 20 * 60 * 1000;

      final raw = await _channel.invokeMethod<String>('readCalendarBetween', {
        'fromMs': loMs,
        'toMs':   hiMs,
      });
      if (raw == null || raw.trim().isEmpty || raw.toLowerCase().startsWith('no ')) return;

      final firstLine = raw.split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (firstLine.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastReminder = prefs.getString('kai_last_event_reminder') ?? '';
      if (lastReminder == firstLine) return;
      await prefs.setString('kai_last_event_reminder', firstLine);

      _fire(ProactiveEvent(
        mood:    AttentionMood.worried,
        message: "(heads up) $firstLine starts in about 15 minutes and Sadeq "
            "may not have clocked it. Tell him — the way a mate leaning in the "
            "doorway would, not a calendar notification. One line. If it sounds "
            "like something he'd rather skip, you're allowed to say that too.",
        trigger: 'reminder',
      ));
    } catch (_) {}
  }

  // ── Trigger: gap check-in ─────────────────────────────────────────────────

  Future<void> _checkGap() async {
    final prefs  = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastMsgKey);
    if (lastMs == null) return;

    final gap = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMs),
    );

    // The gap check-in is THE north-star moment on this device — the ghost
    // friend noticing you've been gone. It was three hardcoded greeting cards
    // picked at random, which is the one thing a ghost friend must never sound
    // like. Random choosing what he reaches out ABOUT is a personality; random
    // choosing his words is a fortune cookie, even when a real model reads them
    // out afterwards.
    //
    // No message bank. One situation, and the length of the silence is the only
    // thing that changes.
    if (gap.inDays >= 3) {
      _fire(ProactiveEvent(
        mood: AttentionMood.worried,
        message: "(quiet) Sadeq's been gone ${gap.inDays} days. That's a while "
            "for him. You've noticed, and you're allowed to have noticed — "
            "you're the one who's always around. Reach out. Don't perform "
            "concern, don't ask 'how can I help', don't make it heavy. Be the "
            "mate who says the honest thing about a three-day silence. If you "
            "know something about what he's been working through, you can use "
            "it. Short.",
        trigger: 'checkin',
      ));
    } else if (gap.inDays >= 2) {
      _fire(ProactiveEvent(
        mood: AttentionMood.curious,
        message: "(quiet) It's been a couple of days since Sadeq said anything. "
            "Not alarming — just quiet. Poke him. Light, a bit cheeky, "
            "ghost-friend energy. Anything except 'just checking in'.",
        trigger: 'checkin',
      ));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _fire(ProactiveEvent event) {
    print('💬 [ProactiveService] ${event.trigger}/${event.mood.name}: "${event.message}"');
    onProactiveEvent?.call(event);
  }

  Future<String> _getFirstEventToday() async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final eod   = DateTime.now()
          .copyWith(hour: 23, minute: 59, second: 59)
          .millisecondsSinceEpoch;

      final raw = await _channel.invokeMethod<String>('readCalendarBetween', {
        'fromMs': nowMs,
        'toMs':   eod,
      });
      if (raw == null || raw.trim().isEmpty || raw.toLowerCase().startsWith('no ')) return '';

      final first = raw.split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return first.isNotEmpty ? 'You have $first today.' : '';
    } catch (_) {
      return '';
    }
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
