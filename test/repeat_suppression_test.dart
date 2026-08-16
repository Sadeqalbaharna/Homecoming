// Telling a long outage apart from a loud one.
//
// 968 activity_stream_unavailable and 482 request_stream_unavailable entries in
// 48 hours, all from the laptop sleeping. Every retry logged at the same volume
// as the first, until the journal had rotated at 2MB and a genuine outage was
// indistinguishable from an ordinary night.
//
// The decisions underneath were all correct. It was the record that was useless.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/repeat_suppression.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 16, 2);

  group('the first one always speaks', () {
    test('a single occurrence is emitted', () {
      final s = RepeatSuppressor();
      expect(s.record('stream:activity', t0).shouldEmit, isTrue);
    });

    test('different keys do not suppress each other', () {
      final s = RepeatSuppressor();
      expect(s.record('stream:activity', t0).shouldEmit, isTrue);
      expect(s.record('stream:request', t0).shouldEmit, isTrue,
          reason: 'two subsystems failing is two facts, not one');
    });

    test('a one-off leaves no summary to write', () {
      final s = RepeatSuppressor();
      s.record('stream:activity', t0);
      expect(s.resolve('stream:activity'), isNull,
          reason: 'the original line already said everything');
    });
  });

  group('the storm is counted, not repeated', () {
    test('retries two seconds apart are swallowed', () {
      // The real cadence from the journal: 10:31:02, :04, :06.
      final s = RepeatSuppressor();
      expect(s.record('k', t0).shouldEmit, isTrue);
      for (var i = 2; i <= 50; i += 2) {
        expect(s.record('k', t0.add(Duration(seconds: i))).shouldEmit, isFalse,
            reason: 'second $i');
      }
      expect(s.totalFor('k'), 26);
    });

    test('nothing is lost — the count survives the silence', () {
      final s = RepeatSuppressor();
      s.record('k', t0);
      for (var i = 2; i <= 58; i += 2) {
        s.record('k', t0.add(Duration(seconds: i)));
      }
      // One minute in, the schedule comes due and the line says what it stands for.
      final due = s.record('k', t0.add(const Duration(seconds: 61)));
      expect(due.shouldEmit, isTrue);
      expect(due.suppressedSinceLastEmit, 29);
    });

    test('an episode that ends reports its full weight', () {
      final s = RepeatSuppressor();
      s.record('k', t0);
      for (var i = 1; i <= 400; i++) {
        s.record('k', t0.add(Duration(seconds: i * 3)));
      }
      final summary = s.resolve('k');
      expect(summary, isNotNull);
      expect(summary!.total, 401);
      expect(summary.duration, const Duration(seconds: 1200));
      expect(summary.key, 'k');
    });
  });

  group('a long outage never goes silent', () {
    test('the schedule escalates instead of stopping', () {
      final s = RepeatSuppressor();
      final emits = <Duration>[];
      var elapsed = Duration.zero;
      s.record('k', t0);
      // Eight hours of failures every 5 seconds.
      for (var sec = 5; sec <= 8 * 3600; sec += 5) {
        elapsed = Duration(seconds: sec);
        if (s.record('k', t0.add(elapsed)).shouldEmit) emits.add(elapsed);
      }
      // Front-loaded then sparse: roughly one line an hour once settled.
      expect(emits.length, lessThan(15),
          reason: 'must not reproduce the wall of text');
      expect(emits.length, greaterThan(5),
          reason: 'and must not go quiet on a genuine eight-hour outage');
      expect(emits.last.inHours, greaterThanOrEqualTo(6),
          reason: 'still reporting near the end of the episode');
    });

    test('the gaps grow rather than staying flat', () {
      final s = RepeatSuppressor();
      final emits = <int>[];
      s.record('k', t0);
      for (var sec = 5; sec <= 4 * 3600; sec += 5) {
        if (s.record('k', t0.add(Duration(seconds: sec))).shouldEmit) {
          emits.add(sec);
        }
      }
      final gaps = [
        for (var i = 1; i < emits.length; i++) emits[i] - emits[i - 1]
      ];
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThanOrEqualTo(gaps[i - 1]),
            reason: 'gap $i shrank: $gaps');
      }
    });
  });

  group('recovery closes the episode', () {
    test('after resolve, the next failure is a fresh first', () {
      final s = RepeatSuppressor();
      s.record('k', t0);
      s.record('k', t0.add(const Duration(seconds: 2)));
      s.resolve('k');
      expect(s.isOpen('k'), isFalse);
      expect(s.record('k', t0.add(const Duration(minutes: 30))).shouldEmit,
          isTrue, reason: 'a new outage is news again');
    });

    test('resolving something that was never failing is a no-op', () {
      final s = RepeatSuppressor();
      expect(s.resolve('never-failed'), isNull);
      expect(s.isOpen('never-failed'), isFalse);
    });
  });

  group('the summary is a log line, not a payload', () {
    test('it carries counts and times and nothing else', () {
      final s = RepeatSuppressor();
      s.record('attention:no_suitable_body_online', t0);
      s.record('attention:no_suitable_body_online',
          t0.add(const Duration(minutes: 1)));
      final json = s.resolve('attention:no_suitable_body_online')!.toJson();
      expect(json.keys.toSet(), {
        'key',
        'occurrences',
        'firstAt',
        'lastAt',
        'durationSeconds',
      });
      // The key is a kind, never content. Journal privacy depends on callers
      // fingerprinting by category, and this is where that is asserted.
      expect(json['key'], isNot(contains(' ')));
    });
  });
}
