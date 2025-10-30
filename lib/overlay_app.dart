import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:window_manager/window_manager.dart';
import 'package:lottie/lottie.dart';

class KaiOverlay extends StatelessWidget {
  const KaiOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
      home: const _FloatingKai(),
    );
  }
}

class _FloatingKai extends StatefulWidget {
  const _FloatingKai();

  @override
  State<_FloatingKai> createState() => _FloatingKaiState();
}

class _FloatingKaiState extends State<_FloatingKai> with TickerProviderStateMixin {
  // --- floating movement ---
  bool _isFloating = false;
  Timer? _floatingTimer;
  final _floatingRng = Random();
  
  void _toggleFloating() {
    setState(() {
      _isFloating = !_isFloating;
    });
    
    if (_isFloating) {
      _startFloating();
    } else {
      _stopFloating();
    }
  }
  
  void _startFloating() {
    _floatingTimer?.cancel();
    _floatingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isFloating || !mounted) {
        timer.cancel();
        return;
      }
      
      // Get current position
      final pos = await windowManager.getPosition();
      
      // Generate random movement (small steps)
      final dx = (_floatingRng.nextDouble() - 0.5) * 50; // -25 to +25 pixels
      final dy = (_floatingRng.nextDouble() - 0.5) * 50;
      
      // Move to new position
      await windowManager.setPosition(Offset(pos.dx + dx, pos.dy + dy));
    });
  }
  
  void _stopFloating() {
    _floatingTimer?.cancel();
    _floatingTimer = null;
  }
  
  // --- window drag (same as before) ---
  Offset _dragStart = Offset.zero;
  void _startDrag(DragStartDetails d) {
    _dragStart = d.globalPosition;
    // Pause floating during drag
    if (_isFloating) {
      _floatingTimer?.cancel();
    }
  }
  
  void _drag(DragUpdateDetails d) async {
    final pos = await windowManager.getPosition();
    final delta = d.globalPosition - _dragStart;
    _dragStart = d.globalPosition;
    await windowManager.setPosition(Offset(pos.dx + delta.dx, pos.dy + delta.dy));
  }
  
  void _endDrag(DragEndDetails d) {
    // Resume floating after drag if enabled
    if (_isFloating) {
      _startFloating();
    }
  }

  // --- blink animation ---
  late final AnimationController _blinkCtrl;
  late final Animation<double> _blink; // 1.0 open -> 0.0 closed
  final _rng = Random();

  void _scheduleNextBlink() async {
    final wait = 1800 + _rng.nextInt(2500); // 1.8–4.3s between blinks
    await Future.delayed(Duration(milliseconds: wait));
    if (!mounted) return;
    // quick close-open (like a real blink)
    await _blinkCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 70));
    await _blinkCtrl.reverse();
    _scheduleNextBlink();
  }

  // --- candle glow pulse ---
  late final AnimationController _glowCtrl;
  late final Animation<double> _glow; // 0..1 intensity

  @override
  void initState() {
    super.initState();
    
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 110),
    );
    _blink = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _blinkCtrl,
      curve: Curves.easeIn,
      reverseCurve: Curves.easeOut,
    ));
    _scheduleNextBlink();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.35, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glowCtrl);
  }

  @override
  void dispose() {
    _stopFloating();
    _blinkCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // == HALF SIZE ==
    const spriteSize = 240.0; // was ~480; tweak as you like

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: _startDrag,
        onPanUpdate: _drag,
        onPanEnd: _endDrag,
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_glow, _blink]),
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Pulsing candle glow ring (thin)
                  SizedBox(
                    width: spriteSize + 24,
                    height: spriteSize + 24,
                    child: CustomPaint(
                      painter: _GlowRingPainter(intensity: _glow.value),
                    ),
                  ),

                  // === YOUR SPRITE ===
                  // Using Lottie animation (much better than GIF!)
                  SizedBox(
                    width: spriteSize,
                    height: spriteSize,
                    child: Lottie.asset(
                      'assets/avatar/kai_talk.json', // Using talking animation
                      fit: BoxFit.contain,
                      repeat: true,
                      animate: true,
                    ),
                  ),

                  // Blink overlay (simple eyelid sweep). Tweak position/size to your art.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _BlinkPainter(progressOpen: _blink.value),
                      ),
                    ),
                  ),
                  
                  // Floating toggle button
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleFloating,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isFloating ? Colors.greenAccent : Colors.white38,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _isFloating ? Icons.pause : Icons.play_arrow,
                            color: _isFloating ? Colors.greenAccent : Colors.white,
                            size: 20,
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
      ),
    );
  }
}

/// Thin, warm glow that "breathes" like candlelight.
class _GlowRingPainter extends CustomPainter {
  final double intensity;
  const _GlowRingPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2;

    // outer soft halo
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..color = const Color(0xFFFFE7B0).withOpacity(0.25 * intensity);
    canvas.drawCircle(c, r - 6, halo);

    // inner, very subtle ring
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFD38A).withOpacity(0.6 * (0.6 + 0.4 * intensity));
    canvas.drawCircle(c, r - 10, ring);
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter old) =>
      old.intensity != intensity;
}

/// Draws a horizontal "eyelid" that closes briefly. Adjust rect to your sprite.
class _BlinkPainter extends CustomPainter {
  final double progressOpen; // 1.0 open -> 0.0 closed
  const _BlinkPainter({required this.progressOpen});

  @override
  void paint(Canvas canvas, Size size) {
    // position/size of the eye region as a fraction of the sprite rect.
    // Tweak these 4 numbers to match your art.
    final left = size.width * 0.34;
    final top = size.height * 0.29;
    final w = size.width * 0.34;
    final h = size.height * 0.16;

    final eyeRect = Rect.fromLTWH(left, top, w, h);
    final paint = Paint()..color = const Color(0xFF3A2B1E).withOpacity(0.85);

    // draw a rounded eyelid that slides from top to bottom as it closes
    final closedHeight = eyeRect.height;
    final currentHeight = closedHeight * (1 - progressOpen);
    final lidRect = Rect.fromLTWH(
      eyeRect.left,
      eyeRect.top,
      eyeRect.width,
      currentHeight,
    );
    final r = Radius.circular(eyeRect.height * 0.35);
    final rrect = RRect.fromRectAndCorners(
      lidRect,
      topLeft: r,
      topRight: r,
      bottomLeft: r,
      bottomRight: r,
    );

    if (currentHeight > 1) {
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlinkPainter old) =>
      old.progressOpen != progressOpen;
}
