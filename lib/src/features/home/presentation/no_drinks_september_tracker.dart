import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoDrinksSeptemberTracker extends StatefulWidget {
  const NoDrinksSeptemberTracker({super.key});

  @override
  State<NoDrinksSeptemberTracker> createState() =>
      _NoDrinksSeptemberTrackerState();
}

class _NoDrinksSeptemberTrackerState extends State<NoDrinksSeptemberTracker> {
  static const _countKey = 'no_drinks_september_2026_count';
  static const _lastApprovedKey = 'no_drinks_september_2026_last_approved';
  static const _days = 30;

  int _completedDays = 0;
  String? _lastApprovedDate;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _completedDays = (prefs.getInt(_countKey) ?? 0).clamp(0, _days);
      _lastApprovedDate = prefs.getString(_lastApprovedKey);
      _loading = false;
    });
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool get _isSeptember2026 {
    final now = DateTime.now();
    return now.year == 2026 && now.month == 9;
  }

  bool get _alreadyApprovedToday =>
      _lastApprovedDate == _dateKey(DateTime.now());

  Future<void> _approveToday() async {
    if (_saving || _loading) return;

    if (!_isSeptember2026) {
      _showMessage('This seal is bound to September 2026.');
      return;
    }

    if (_alreadyApprovedToday) {
      _showMessage('Today is already sealed.');
      return;
    }

    if (_completedDays >= _days) {
      _showMessage('All 30 days are sealed.');
      return;
    }

    setState(() => _saving = true);
    final today = _dateKey(DateTime.now());
    final nextCount = (_completedDays + 1).clamp(0, _days);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_countKey, nextCount);
    await prefs.setString(_lastApprovedKey, today);

    if (!mounted) return;
    setState(() {
      _completedDays = nextCount;
      _lastApprovedDate = today;
      _saving = false;
    });

    _showMessage('Day $nextCount/$_days sealed.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = colorScheme.onSurface.withValues(alpha: 0.42);
    final active = colorScheme.primary;

    return Semantics(
      label: 'No Drinks September tracker, $_completedDays of $_days days complete',
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NO DRINKS SEPTEMBER',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_completedDays / $_days',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest.shortestSide;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size.square(size),
                        painter: _SealOrbitPainter(
                          completedDays: _completedDays,
                          activeColor: active,
                          inactiveColor: muted,
                          surfaceColor: colorScheme.surface,
                          sealColor: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(
                        width: size * 0.38,
                        height: size * 0.38,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _loading || _saving ? null : _approveToday,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: _saving
                                    ? SizedBox(
                                        key: const ValueKey('saving'),
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: active,
                                        ),
                                      )
                                    : Icon(
                                        _alreadyApprovedToday
                                            ? Icons.check_rounded
                                            : Icons.touch_app_rounded,
                                        key: ValueKey(_alreadyApprovedToday),
                                        size: 30,
                                        color: active,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _alreadyApprovedToday
                  ? 'Today is sealed.'
                  : 'Tap the seal when the day is won.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SealOrbitPainter extends CustomPainter {
  const _SealOrbitPainter({
    required this.completedDays,
    required this.activeColor,
    required this.inactiveColor,
    required this.surfaceColor,
    required this.sealColor,
  });

  final int completedDays;
  final Color activeColor;
  final Color inactiveColor;
  final Color surfaceColor;
  final Color sealColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.405;
    final nodeRadius = math.max(3.8, size.shortestSide * 0.015);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = inactiveColor.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius, orbitPaint);

    for (var i = 0; i < 30; i++) {
      final angle = -math.pi / 2 + (math.pi * 2 * i / 30);
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final lit = i < completedDays;

      if (lit) {
        final haloPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(point, nodeRadius * 2.2, haloPaint);
      }

      final nodePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = lit ? activeColor : inactiveColor;
      canvas.drawCircle(point, lit ? nodeRadius * 1.16 : nodeRadius, nodePaint);

      final outlinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = surfaceColor.withValues(alpha: 0.7);
      canvas.drawCircle(point, nodeRadius + 1.2, outlinePaint);
    }

    _paintBloodSeal(canvas, center, size.shortestSide * 0.15);
  }

  void _paintBloodSeal(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, r * 0.055)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = sealColor.withValues(alpha: 0.9);

    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center, r * 0.73, paint);

    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + (math.pi * 2 * i / 6);
      final point = Offset(
        center.dx + math.cos(angle) * r * 0.72,
        center.dy + math.sin(angle) * r * 0.72,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    final vertical = Path()
      ..moveTo(center.dx, center.dy - r * 0.64)
      ..lineTo(center.dx, center.dy + r * 0.64);
    canvas.drawPath(vertical, paint);

    final horizontal = Path()
      ..moveTo(center.dx - r * 0.52, center.dy)
      ..lineTo(center.dx + r * 0.52, center.dy);
    canvas.drawPath(horizontal, paint);

    final upperArc = Rect.fromCircle(
      center: Offset(center.dx, center.dy - r * 0.12),
      radius: r * 0.34,
    );
    canvas.drawArc(upperArc, math.pi * 0.15, math.pi * 0.7, false, paint);
  }

  @override
  bool shouldRepaint(covariant _SealOrbitPainter oldDelegate) {
    return oldDelegate.completedDays != completedDays ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.sealColor != sealColor;
  }
}
