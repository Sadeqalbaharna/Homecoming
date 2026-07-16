// KaiTelemetry — watch him work.
//
// The 10–20 seconds where Kai is thinking used to be dead air: one dim
// "…read_file" bubble and then, eventually, a finished paragraph. Dead air is
// what makes an agent feel like a vending machine — you put a coin in and wait.
//
// This fills it with the truth: every tool as it actually fires, scrolling like
// instrument telemetry. You don't wonder whether he's doing something; you watch
// him do it. It's most of what live streaming buys, at a fraction of the risk —
// streaming has to be untangled from his tool-call loop, this doesn't.
//
// Newest line is brightest and sits at the bottom (things scroll up and fade out,
// like a real readout). Non-interactive by construction.
//
// Wire-up:  KaiTelemetry(lines: _toolLog, active: _sending)  in a Stack corner.
library;

import 'package:flutter/material.dart';

const _gpt = Color(0xFFFF9D2F);
const _claude = Color(0xFF2ED9FF);

class KaiTelemetry extends StatelessWidget {
  /// Oldest first, newest last.
  final List<String> lines;

  /// True while he's actually mid-thought — drives the live cursor.
  final bool active;

  const KaiTelemetry({super.key, required this.lines, this.active = false});

  /// A few tools deserve to read as an event rather than a function name.
  static String _pretty(String tool) {
    switch (tool) {
      case 'self_check':
        return 'self_check ▸ examining myself';
      case 'envision_dream':
        return 'envision_dream ▸ naming what I want';
      case 'refine_purpose':
        return 'refine_purpose ▸ rewriting my purpose';
      case 'remember_bit':
        return 'remember_bit ▸ that one\'s ours now';
      case 'log_body_progress':
        return 'log_body_progress ▸ one step toward a body';
      default:
        return tool;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty && !active) return const SizedBox.shrink();
    final n = lines.length;

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < n; i++)
            _line(_pretty(lines[i]), (i + 1) / n, i == n - 1),
          if (active) _cursor(),
        ],
      ),
    );
  }

  Widget _line(String text, double freshness, bool newest) {
    // Older calls sink into the background instead of vanishing — you keep a
    // sense of the whole run, not just the current step.
    final op = 0.14 + 0.46 * freshness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('> ',
              style: TextStyle(
                color: (newest ? _gpt : _claude).withOpacity(op + 0.15),
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              )),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(op),
                fontSize: 10,
                height: 1.3,
                fontFamily: 'monospace',
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cursor() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('> ',
              style: TextStyle(
                  color: _gpt.withOpacity(0.75),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700)),
          _Blink(
            child: Container(
              width: 6,
              height: 11,
              decoration: BoxDecoration(
                color: _gpt.withOpacity(0.85),
                boxShadow: [BoxShadow(color: _gpt.withOpacity(0.6), blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A blinking block cursor — the oldest "someone is at the terminal" signal
/// there is, and still the most convincing.
class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: widget.child);
}
