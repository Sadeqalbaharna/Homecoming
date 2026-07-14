// ContextInjectionService
//
// Builds two blocks that are prepended to Kai's system prompt on every message:
//
//  1. LIVE CONTEXT   — current time, weather (cached 30 min), next calendar event
//                      (cached 5 min).
//
//  2. TEMPORAL CONTEXT — how long since the last chat, what time of day it is,
//                        and any calendar events that happened in the gap, so Kai
//                        can open with "morning, how'd you sleep?" or "how did
//                        the big meeting go?".
//
// Call stampLastMessage() right after a successful reply so the next session
// knows when this one ended.

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tavern_menu_service.dart';
import 'tavern_status_service.dart';

class ContextInjectionService {
  static final ContextInjectionService _i = ContextInjectionService._();
  factory ContextInjectionService() => _i;
  ContextInjectionService._();

  static const _channel   = MethodChannel('com.homecoming.app/kai_tools');
  static const _prefKey   = 'kai_last_message_ms';

  // ── Weather cache ─────────────────────────────────────────────────────────
  String?   _cachedWeather;
  DateTime? _weatherAt;

  // ── Calendar (upcoming) cache ─────────────────────────────────────────────
  String?   _cachedCalendar;
  DateTime? _calendarAt;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Pre-warm caches right after permissions are granted.
  Future<void> prime() async {
    await Future.wait([_fetchWeather(), _fetchUpcoming()]);
  }

  /// Stamp the current time as "last message sent". Call after every reply.
  Future<void> stampLastMessage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Full context block for the system prompt.
  /// Returns live context + temporal context + live tavern menu + live tavern status.
  Future<String> getContextBlock() async {
    final results = await Future.wait([
      _buildLiveBlock(),
      _buildTemporalBlock(),
      TavernMenuService().getMenuBlock(),
      TavernStatusService().getStatusBlock(),
    ]);
    return results.join('');
  }

  // ── Live context ──────────────────────────────────────────────────────────

  Future<String> _buildLiveBlock() async {
    final time     = _currentTime();
    final weather  = await _fetchWeather();
    final upcoming = await _fetchUpcoming();

    final buf = StringBuffer('━━ LIVE CONTEXT ━━\n');
    buf.writeln('🕐 Now: $time');
    if (weather.isNotEmpty)  buf.writeln('🌤 Weather: $weather');
    if (upcoming.isNotEmpty) buf.writeln('📅 Up next: $upcoming');
    buf.writeln('━━━━━━━━━━━━━━━━━━');
    return buf.toString();
  }

  // ── Temporal context ──────────────────────────────────────────────────────

  Future<String> _buildTemporalBlock() async {
    final prefs  = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_prefKey);
    if (lastMs == null) return ''; // First ever session

    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final now  = DateTime.now();
    final gap  = now.difference(last);

    // Very recent — nothing interesting to say
    if (gap.inMinutes < 10) return '';

    final buf = StringBuffer('━━ SINCE YOUR LAST CHAT ━━\n');

    // ── Gap description ──────────────────────────────────────────────────
    if (gap.inDays >= 14) {
      buf.writeln('⏳ It has been ${gap.inDays} days (${(gap.inDays / 7).floor()} weeks) since the last chat. Open with warmth — acknowledge the gap.');
    } else if (gap.inDays >= 7) {
      buf.writeln('⏳ About a week has passed. Ask what\'s been going on.');
    } else if (gap.inDays >= 2) {
      buf.writeln('⏳ ${gap.inDays} days have passed since the last chat.');
    } else if (gap.inDays == 1 || (gap.inHours >= 18 && last.day != now.day)) {
      buf.writeln('⏳ Last chat was yesterday at ${_fmt(last)}.');
    } else if (gap.inHours >= 8) {
      buf.writeln('⏳ ${gap.inHours} hours since the last chat (at ${_fmt(last)}).');
    } else {
      buf.writeln('⏳ ${gap.inMinutes} minutes since the last chat.');
    }

    // ── Time-of-day crossing ──────────────────────────────────────────────
    final hour = now.hour;
    final crossedMidnight = last.day != now.day;
    if (crossedMidnight) {
      if (hour >= 5 && hour < 12) {
        buf.writeln('🌅 It is now morning. A "good morning" greeting is appropriate. Consider asking how he slept.');
      } else if (hour >= 12 && hour < 17) {
        buf.writeln('☀️ It is now afternoon.');
      } else if (hour >= 17 && hour < 21) {
        buf.writeln('🌆 It is now evening.');
      } else {
        buf.writeln('🌙 It is now night / late evening.');
      }
    }

    // ── Calendar events that happened in the gap ──────────────────────────
    if (gap.inHours >= 1) {
      final events = await _fetchEventsBetween(last, now);
      if (events.isNotEmpty) {
        buf.writeln('📋 Events that happened since last chat:');
        buf.write(events);
        buf.writeln('→ Feel free to ask how any of these went if it fits naturally.');
      }
    }

    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _currentTime() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]} ${now.year}, $h:$m (Bahrain)';
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<String> _fetchWeather() async {
    if (_cachedWeather != null && _weatherAt != null &&
        DateTime.now().difference(_weatherAt!).inMinutes < 30) {
      return _cachedWeather!;
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {'User-Agent': 'curl/7.68.0'},
      ));
      final res  = await dio.get('https://wttr.in/Bahrain?format=j1');
      final data = res.data is String
          ? jsonDecode(res.data as String) as Map<String, dynamic>
          : res.data as Map<String, dynamic>;
      final cur  = data['current_condition'][0];
      final desc = (cur['weatherDesc'] as List)[0]['value'];
      final temp = cur['temp_C'];
      final feel = cur['FeelsLikeC'];
      _cachedWeather = '$desc, ${temp}°C (feels ${feel}°C)';
      _weatherAt     = DateTime.now();
      return _cachedWeather!;
    } catch (_) {
      return _cachedWeather ?? '';
    }
  }

  Future<String> _fetchUpcoming() async {
    if (_cachedCalendar != null && _calendarAt != null &&
        DateTime.now().difference(_calendarAt!).inMinutes < 5) {
      return _cachedCalendar!;
    }
    try {
      final raw = await _channel.invokeMethod<String>(
        'readCalendar', {'daysAhead': 1},
      );
      if (raw == null || raw.startsWith('No events') || raw.startsWith('I don')) {
        _cachedCalendar = '';
      } else {
        final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
        _cachedCalendar = lines.take(3).join(' · ').replaceAll('• ', '');
      }
      _calendarAt = DateTime.now();
      return _cachedCalendar!;
    } catch (_) {
      return _cachedCalendar ?? '';
    }
  }

  Future<String> _fetchEventsBetween(DateTime from, DateTime to) async {
    try {
      final raw = await _channel.invokeMethod<String>('readCalendarBetween', {
        'fromMs': from.millisecondsSinceEpoch,
        'toMs':   to.millisecondsSinceEpoch,
      });
      return (raw == null || raw.trim().isEmpty) ? '' : '$raw\n';
    } catch (_) {
      return '';
    }
  }
}
