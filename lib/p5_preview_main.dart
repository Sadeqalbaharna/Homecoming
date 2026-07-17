// A window onto the messenger. Runs on its own, wired to nothing.
//
//   flutter run -d windows -t lib/p5_preview_main.dart
//   flutter run -d <phone> -t lib/p5_preview_main.dart
//
// No Firebase, no OpenAI, no persona, no secrets — so it starts in a second and
// can't break anything. Change a number in kai_p5_chat.dart, hot reload, look.
//
// ── Why this file exists ─────────────────────────────────────────────────────
//
// The proactive nudge was written correct and unobservable: 25 minutes idle, a
// 45-minute cooldown, a 1-in-4 dice roll and one of six options at random before
// you could see it fire ONCE. So it was built blind and iterated on blind, which
// is the same wall run_tests was built to break — the person who has to answer
// "did that work?" being the only one who can't.
//
// A UI you can only judge by launching the real app, signing in, and provoking a
// real reply has that disease in a nicer hat. Tuning a tilt angle should cost a
// hot reload, not a round trip through OpenAI.
library;

import 'package:flutter/material.dart';

import 'widgets/kai_p5_chat.dart';

void main() => runApp(const _P5PreviewApp());

class _P5PreviewApp extends StatelessWidget {
  const _P5PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kai — messenger preview',
        debugShowCheckedModeBanner: false,
        home: const P5ChatDemo(),
      );
}
