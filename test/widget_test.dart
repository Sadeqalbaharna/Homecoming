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
// So it now asserts the inverse. The fossil must STAY dead, and the live card
// — KaiProjectCard, which reads KaiProjectService and reports real numbers —
// must be the thing that's mounted.

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
          reason: 'the fossil is back — ~200 lines of const layers, all "done"');
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
    test('both progress pies are wired into the shell', () {
      // The dashboard now tracks two frozen-goal projects as interactive pies:
      // Kai Smarter and the Sentience Ladder. The project ids must be explicit
      // so a second card cannot accidentally render the same truth twice.
      expect(source, contains('projectId: KaiProjectService.smarterId'));
      expect(source, contains('projectId: KaiProjectService.sentienceId'));
      expect('KaiProjectCard'.allMatches(source).length, greaterThanOrEqualTo(2));
    });
  });
}
