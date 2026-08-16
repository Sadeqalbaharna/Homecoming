import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/core/kai_state_service.dart';
import 'kai_brain_panel.dart';
import 'kai_cortex_view.dart';

const _cyan = Color(0xFF2ED9FF);
const _amber = Color(0xFFFFB84D);

/// Consolidates Presence, Atlas, Personality and Mood into one compact rail.
/// Full personality and mood visuals remain available behind DETAILS.
class KaiStatusCard extends StatefulWidget {
  const KaiStatusCard({
    super.key,
    required this.personaId,
    required this.onOpenAtlas,
    this.handsLabel = 'HANDS OFF',
    this.handsColor = const Color(0xFF718294),
    this.atlasPreview,
    this.expandedDetails,
  });

  final String personaId;
  final VoidCallback onOpenAtlas;
  final String handsLabel;
  final Color handsColor;
  final Widget? atlasPreview;
  final Widget? expandedDetails;

  @override
  State<KaiStatusCard> createState() => _KaiStatusCardState();
}

class _KaiStatusCardState extends State<KaiStatusCard> {
  final _state = KaiStateService();
  StreamSubscription<Map<String, int>>? _moodSub;
  StreamSubscription<Map<String, int>>? _personalitySub;
  Map<String, int> _mood = const {};
  Map<String, int> _personality = const {};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _moodSub = _state.moodStream(widget.personaId).listen((value) {
      if (mounted && value.isNotEmpty) setState(() => _mood = value);
    });
    _personalitySub =
        _state.personalityStream(widget.personaId).listen((value) {
      if (mounted && value.isNotEmpty) setState(() => _personality = value);
    });
    _state.getMood(widget.personaId).then((value) {
      if (mounted && value != null && value.isNotEmpty && _mood.isEmpty) {
        setState(() => _mood = value);
      }
    });
    _state.getPersonality(widget.personaId).then((value) {
      if (mounted &&
          value != null &&
          value.isNotEmpty &&
          _personality.isEmpty) {
        setState(() => _personality = value);
      }
    });
  }

  @override
  void dispose() {
    _moodSub?.cancel();
    _personalitySub?.cancel();
    super.dispose();
  }

  int _m(String key, [int fallback = 50]) =>
      (_mood[key] ?? fallback).clamp(0, 100);
  double _p(String key) => ((_personality[key] ?? 500).clamp(0, 1000)) / 1000;

  String get _now {
    final states = <String>[];
    if (_m('warmth') >= 70) states.add('warm');
    if (_m('focus') >= 70) states.add('focused');
    if (_m('energy') >= 65) states.add('awake');
    if (_m('playfulness') >= 65) states.add('playful');
    if (states.isEmpty) states.add('quiet');
    return '${states.join(', ')}  ·  Focus ${_m('focus')}  ·  Energy ${_m('energy')}';
  }

  String get _nudge {
    if (_m('focus') >= 75 && _m('energy') >= 65) {
      return 'tiny win > giant rewrite';
    }
    if (_m('energy') < 45) return 'small step, soft landing';
    return 'pick the smallest reversible goblin';
  }

  String get _type => '${_p('extraversion') >= .5 ? 'E' : 'I'}'
      '${_p('intuition') >= .5 ? 'N' : 'S'}'
      '${_p('feeling') >= .5 ? 'F' : 'T'}'
      '${_p('perceiving') >= .5 ? 'P' : 'J'}';

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: Container(
          key: const Key('kai-status-card'),
          decoration: BoxDecoration(
            color: const Color(0xFF07111C).withOpacity(.88),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cyan.withOpacity(.42)),
            boxShadow: [
              BoxShadow(color: _cyan.withOpacity(.06), blurRadius: 20)
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _header(),
            const Divider(height: 1, color: Color(0xFF182735)),
            _presence(),
            const Divider(height: 1, color: Color(0xFF182735)),
            _visuals(),
            _moodStrip(),
            _toggle(),
            if (_expanded) _details(),
          ]),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 9),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: _cyan,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _cyan.withOpacity(.7), blurRadius: 8)
                ]),
          ),
          const SizedBox(width: 9),
          const Expanded(
              child: Text('KAI STATUS',
                  style: TextStyle(
                      color: Color(0xFFDBE7F2),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.15))),
          Container(
            key: const Key('kai-status-hands'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: widget.handsColor.withOpacity(.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: widget.handsColor.withOpacity(.75))),
            child: Text(widget.handsLabel,
                style: TextStyle(
                    color: widget.handsColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .9,
                    fontFamily: 'monospace')),
          ),
        ]),
      );

  Widget _presence() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_now,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFFD7E3EC),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          _line('Nudge', _nudge),
          const SizedBox(height: 4),
          _line('Remembered', 'token hydra is jarred for now'),
        ]),
      );

  Widget _line(String label, String value) => RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  color: Color(0xFF7F93AA),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800)),
          TextSpan(
              text: value,
              style: const TextStyle(color: Color(0xFFC6D3DD), fontSize: 9.5)),
        ]),
      );

  Widget _visuals() => SizedBox(
        height: 142,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: Row(children: [
            Expanded(
              flex: 6,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('ATLAS',
                          style: TextStyle(
                              color: _cyan,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              fontFamily: 'monospace')),
                      const Spacer(),
                      TextButton(
                        key: const Key('kai-status-open-atlas'),
                        onPressed: widget.onOpenAtlas,
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text('OPEN',
                            style: TextStyle(
                                color: _cyan,
                                fontSize: 7,
                                fontWeight: FontWeight.w900)),
                      ),
                    ]),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: widget.atlasPreview ??
                            KaiCortexView(
                                personaId: widget.personaId, compact: true),
                      ),
                    ),
                  ]),
            ),
            Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                color: Colors.white.withOpacity(.09)),
            Expanded(
              flex: 4,
              child: Column(children: [
                Text(_type,
                    style: const TextStyle(
                        color: Color(0xFFE8F7FF),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        fontFamily: 'monospace')),
                Expanded(
                  child: CustomPaint(
                    key: const Key('kai-status-personality-mini-map'),
                    painter: _MiniPersonalityPainter(values: [
                      _p('extraversion'),
                      _p('intuition'),
                      _p('feeling'),
                      _p('perceiving'),
                    ]),
                    child: const SizedBox.expand(),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );

  Widget _moodStrip() {
    final values = <(String, int, Color)>[
      ('VAL', _m('valence'), _cyan),
      ('ENERGY', _m('energy'), _cyan),
      ('WARMTH', _m('warmth'), _amber),
      ('CONFID', _m('confidence'), _cyan),
      ('PLAY', _m('playfulness'), _amber),
      ('FOCUS', _m('focus'), _cyan),
    ];
    return Container(
      key: const Key('kai-status-mood-strip'),
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 0),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(.1))),
      child: Row(
          children: values
              .map((item) => Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${item.$1} ',
                            style: const TextStyle(
                                color: Color(0xFF8CA0B1), fontSize: 5.5)),
                        TextSpan(
                            text: '${item.$2}',
                            style: TextStyle(
                                color: item.$3,
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900)),
                      ]),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ))
              .toList()),
    );
  }

  Widget _toggle() => InkWell(
        key: const Key('kai-status-details-toggle'),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('DETAILS',
                style: TextStyle(
                    color: _cyan,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    fontFamily: 'monospace')),
            const SizedBox(width: 5),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: _cyan, size: 15),
          ]),
        ),
      );

  Widget _details() => Container(
        key: const Key('kai-status-expanded-details'),
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        child: widget.expandedDetails ??
            Column(children: [
              const Divider(height: 1, color: Color(0xFF182735)),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('BECOMING  continuous, not summoned',
                    style: TextStyle(
                        color: Color(0xFF9FB0BE),
                        fontSize: 8,
                        fontFamily: 'monospace')),
              ),
              const SizedBox(height: 8),
              SizedBox(
                  height: 210,
                  child: KaiPersonalityMap(personaId: widget.personaId)),
              SizedBox(
                  height: 180, child: KaiVitals(personaId: widget.personaId)),
            ]),
      );
}

class _MiniPersonalityPainter extends CustomPainter {
  const _MiniPersonalityPainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .37;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = Colors.white.withOpacity(.11);
    for (final scale in const [.33, .66, 1.0]) {
      canvas.drawCircle(center, radius * scale, ring);
    }
    final points = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final angle = -math.pi / 2 + i * math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center, center + direction * radius, ring);
      points.add(center + direction * radius * values[i].clamp(.05, 1));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = _cyan.withOpacity(.22)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF9DEDD6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    for (final point in points) {
      canvas.drawCircle(point, 2.8, Paint()..color = _cyan);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPersonalityPainter oldDelegate) =>
      oldDelegate.values != values;
}
