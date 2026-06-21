// Proactive Service — Kai initiates conversations when the user has been
// inactive for a while, triggered by timers and contextual cues.

import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// What triggered the proactive message.
enum ProactiveTrigger { idle, test, contextual }

/// Callback fired when Kai wants to proactively reach out.
/// [message] is what Kai says; [trigger] describes why (e.g. 'idle_timeout').
typedef ProactiveMessageCallback = void Function(String message, String trigger);

class ProactiveService {
  static const String _enabledKey = 'proactive_enabled';
  static const Duration _defaultIdleThreshold = Duration(minutes: 30);
  static const Duration _minimumInterval = Duration(minutes: 15);

  Timer? _idleTimer;
  DateTime? _lastInteraction;
  bool _enabled = true;
  bool _initialized = false;

  /// Set this callback to receive proactive messages.
  ProactiveMessageCallback? onProactiveMessage;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start monitoring idle time and schedule proactive messages.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _lastInteraction = DateTime.now();

    if (_enabled) {
      _scheduleNextCheck();
    }
    print('✅ [ProactiveService] Initialized (enabled: $_enabled)');
  }

  /// Stop all timers — call when the overlay is disposed.
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _initialized = false;
    print('🛑 [ProactiveService] Stopped');
  }

  /// Record that the user just interacted, resetting the idle timer.
  void recordInteraction() {
    _lastInteraction = DateTime.now();
    // Reschedule so the clock resets
    if (_enabled && _initialized) {
      _idleTimer?.cancel();
      _scheduleNextCheck();
    }
  }

  /// Enable or disable proactive messaging, persisting the setting.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);

    if (_enabled && _initialized) {
      _scheduleNextCheck();
    } else {
      _idleTimer?.cancel();
    }
    print('⚙️ [ProactiveService] Enabled: $value');
  }

  /// Manually fire a proactive message after [delay] (for testing).
  Future<void> testProactive({Duration delay = const Duration(seconds: 5)}) async {
    await Future.delayed(delay);
    _fireProactiveMessage('test');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _scheduleNextCheck() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_defaultIdleThreshold, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (!_enabled || onProactiveMessage == null) return;

    final lastSeen = _lastInteraction;
    if (lastSeen == null) return;

    final idleTime = DateTime.now().difference(lastSeen);
    if (idleTime < _minimumInterval) {
      // Not idle long enough — check again later
      _scheduleNextCheck();
      return;
    }

    _fireProactiveMessage('idle_timeout');
    // Schedule the next one
    _scheduleNextCheck();
  }

  void _fireProactiveMessage(String trigger) {
    final message = _selectMessage(trigger);
    print('💬 [ProactiveService] Firing proactive ($trigger): "$message"');
    onProactiveMessage?.call(message, trigger);
  }

  static final List<String> _idleMessages = [
    "Hey, just checking in — how's your day going?",
    "I've been thinking about our last chat. Everything okay?",
    "It's been a while! What's on your mind?",
    "Whenever you're ready to talk, I'm right here. 💙",
    "Just wanted to say hi. How are you holding up?",
    "I noticed it's been quiet. Need anything from me?",
  ];

  static String _selectMessage(String trigger) {
    final rng = Random();
    if (trigger == 'test') return 'This is a test proactive message from Kai! 🧪';
    return _idleMessages[rng.nextInt(_idleMessages.length)];
  }
}
