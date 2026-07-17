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

// ── Wiring the real one into the phone ───────────────────────────────────────
//
// KaiP5ChatScreen (lib/screens/kai_p5_chat_screen.dart) is the live version —
// real history, real AIService, real replyCeiling. It is NOT wired into
// main_mobile yet, because main_mobile is 2,200 lines of avatar, flame overlay,
// wake word and hold-to-speak, and cutting a door into that at 2am is how you
// break the thing that works to reach the thing that doesn't.
//
// It needs one route and one way in — a button on the avatar screen, or the
// bubble tap opening the full conversation instead of showing one reply. That's
// a daylight job.
//
// Until then it can be run directly and it is fully live:
//
//   flutter run -d <phone> -t lib/p5_preview_main.dart
//
// …after swapping the `home:` above for:
//
//   const KaiP5ChatScreen(personaId: 'truekai', model: 'gpt-5.5')
//
// which needs Firebase initialised first, since it loads real history — so that
// swap belongs in main_mobile's boot, not here. This file stays dumb on purpose:
// no Firebase, no keys, starts in a second, can't break anything.
