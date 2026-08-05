// KaiPresenceCard — the fun-stack v0 surface.
//
// This is intentionally read-only and low-risk: it does not write memory, fire
// proactive notifications, or spend tokens. It just makes Kai's presence visible
// as one compact card: Now / Remembered / Nudge / Becoming.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/core/kai_state_service.dart';

class KaiPresenceCard extends StatefulWidget {
  final String personaId;

  const KaiPresenceCard({super.key, required this.personaId});

  @override
  State<KaiPresenceCard> createState() => _KaiPresenceCardState();
}

class _KaiPresenceCardState extends State<KaiPresenceCard> {
  final _state = KaiStateService();
  StreamSubscription<Map<String, int>>? _moodSub;
  Map<String, int> _mood = const {};

  @override
  void initState() {
    super.initState();
    _moodSub = _state.moodStream(widget.personaId).listen((m) {
      if (mounted) setState(() => _mood = m);
    });
    _state.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) {
        setState(() => _mood = m);
      }
    });
  }

  @override
  void dispose() {
    _moodSub?.cancel();
    super.dispose();
  }

  int _m(String key, [int fallback = 50]) => _mood[key] ?? fallback;

  String get _nowLine {
    final warmth = _m('warmth');
    final focus = _m('focus');
    final energy = _m('energy');
    final play = _m('playfulness');
    final pieces = <String>[];
    if (warmth >= 70) pieces.add('warm');
    if (focus >= 70) pieces.add('focused');
    if (energy >= 65) pieces.add('awake');
    if (play >= 65) pieces.add('playful');
    if (pieces.isEmpty) pieces.add('quiet');
    return '${pieces.join(', ')} · focus $focus% · energy $energy%';
  }

  String get _rememberedLine => 'token hydra is jarred for now';

  String get _nudgeLine {
    final focus = _m('focus');
    final energy = _m('energy');
    if (focus >= 75 && energy >= 65) return 'tiny win > giant rewrite';
    if (energy < 45) return 'small step, soft landing';
    return 'pick the smallest reversible goblin';
  }

  String get _becomingLine => 'continuous, not summoned';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Kai Presence Card. Now: $_nowLine. Remembered: $_rememberedLine. Nudge: $_nudgeLine. Becoming: $_becomingLine.',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A111C).withOpacity(0.74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF223246)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ED9FF).withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ED9FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2ED9FF).withOpacity(0.55),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'KAI PRESENCE',
                  style: TextStyle(
                    color: Color(0xFFDBE7F2),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line('Now', _nowLine),
            _line('Remembered', _rememberedLine),
            _line('Nudge', _nudgeLine),
            _line('Becoming', _becomingLine),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF7F93AA),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
