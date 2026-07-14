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
import 'dart:math';

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
    final message = event.isNotEmpty
        ? 'Morning. $event'
        : 'Morning — hope you slept well. Anything on your mind?';

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
        message: 'Heads up — $firstLine is coming up soon.',
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

    if (gap.inDays >= 3) {
      _fire(ProactiveEvent(
        mood:    AttentionMood.worried,
        message: "It's been ${gap.inDays} days. Everything alright?",
        trigger: 'checkin',
      ));
    } else if (gap.inDays >= 2) {
      final msgs = [
        "Haven't heard from you in a couple of days. What's going on?",
        "Been a bit quiet over here — just checking in.",
        "You've been on my mind. How are you doing?",
      ];
      _fire(ProactiveEvent(
        mood:    AttentionMood.curious,
        message: msgs[Random().nextInt(msgs.length)],
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
