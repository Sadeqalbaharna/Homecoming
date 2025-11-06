import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// For kDebugMode
import 'package:window_manager/window_manager.dart';
import 'package:lottie/lottie.dart';

// Voice training imports
import 'widgets/voice_setup_dialog.dart';

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
  // --- Animation state ---
  String _currentAnimation = 'idle'; // 'idle', 'talk', 'attention', 'thinking', 'speaking'
  int _currentFrame = 0;
  AnimationController? _frameAnimController;
  
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
  
  // --- Animation switching ---
  void _switchAnimation(String animName) {
    setState(() {
      _currentAnimation = animName;
      _currentFrame = 0;
    });
    
    // For frame-based animations, setup controller
    if (animName == 'attention' || animName == 'thinking' || animName == 'speaking') {
      _frameAnimController?.dispose();
      final frameCount = animName == 'thinking' ? 241 : 121;
      _frameAnimController = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: frameCount * 40), // 40ms per frame
      )..addListener(() {
        setState(() {
          _currentFrame = (_frameAnimController!.value * frameCount).floor();
        });
      })..repeat();
    } else {
      _frameAnimController?.dispose();
      _frameAnimController = null;
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
    _frameAnimController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // == HALF SIZE ==
    const spriteSize = 240.0; // was ~480; tweak as you like

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Main draggable avatar in center
          GestureDetector(
            onPanStart: _startDrag,
            onPanUpdate: _drag,
            onPanEnd: _endDrag,
            onLongPress: _openVoiceTraining,
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
                      SizedBox(
                        width: spriteSize,
                        height: spriteSize,
                        child: _buildAnimation(),
                      ),

                      // Blink overlay (simple eyelid sweep). Tweak position/size to your art.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _BlinkPainter(progressOpen: _blink.value),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          
          // Voice training indicator (small icon in top-right)
          Positioned(
            top: 10,
            right: 10,
            child: GestureDetector(
              onTap: _openVoiceTraining,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.6),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Color(0xFFD4AF37),
                  size: 16,
                ),
              ),
            ),
          ),
          
          // Floating toggle button (top layer)
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
          
          // Animation controller buttons
          Positioned(
            bottom: 10,
            left: 10,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white38, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _animButton('idle', 'Idle'),
                    _animButton('talk', 'Talk'),
                    _animButton('attention', 'Att'),
                    _animButton('thinking', 'Think'),
                    _animButton('speaking', 'Speak'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Build animation widget based on current selection
  Widget _buildAnimation() {
    switch (_currentAnimation) {
      case 'idle':
        return Lottie.asset(
          'assets/avatar/kai_idle.json',
          fit: BoxFit.contain,
          repeat: true,
          animate: true,
        );
      case 'talk':
        return Lottie.asset(
          'assets/avatar/kai_talk.json',
          fit: BoxFit.contain,
          repeat: true,
          animate: true,
        );
      case 'attention':
      case 'thinking':
      case 'speaking':
        // Frame-based animation
        String frameDir = _currentAnimation == 'attention' 
          ? 'attention_frames'
          : _currentAnimation == 'thinking'
          ? 'thinking_frames'
          : 'speaking_frames';
        return Image.asset(
          'assets/avatar/$frameDir/frame_${_currentFrame.toString().padLeft(4, '0')}.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Icon(Icons.error, color: Colors.red),
        );
      default:
        return const Icon(Icons.person, size: 100, color: Colors.white);
    }
  }
  
  // Animation button widget
  Widget _animButton(String animName, String label) {
    final isActive = _currentAnimation == animName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => _switchAnimation(animName),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.greenAccent.withOpacity(0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.greenAccent : Colors.white70,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// Open voice training setup
  void _openVoiceTraining() {
    HapticFeedback.mediumImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const VoiceSetupDialog(),
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
