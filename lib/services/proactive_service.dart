/// Proactive AI Service
/// Monitors context and triggers helpful Kai interventions
library;

import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

enum ProactiveTrigger {
  morningGreeting,
  lunchReminder,
  eveningRecap,
  idleCheckIn,
  breakReminder,
  calendarAlert,
  curiosityFact,
  weatherAlert,
  goalReminder,
}

class ProactiveService {
  static final ProactiveService _instance = ProactiveService._internal();
  factory ProactiveService() => _instance;
  ProactiveService._internal();

  Timer? _checkTimer;
  DateTime? _lastInteraction;
  DateTime? _lastProactive;
  bool _isEnabled = true;

  // Configuration
  static const Duration checkInterval = Duration(minutes: 5);
  static const Duration minTimeBetweenProactive = Duration(hours: 1);
  static const Duration idleThreshold = Duration(hours: 4);

  /// Initialize proactive monitoring
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('proactive_enabled') ?? true;
    
    if (_isEnabled) {
      _startMonitoring();
    }
  }

  /// Start background monitoring
  void _startMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(checkInterval, (_) => _checkTriggers());
    print('🔔 [PROACTIVE] Monitoring started');
  }

  /// Stop monitoring
  void stop() {
    _checkTimer?.cancel();
    print('🔔 [PROACTIVE] Monitoring stopped');
  }

  /// Enable/disable proactive features
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_enabled', enabled);
    
    if (enabled) {
      _startMonitoring();
    } else {
      stop();
    }
  }

  /// Record user interaction
  void recordInteraction() {
    _lastInteraction = DateTime.now();
  }

  /// TEST: Manually trigger a proactive message after delay
  /// Uses real trigger logic based on time of day and context
  Future<void> testProactive({Duration delay = const Duration(minutes: 1)}) async {
    print('🧪 [PROACTIVE TEST] Will check triggers in ${delay.inSeconds} seconds...');
    
    await Future.delayed(delay);
    
    print('🧪 [PROACTIVE TEST] Running real trigger check...');
    
    // Run through the actual trigger logic
    ProactiveTrigger? trigger;
    
    // Check triggers in priority order (same as _checkTriggers)
    if (await _shouldGreetMorning()) {
      trigger = ProactiveTrigger.morningGreeting;
      print('🧪 [TEST] Matched: Morning greeting');
    } else if (await _shouldRemindLunch()) {
      trigger = ProactiveTrigger.lunchReminder;
      print('🧪 [TEST] Matched: Lunch reminder');
    } else if (await _shouldRecapEvening()) {
      trigger = ProactiveTrigger.eveningRecap;
      print('🧪 [TEST] Matched: Evening recap');
    } else if (_shouldCheckInIdle()) {
      trigger = ProactiveTrigger.idleCheckIn;
      print('🧪 [TEST] Matched: Idle check-in');
    } else if (_shouldRemindBreak()) {
      trigger = ProactiveTrigger.breakReminder;
      print('🧪 [TEST] Matched: Break reminder');
    } else if (await _shouldShareCuriosity()) {
      trigger = ProactiveTrigger.curiosityFact;
      print('🧪 [TEST] Matched: Curiosity fact');
    } else {
      // Fallback: Use curiosity if no other trigger matches
      trigger = ProactiveTrigger.curiosityFact;
      print('🧪 [TEST] No triggers matched, using curiosity fallback');
    }
    
    print('🧪 [PROACTIVE TEST] Triggering: ${trigger.toString()}');
    await _triggerProactive(trigger);
  }

  /// Check all triggers and decide if Kai should speak up
  Future<void> _checkTriggers() async {
    if (!_isEnabled) return;
    
    // Don't interrupt too frequently
    if (_lastProactive != null &&
        DateTime.now().difference(_lastProactive!) < minTimeBetweenProactive) {
      return;
    }

    // Check triggers in priority order
    ProactiveTrigger? trigger;
    
    if (await _shouldGreetMorning()) {
      trigger = ProactiveTrigger.morningGreeting;
    } else if (await _shouldRemindLunch()) {
      trigger = ProactiveTrigger.lunchReminder;
    } else if (await _shouldRecapEvening()) {
      trigger = ProactiveTrigger.eveningRecap;
    } else if (_shouldCheckInIdle()) {
      trigger = ProactiveTrigger.idleCheckIn;
    } else if (_shouldRemindBreak()) {
      trigger = ProactiveTrigger.breakReminder;
    } else if (await _shouldShareCuriosity()) {
      trigger = ProactiveTrigger.curiosityFact;
    }

    if (trigger != null) {
      await _triggerProactive(trigger);
    }
  }

  /// Trigger a proactive message
  Future<void> _triggerProactive(ProactiveTrigger trigger, {String? overrideMessage}) async {
    _lastProactive = DateTime.now();
    
    final message = overrideMessage ?? _generateMessage(trigger);
    print('🔔 [PROACTIVE] Triggered: $trigger - "$message"');
    
    // Call the callback to initiate chat
    if (onProactiveMessage != null) {
      await onProactiveMessage!(message, trigger);
    }
    
    // Record in analytics
    await _recordTrigger(trigger);
  }
  
  /// Callback for when Kai wants to initiate conversation
  Future<void> Function(String message, ProactiveTrigger trigger)? onProactiveMessage;

  /// Generate contextual message for trigger
  String _generateMessage(ProactiveTrigger trigger) {
    final random = Random();
    
    switch (trigger) {
      case ProactiveTrigger.morningGreeting:
        return _morningGreetings[random.nextInt(_morningGreetings.length)];
      case ProactiveTrigger.lunchReminder:
        return _lunchMessages[random.nextInt(_lunchMessages.length)];
      case ProactiveTrigger.eveningRecap:
        return _eveningMessages[random.nextInt(_eveningMessages.length)];
      case ProactiveTrigger.idleCheckIn:
        return _checkInMessages[random.nextInt(_checkInMessages.length)];
      case ProactiveTrigger.breakReminder:
        return _breakMessages[random.nextInt(_breakMessages.length)];
      case ProactiveTrigger.curiosityFact:
        return _curiosityMessages[random.nextInt(_curiosityMessages.length)];
      case ProactiveTrigger.calendarAlert:
        return "Reminder: Your event starts in 15 minutes! 📅";
      case ProactiveTrigger.weatherAlert:
        return "Weather update: Looks like rain later! ☔";
      case ProactiveTrigger.goalReminder:
        return "Don't forget: You wanted to accomplish something today! 🎯";
    }
  }

  /// Record trigger for analytics
  Future<void> _recordTrigger(ProactiveTrigger trigger) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'proactive_${trigger.name}_count';
    final count = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, count + 1);
    
    // Also record last trigger time
    await prefs.setString('proactive_last_${trigger.name}', DateTime.now().toIso8601String());
  }

  // ===== TRIGGER CONDITIONS =====

  Future<bool> _shouldGreetMorning() async {
    final now = DateTime.now();
    final hour = now.hour;
    
    // Between 7-9am
    if (hour < 7 || hour >= 9) return false;
    
    // Not already greeted today
    return !(await _wasTriggeredToday(ProactiveTrigger.morningGreeting));
  }

  Future<bool> _shouldRemindLunch() async {
    final now = DateTime.now();
    final hour = now.hour;
    
    // Between 12-1pm
    if (hour != 12) return false;
    
    return !(await _wasTriggeredToday(ProactiveTrigger.lunchReminder));
  }

  Future<bool> _shouldRecapEvening() async {
    final now = DateTime.now();
    final hour = now.hour;
    
    // Between 8-10pm
    if (hour < 20 || hour >= 22) return false;
    
    return !(await _wasTriggeredToday(ProactiveTrigger.eveningRecap));
  }

  bool _shouldCheckInIdle() {
    if (_lastInteraction == null) return false;
    
    final idleDuration = DateTime.now().difference(_lastInteraction!);
    return idleDuration > idleThreshold;
  }

  bool _shouldRemindBreak() {
    // TODO: Integrate with screen time tracking
    // For now, random with low probability
    return DateTime.now().minute == 0 && DateTime.now().hour % 2 == 0;
  }

  Future<bool> _shouldShareCuriosity() async {
    // Random throughout day, max once
    return DateTime.now().hour % 6 == 0 && 
           !(await _wasTriggeredToday(ProactiveTrigger.curiosityFact));
  }

  Future<bool> _wasTriggeredToday(ProactiveTrigger trigger) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTriggerStr = prefs.getString('proactive_last_${trigger.name}');
    
    if (lastTriggerStr == null) return false;
    
    final lastTrigger = DateTime.parse(lastTriggerStr);
    final now = DateTime.now();
    
    return lastTrigger.year == now.year &&
           lastTrigger.month == now.month &&
           lastTrigger.day == now.day;
  }

  // ===== MESSAGE TEMPLATES =====

  static const _morningGreetings = [
    "Good morning! ☀️ Ready to make today awesome?",
    "Morning! How'd you sleep? Need coffee recommendations? ☕",
    "Rise and shine! What's on your agenda today?",
    "Good morning! Fun fact: You're already doing great! 🌅",
    "Hey! Just wanted to say hi. How are you feeling today?",
    "Morning vibes! ✨ What's the first thing you want to tackle?",
  ];

  static const _lunchMessages = [
    "Time for lunch! 🍽️ Want some restaurant suggestions nearby?",
    "Lunch break! What sounds good today?",
    "Hey! Have you eaten yet? Your brain needs fuel! 🥗",
    "Midday check-in! Hungry? I can help you find food! 🍕",
  ];

  static const _eveningMessages = [
    "How was your day? Want to chat about it? 🌙",
    "Evening! Anything interesting happen today?",
    "Day's wrapping up! Want to decompress and talk? 🌆",
    "Hey! Just checking in. How are you feeling tonight?",
  ];

  static const _checkInMessages = [
    "Hey! Haven't heard from you in a while. Everything okay? 😊",
    "Miss me? I was wondering how you're doing! 💭",
    "Just popping in to say hi! What's up?",
    "Feels quiet today. Want to chat about anything?",
  ];

  static const _breakMessages = [
    "You've been focused for a while! Time for a quick break? 💪",
    "Break time! Want to hear something interesting? 🤓",
    "Reminder: Breaks are important! How about a quick stretch?",
    "Hey! You've been working hard. Need a mental reset?",
  ];

  static const _curiosityMessages = [
    "Fun fact: I just learned something cool! Want to hear? 🤓",
    "Random thought: Ever wondered why... (ask me and I'll tell you!)",
    "I came across something fascinating today. Interested? ✨",
    "Quick question: What's something you've always wanted to know?",
    "Curiosity moment! What topic should we explore together? 🔍",
  ];
}
