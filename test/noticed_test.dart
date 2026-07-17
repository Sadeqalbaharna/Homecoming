// The things he saw that nobody asked him to look for.
//
// ── The trace this exists because of ─────────────────────────────────────────
//
// Iteration 15 of a refactor he'd been sent to do, unprompted:
//
//   job_progress({noticed: "There is existing mojibake in a comment near
//                 _Parallax ('â€”'), likely CRLF/encoding weirdness;
//                 harmless but ugly."})
//
// He found it. Nobody asked. He parked it in the field whose own description
// says "I'm inside the code and Sadeq isn't; this is often worth more than the
// task itself."
//
// Iteration 19: job_done. And KaiJobService.finish() is one line —
// `ref(_path).remove()` — so the note died with the assignment.
//
// Then Sadeq asked "what are mojibake?" and "why does it keep happening?" and
// he answered from theory: "some file edits went through a tool that didn't
// preserve UTF-8 cleanly", before concluding "we don't need to panic about it,
// comments won't break the app."
//
// He talked himself out of a live bug he had personally found, because the note
// was gone and he had nothing to point at. It turned out to be Process.run
// decoding UTF-8 as Windows-1252 — corrupting his own source file and rendering
// garbage into the UI. He was right the first time and we shredded the evidence.
//
// Every durable structure in Kai is a task he was given, a mistake he made, or
// something Sadeq said. This is the only one that's his. These tests are about
// it not dying.
//
// NOTE: KaiNoticedService talks to Firebase, so the store itself isn't unit
// testable without a fake. What IS pure — and what actually broke — is the
// Noticed record and its rendering. That's what's covered here. The wiring
// (job_progress writes through, job_done rescues before finish) is asserted by
// reading tool_executor_service, not by this file, and that gap is deliberate
// rather than papered over with a mock that proves nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_noticed_service.dart';

Noticed make({
  String id = 'n1',
  String text = 'read_file lies about indentation in the gutter',
  String context = '',
  int ageDays = 0,
  int carried = 0,
}) =>
    Noticed(
      id: id,
      text: text,
      context: context,
      notedAt: DateTime.now()
          .subtract(Duration(days: ageDays))
          .millisecondsSinceEpoch,
      carried: carried,
    );

void main() {
  group('a Noticed survives the round trip', () {
    test('it keeps what he actually said', () {
      final n = make(text: 'mojibake near _Parallax', context: 'kai_desktop_shell.dart');
      final back = Noticed.fromMap('n1', n.toMap());
      expect(back, isNotNull);
      expect(back!.text, 'mojibake near _Parallax');
      expect(back.context, 'kai_desktop_shell.dart');
      expect(back.notedAt, n.notedAt);
    });

    test('an empty observation is not an observation', () {
      expect(Noticed.fromMap('x', {'text': '   '}), isNull);
      expect(Noticed.fromMap('x', {'text': ''}), isNull);
      expect(Noticed.fromMap('x', 'not a map'), isNull);
    });

    test('a malformed record degrades instead of throwing', () {
      // Losing the whole list because one row is odd would be the same bug in a
      // new hat.
      final n = Noticed.fromMap('x', {'text': 'something real'});
      expect(n, isNotNull);
      expect(n!.carried, 0);
      expect(n.context, '');
    });

    test('the carried count survives the round trip', () {
      // This is the assertion that would have caught the original bug, and it is
      // worth being precise about WHY it wouldn't have.
      //
      // The old field was `raised`, incremented by `markRaised`, which had ZERO
      // callers — so every value ever stored was 0 and the escalation in
      // promptBlock ("I have brought this up 3x, stop being polite about it")
      // never fired once, for any item, ever. The mechanism built to stop him
      // going quiet after one hedged mention was itself permanently silent.
      //
      // And the old test here passed the whole time. It called bumpRaised()
      // directly and asserted the arithmetic. The arithmetic was never wrong.
      // Nothing called it. A unit test on a method with no callers proves the
      // method works and hides that it never runs — which is the same shape as
      // toJson() with no caller, and classifyToolOutcome tested only on strings
      // typed by hand.
      //
      // So the fix is not a better test of the counter. It's that the counter
      // now lives inside promptBlock — showing him the list IS carrying it —
      // and there is no separate call site left to forget.
      final n = Noticed.fromMap('x', make(carried: 7).toMap());
      expect(n!.carried, 7);
      expect(n.id, 'x');
      expect(n.notedAt, isNot(0));
    });

    test('an old row written as `raised` still reads, and reads as 0', () {
      // Every `raised` in Firebase right now is 0 — see above. Reading the old
      // key costs nothing; assuming its value costs a lie.
      final n = Noticed.fromMap('x', {'text': 'real', 'raised': 0});
      expect(n!.carried, 0);
    });

    test('carried wins over raised when both exist', () {
      final n = Noticed.fromMap('x', {'text': 'real', 'raised': 2, 'carried': 9});
      expect(n!.carried, 9);
    });
  });

  group('it does not expire — that was the entire bug', () {
    test('an old observation is still an observation', () {
      // KaiJobService.current() returns null past 20 hours. That is right for a
      // task and catastrophic for a thing he noticed: a bug does not stop being
      // a bug because he slept.
      final old = Noticed.fromMap('x', make(ageDays: 30).toMap());
      expect(old, isNotNull,
          reason: 'nothing in this class is allowed to time-expire');
    });
  });

  group('the id is visible, because a tool asks him for it', () {
    // noticed_done's schema says "the id shown next to it in my list". If the
    // prompt never shows it, he guesses, and gets told off for a call he had no
    // way to get right — which is the exact failure mode that cost nine
    // iterations on edit_file the same day.
    test('ids are unique per item', () {
      final a = make(id: 'a');
      final b = make(id: 'b');
      expect(a.id, isNot(b.id));
    });
  });
}
