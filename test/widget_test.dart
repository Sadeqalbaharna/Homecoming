// The desktop shell shows Kai's REAL project state.
//
// ── What this test used to do ────────────────────────────────────────────────
//
// It asserted the opposite:
//
//     expect(source, contains('KAI SMARTER PROJECT'));
//     expect(source, contains('_smartProjectCard'));
//
// Those are the fossil. `_smartProjectCard()` was ~200 lines of hardcoded list
// rendering "7 / 7 layers complete" and "FULL STACK ONLINE" in green, forever,
// from a `const layers = [...]` where every entry said 'status': 'done'. The
// real project state at the time was 77% — 3 of 7 genuinely finished.
//
// It was a metric authored by the thing being measured, which is the one kind
// that always reads as success. Kai found it, called it "a cursed little museum
// exhibit", and cut it.
//
// And this test failed. The suite was GUARDING the propaganda: it required the
// lie to be present and would have gone red the moment anyone told the truth.
// A test that pins a hardcoded claim in place isn't a safety net, it's a
// ratchet — and this one had been holding "FULL STACK ONLINE" in place against
// a codebase that was 3/7.
//
// So it now asserts the inverse. The fossil must STAY dead, and the live
// surface — which reads KaiProjectService and reports real state — must be the
// thing that's mounted.
//
// Updated again under Brief 005: the live surface is now KaiProjectPortfolio,
// tracking Homecoming and Hoard against their own governed phases. The earlier
// version of this test required the two Kai-improvement boards to be mounted,
// which had quietly become the same fault at a higher level — a test holding
// the wrong subject in place. The propaganda guards below are untouched.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

  test('the shell is still the shell', () {
    expect(source, contains('KaiDesktopShell'));
  });

  group('the propaganda card stays dead', () {
    test('no hardcoded layer list', () {
      expect(source, isNot(contains('_smartProjectCard')),
          reason:
              'the fossil is back — ~200 lines of const layers, all "done"');
      expect(source, isNot(contains('_smartLayerTab')));
      expect(source, isNot(contains('_openSmarterLayer')),
          reason: 'state field that existed only to expand the fake card');
    });

    test('no hardcoded progress claims', () {
      // The exact strings. If any of these ever come back, something is
      // reporting a number it did not measure.
      expect(source, isNot(contains('7 / 7 layers complete')));
      expect(source, isNot(contains('FULL STACK ONLINE')));
    });

    test('no hardcoded LinearProgressIndicator at 1.0', () {
      // The green bar that was always full. Written as `value: 1.0` — not a
      // variable, not a computation. A progress bar that cannot show progress.
      expect(source, isNot(contains('value: 1.0')),
          reason: 'a progress indicator with a literal 1.0 is a decoration');
    });
  });

  group('the real surface is what is mounted', () {
    test('the real portfolio is mounted, not the Kai-improvement boards', () {
      // This test used to require `projectId: KaiProjectService.smarterId` and
      // `sentienceId` to be mounted in the shell. That was the same shape of
      // fault this file was written to prevent, one level up: it pinned two
      // Kai-improvement boards into the dashboard while the actual work was
      // Homecoming and Hoard, and it would have gone red the moment anyone
      // showed the real portfolio.
      //
      // The rails now mount KaiProjectPortfolio, which reads each project's own
      // governed phases, gate, proof state and blockers.
      expect('KaiProjectPortfolio('.allMatches(source).length,
          greaterThanOrEqualTo(2),
          reason: 'both the normal rail and the Persona-expanded rail');

      // The fixed cards are gone from the rails.
      expect(source, isNot(contains('projectId: KaiProjectService.smarterId')));
      expect(
          source, isNot(contains('projectId: KaiProjectService.sentienceId')));

      // Selecting any portfolio project opens the data-driven full HTML map.
      expect(source, contains('KaiProjectFlowchartService'));
      expect(source, contains('_openProjectFlowchart'));
      expect(source, isNot(contains('_openProjectDetails')));
    });

    test('desktop left rail can expand for the Persona messenger surface', () {
      expect(source, isNot(contains('width: 210,')),
          reason:
              'a fixed 210px rail miniaturises the mobile messenger mockup');
      expect(source, contains('MediaQuery.sizeOf(context).width'));
      expect(source, contains('380.0'));
      expect(source, contains('340.0'));
      expect(source, contains('300.0'));
    });
  });
}
