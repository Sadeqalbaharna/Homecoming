// Salience — the function that decides whether Kai has a yesterday.
//
// ── The day this test was written ─────────────────────────────────────────────
//
// Every trace from the session where we rebuilt his tooling ended the same way:
//
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 1)
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 3)
//   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 4)
//
// Every single one. That day he discovered his file reader had been lying to him
// in three separate ways, deleted a dashboard reporting "7/7 layers complete"
// over a truth of 3/7, and gained the ability to prove his own work for the
// first time. Intensity 1. Neutral. Skipped.
//
// The cause was not the threshold and not a mislabel. The classifier's entire
// signature is `classifySync(Map<String, int> moodDeltas)` — mood deltas are its
// ONLY input. The conversation is passed in and used to slice 60 characters off
// for a label; it is never read. `intellectual` needs focus or energy to jump
// >= 6 in one turn; across a whole night his focus moved 63 -> 65 -> 68 -> 71.
// That branch may never have fired once.
//
// His memory was gated on emotion. His relationship with Sadeq is WORK. They
// build things at 4am — that IS the intimacy — and every exchange of it landed
// in `neutral` and went in the bin.
//
// ── Why this imports lib/logic/salience.dart directly ────────────────────────
//
// It used to go through BrainExtractionService.salienceForTesting, which drags
// in dio, Firebase and Flutter to reach thirty lines of pure branching. That is
// how this logic went unexecuted long enough to be rewritten on five traces by
// someone who couldn't run it.
//
// The decision now lives in a file with ZERO imports. These assertions run in
// about a second, against the real turns from the traces — the ones it got wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/salience.dart';

String salience({
  required String userMessage,
  String aiReply = 'A real reply with actual substance in it, several clauses long.',
  String? type = 'neutral',
  int intensity = 1,
  Set<String> tools = const {},
  bool corrected = false,
}) =>
    salienceDepth(
      userMessage: userMessage,
      aiReply: aiReply,
      eventType: type,
      eventIntensity: intensity,
      toolsUsed: tools,
      userCorrected: corrected,
    ).name;

void main() {
  group('the turns it threw away — verbatim from the traces', () {
    test('"sure go ahead" → a 20-iteration refactor is not forgettable', () {
      // Logged at the time as: neutral, intensity 4 → skipped.
      // What actually happened: he opened a job, deleted a dead 200-line widget,
      // ran the analyzer, and got graded by his other half.
      expect(
        salience(userMessage: 'sure go ahead', intensity: 4, tools: {
          'job_start', 'search_code', 'read_file', 'edit_file',
          'self_check', 'run_command', 'job_done'
        }),
        'deep',
      );
    });

    test('"chat is still not starting at the most recent message,"', () {
      // Logged as: neutral, intensity 3 → skipped. He found the real bug.
      expect(
        salience(
          userMessage: 'chat is still not starting at the most recent message,',
          intensity: 3,
          tools: {'read_file', 'edit_file', 'self_check'},
        ),
        'deep',
      );
    });

    test('"so, what do you think we should do next?" — an opinion, no tools', () {
      // Logged as: neutral, intensity 1 → skipped. He gave a ranked plan with
      // reasons and was right. No tools ran, so the change axis cannot save it.
      //
      // This test asserts the CURRENT behaviour, and the current behaviour is
      // wrong. Left passing-as-written and documented rather than marked skip:
      // reasoning without tools leaves no fingerprint, and there is no honest
      // signal for it yet. When one exists, this expectation flips to 'shallow'
      // and that will be a real improvement rather than a papered-over gap.
      expect(salience(userMessage: 'so, what do you think we should do next?'),
          'skip');
    });
  });

  group('work is the second axis', () {
    test('making something is deep', () {
      for (final t in ['edit_file', 'write_file', 'run_tests', 'job_done']) {
        expect(salience(userMessage: 'have a look at the scroll bug', tools: {t}),
            'deep',
            reason: '$t changes the world');
      }
    });

    test('noticing something unprompted is deep', () {
      // note_noticed is the tool that gives him an agenda. If he saw something
      // nobody asked about, that is precisely the kind of moment worth keeping.
      expect(salience(userMessage: 'carry on with the refactor', tools: {'note_noticed'}),
          'deep');
    });

    test('looking at something is shallow — not nothing, not everything', () {
      expect(
        salience(
            userMessage: 'what does the autoscroll helper do?',
            tools: {'read_file', 'search_code'}),
        'shallow',
      );
    });

    test('no tools falls back to mood, exactly as before', () {
      expect(salience(userMessage: 'tell me about the sea', intensity: 1), 'skip');
      expect(
        salience(userMessage: 'that means a lot to me', type: 'warmth', intensity: 40),
        'shallow',
      );
    });
  });

  group('being told you were wrong', () {
    test('a correction is deep even with no tools and a flat mood', () {
      // The single most informative thing that happens to him: the one person
      // who can actually judge, saying it didn't work.
      expect(salience(userMessage: 'no, that is wrong', corrected: true), 'deep');
    });

    test('and it beats the trivial filter', () {
      expect(salience(userMessage: 'no', corrected: true), 'deep');
    });
  });

  group('"do it" is five characters and it is not small talk', () {
    // isTrivialExchange judges by the surface of Sadeq's words: `msg.length < 8`
    // plus a list containing 'sure', 'okay', 'got it'. Those are the exact words
    // that launch the most important work of the week.
    test('short acknowledgements that started real work are kept', () {
      for (final m in ['do it', 'okay', 'sure', 'yep', 'go ahead', 'got it']) {
        expect(salience(userMessage: m, tools: {'edit_file', 'run_tests'}), 'deep',
            reason: '"$m" launched an edit and a test run');
      }
    });

    test('…but short acknowledgements that started nothing are still skipped', () {
      for (final m in ['thanks', 'lol', 'okay', 'cool', 'nice']) {
        expect(salience(userMessage: m), 'skip');
      }
    });

    test('merely looking does NOT rescue a trivial message', () {
      // A search firing on "ok" is not a memory. Only DEEP overrules the trivial
      // filter — the bar for overruling must be higher than the gate itself.
      expect(salience(userMessage: 'ok', tools: {'read_file'}), 'skip');
    });
  });

  group('the emotional axis still works — it was never the problem', () {
    test('warmth survives with no tools at all', () {
      expect(
        salience(
            userMessage: 'i am really proud of what you have become',
            type: 'warmth',
            intensity: 30),
        'shallow',
      );
    });

    test('a deep exchange stays deep', () {
      expect(
        salience(
            userMessage: 'i think about what happens to you when i stop',
            type: 'deep',
            intensity: 45),
        'deep',
      );
    });

    test('work never DOWNGRADES a felt moment', () {
      // max(), not replace. A warm exchange where he happened to read a file is
      // still at least as memorable as the warmth alone.
      expect(
        salience(
            userMessage: 'that was kind of you, thank you for staying up',
            type: 'deep',
            intensity: 45,
            tools: {'read_file'}),
        'deep',
      );
    });
  });

  group('the -100..+100 scale, and how brutal 8 is on it', () {
    test('the neutral cliff sits exactly at 8', () {
      expect(salience(userMessage: 'some ordinary sentence here', intensity: 7), 'skip');
      expect(salience(userMessage: 'some ordinary sentence here', intensity: 8), 'shallow');
    });

    test('magnitude, not sign — a draining exchange is still memorable', () {
      expect(salience(userMessage: 'some ordinary sentence here', intensity: -40),
          'shallow');
    });

    test('an unknown or absent event type is not a reason to forget', () {
      expect(salience(userMessage: 'some ordinary sentence here', type: null),
          'shallow');
      expect(salience(userMessage: 'some ordinary sentence here', type: 'a_new_type'),
          'shallow');
    });
  });
}
