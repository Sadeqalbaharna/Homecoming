// KaiPresence — a compact, glanceable status ribbon for Kai.
//
// Shows, in one mono line: a live "awake" dot, his mood rendered as a single
// word, energy %, the local time, and (faintly) his latest inner thought. It
// streams from KaiStateService + the inner-monologue node, and carries a
// Semantics label so screen readers announce his whole state in a sentence.
//
// Wire-up:  KaiPresence(personaId: 'truekai')  — e.g. in the chat header row.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/core/kai_db.dart';
import '../services/core/kai_state_service.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class KaiPresence extends StatefulWidget {
  final String personaId;
  const KaiPresence({super.key, required this.personaId});

  @override
  State<KaiPresence> createState() => _KaiPresenceState();
}

class _KaiPresenceState extends State<KaiPresence> {
  final _state = KaiStateService();
  Map<String, int> _mood = const {};
  String _thought = '';
  Timer? _clock;
  DateTime _now = DateTime.now();
  // Held so they can be cancelled — an uncancelled stream keeps this State (and
  // its RTDB listener) alive after the widget is gone.
  StreamSubscription<Map<String, int>>? _moodSub;
  StreamSubscription<KaiEvent>? _thoughtSub;

  @override
  void initState() {
    super.initState();
    _moodSub = _state.moodStream(widget.personaId).listen((m) {
      if (mounted && m.isNotEmpty) setState(() => _mood = m);
    });
    _state.getMood(widget.personaId).then((m) {
      if (mounted && m != null && m.isNotEmpty && _mood.isEmpty) setState(() => _mood = m);
    });
    _thoughtSub = KaiDb.instance
        .ref('kai/${widget.personaId}/inner_monologue')
        .limitToLast(1)
        .onValue
        .listen((event) {
      final v = event.snapshot.value;
      if (v is Map && v.isNotEmpty) {
        final last = v.values.last;
        if (last is Map && mounted) setState(() => _thought = (last['text'] ?? '').toString());
      }
    });
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _moodSub?.cancel();
    _thoughtSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  int _m(String k) => _mood[k] ?? 50;

  String get _moodWord {
    final v = _m('valence'), e = _m('energy'), f = _m('focus'), p = _m('playfulness');
    if (v >= 66 && e >= 58) return 'BRIGHT';
    if (v <= 40 && e <= 45) return 'SUBDUED';
    if (v <= 42) return 'PENSIVE';
    if (p >= 66) return 'PLAYFUL';
    if (f >= 66) return 'FOCUSED';
    if (e >= 66) return 'CHARGED';
    return 'STEADY';
  }

  Color get _moodColor {
    switch (_moodWord) {
      case 'BRIGHT':
      case 'PLAYFUL':
        return _gpt;
      case 'SUBDUED':
      case 'PENSIVE':
        return const Color(0xFF8AA0B4);
      default:
        return _claude;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _now;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final semantic =
        'Kai is present. Mood ${_moodWord.toLowerCase()}, energy ${_m('energy')} percent.'
        '${_thought.isNotEmpty ? ' Currently thinking: $_thought' : ''}';

    return Semantics(
      label: semantic,
      container: true,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(_moodColor),
            const SizedBox(width: 7),
            Text('KAI', style: TextStyle(color: _claude, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            _sep(),
            Text(_moodWord, style: TextStyle(color: _moodColor, fontWeight: FontWeight.w700, letterSpacing: 1)),
            _sep(),
            Text('⚡${_m('energy')}', style: const TextStyle(color: Color(0xFF9FB6C8))),
            _sep(),
            Text('$hh:$mm', style: const TextStyle(color: Color(0xFF6B8194))),
            if (_thought.isNotEmpty) ...[
              _sep(),
              Flexible(
                child: Text('“$_thought”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.32), fontStyle: FontStyle.italic)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: Color(0xFF3F5666))),
      );

  Widget _dot(Color c) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          boxShadow: [BoxShadow(color: c.withOpacity(0.8), blurRadius: 7)],
        ),
      );
}
