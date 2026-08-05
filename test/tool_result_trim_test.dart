// _trimOldToolResults — the bug that shredded his working set.
//
// The intent, from its own doc comment: "old bulky results get clipped while the
// most recent [keepWhole] stay untouched (those are his active working set)".
//
// What it did: when there were FEWER than keepWhole results — i.e. at the start
// of every single job, when they're all he has — it clipped ALL of them to 500
// characters. `cutoff = -1`, and the keep-branch was guarded by `cutoff != -1`,
// so the keep-branch was unreachable in exactly the case it mattered most.
//
// The cost wasn't tokens. It was that he read a file and it was gone by the next
// iteration. From a real trace, reading one 107-line function:
//
//   "the first read got trimmed"
//   "still trimming right at the juicy bit"
//   "going stupidly small now — scalpel, not shovel"
//   "Tiny bites beat the trimming gremlin"
//
// Thirteen iterations, ever-smaller slices, cheerfully blaming a gremlin. That
// "surgical" reading style was a coping strategy for amnesia we inflicted.
//
// This test exists because the logic is pure, the bug was one boolean, and
// nothing was watching.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/ai_service.dart';

/// A tool message with `len` characters of content.
///
/// [name] matters now: reads are MATERIALS he has to quote back verbatim into
/// an edit_file several iterations later, so they survive longer than a
/// job_start ack he glanced at once. Default is a non-read tool, so every test
/// written before that distinction existed still measures what it meant to.
Map<String, dynamic> tool(String id, int len, {String name = 'self_check'}) => {
      'role': 'tool',
      'tool_call_id': id,
      'name': name,
      'content': 'x' * len,
    };

Map<String, dynamic> read(String id, int len) =>
    tool(id, len, name: 'read_file');

Map<String, dynamic> user(String t) => {'role': 'user', 'content': t};
Map<String, dynamic> asst(String t) => {'role': 'assistant', 'content': t};
Map<String, dynamic> asstToolCall(String id, String name, int argLen) => {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': id,
          'type': 'function',
          'function': {
            'name': name,
            'arguments': '{"payload":"${'x' * argLen}"}',
          },
        }
      ],
    };

bool _isWhole(Map<String, dynamic> m, int len) =>
    (m['content'] as String).length == len;
bool _isClipped(Map<String, dynamic> m) =>
    (m['content'] as String).contains('older result trimmed');

void main() {
  group('the working set survives — the bug', () {
    test('a single big result is NOT old-clipped, but huge blobs are capped', () {
      // THE regression. One read_file, one iteration later, still readable —
      // but no longer immortal at arbitrary size.
      final msgs = [user('read the shell'), tool('a', 5000)];
      AIService.trimOldToolResultsForTesting(msgs);
      expect(_isClipped(msgs[1]), isFalse,
          reason: 'his only tool result is his active working set, not stale');
      expect((msgs[1]['content'] as String).length, lessThan(5000),
          reason: 'active does not mean unlimited');
      expect(msgs[1]['content'], contains('truncated'));
    });

    test('two and three results stay whole', () {
      for (final n in [2, 3]) {
        final msgs = <Map<String, dynamic>>[user('go')];
        for (var i = 0; i < n; i++) {
          msgs..add(asst('...'))..add(tool('t$i', 5000));
        }
        AIService.trimOldToolResultsForTesting(msgs);
        final tools = msgs.where((m) => m['role'] == 'tool').toList();
        for (final t in tools) {
          expect(_isClipped(t), isFalse,
              reason: 'with $n results, all $n are the working set');
        }
      }
    });
  });

  group('the working set is bounded — the feature still works', () {
    test('with more than keepWhole, the OLDEST get clipped', () {
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 5; i++) {
        msgs..add(asst('...'))..add(tool('t$i', 5000));
      }
      AIService.trimOldToolResultsForTesting(msgs);
      final tools = msgs.where((m) => m['role'] == 'tool').toList();

      // 5 results, keepWhole = 3 → the first two are history.
      expect(_isClipped(tools[0]), isTrue);
      expect(_isClipped(tools[1]), isTrue);
      // …the last three are what he's actually working with.
      expect(_isClipped(tools[2]), isFalse);
      expect(_isClipped(tools[3]), isFalse);
      expect(_isClipped(tools[4]), isFalse);
    });

    test('small old results are left alone', () {
      // Clipping a 40-char result to 500 chars would ADD text. Only bulk goes.
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 5; i++) {
        msgs..add(asst('...'))..add(tool('t$i', 40));
      }
      AIService.trimOldToolResultsForTesting(msgs);
      for (final t in msgs.where((m) => m['role'] == 'tool')) {
        expect(_isWhole(t, 40), isTrue);
      }
    });

    test('an enormous recent result is still hard-capped', () {
      // A whole-file read can be ~95k chars and gets re-sent EVERY round. Recent
      // doesn't mean unlimited.
      final msgs = [user('read it'), tool('a', 40000)];
      AIService.trimOldToolResultsForTesting(msgs);
      final c = msgs[1]['content'] as String;
      expect(c.length, lessThan(40000));
      expect(c, contains('truncated'),
          reason: 'and it must tell him HOW to get the rest');
      expect(c, contains('search_code'));
    });

    test('no tool results at all is a no-op, not a crash', () {
      final msgs = [user('hi'), asst('hey')];
      AIService.trimOldToolResultsForTesting(msgs);
      expect(msgs[0]['content'], 'hi');
      expect(msgs[1]['content'], 'hey');
    });
  });

  group('reads are materials — the amnesia that made him read in slabs', () {
    test('a read survives chatter that would evict a normal result', () {
      // The exact trace shape. He reads the widget, then does job_progress,
      // self_check, a search — and by the time he writes the edit, keepWhole=3
      // has clipped the read he is about to quote from. So he re-reads. Six
      // read iterations for one 200-line widget.
      final msgs = <Map<String, dynamic>>[user('delete the dead card')];
      msgs..add(asst('reading')) ..add(read('the-read', 9000));
      for (var i = 0; i < 5; i++) {
        msgs..add(asst('...')) ..add(tool('chatter$i', 900));
      }
      AIService.trimOldToolResultsForTesting(msgs);

      final theRead = msgs.firstWhere((m) => m['tool_call_id'] == 'the-read');
      expect(_isClipped(theRead), isFalse,
          reason: 'he still has to quote these exact bytes into edit_file');
      expect((theRead['content'] as String).length, lessThan(9000));
      expect(theRead['content'], contains('truncated'),
          reason: 'recent read_file survives as material, but not as an unlimited blob');
    });

    test('but chatter behind it still gets clipped', () {
      // The saving has to still happen, or this is just a leak with a story.
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 6; i++) {
        msgs..add(asst('...')) ..add(tool('chatter$i', 5000));
      }
      msgs..add(asst('...')) ..add(read('r', 5000));
      AIService.trimOldToolResultsForTesting(msgs);

      expect(_isClipped(msgs.firstWhere((m) => m['tool_call_id'] == 'chatter0')),
          isTrue);
      expect(_isClipped(msgs.firstWhere((m) => m['tool_call_id'] == 'r')),
          isFalse);
    });

    test('reads are not immortal — the oldest still go', () {
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 9; i++) {
        msgs..add(asst('...')) ..add(read('r$i', 5000));
      }
      AIService.trimOldToolResultsForTesting(msgs);
      final reads = msgs.where((m) => m['role'] == 'tool').toList();
      // 9 reads, keepMaterial = 2 → the first seven are genuinely history.
      expect(_isClipped(reads[0]), isTrue);
      expect(_isClipped(reads[6]), isTrue);
      expect(_isClipped(reads[7]), isFalse);
      expect(_isClipped(reads[8]), isFalse);
    });

    test('material window and hard cap are intentionally cheaper now', () {
      final msgs = <Map<String, dynamic>>[user('work on the widget')];
      for (var i = 0; i < 6; i++) {
        msgs..add(asst('...')) ..add(read('r$i', 12000));
      }

      final stats = AIService.trimOldToolResultsForTesting(msgs);
      final reads = msgs.where((m) => m['role'] == 'tool').toList();

      // Old default: keep 6 reads, hard-cap each to 14k, so all six 12k reads
      // survived whole: ~72k chars carried into every later GPT iteration.
      // Middle default: keep 4 reads, hard-cap at 9k: roughly 37k chars carried.
      // Current default: keep 2 reads, hard-cap at 4k: roughly 10k chars carried.
      // That's the knife Sadeq asked for: a smaller working pile every loop,
      // with the option to re-read a precise range when exact bytes matter.
      expect(_isClipped(reads[0]), isTrue);
      expect(_isClipped(reads[1]), isTrue);
      expect(_isClipped(reads[2]), isTrue);
      expect(_isClipped(reads[3]), isTrue);
      expect((reads[4]['content'] as String).length, lessThanOrEqualTo(4200));
      expect((reads[5]['content'] as String).length, lessThanOrEqualTo(4200));
      expect(stats.approxTokensSaved, greaterThanOrEqualTo(14000));
    });

    test('an untagged result is treated as disposable, not material', () {
      // Defensive: if anything ever appends a tool message without a name, the
      // old behaviour is what it gets. Silently promoting unknowns to material
      // would be a memory leak wearing this test as a disguise.
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 5; i++) {
        msgs
          ..add(asst('...'))
          ..add({
            'role': 'tool',
            'tool_call_id': 'u$i',
            'content': 'x' * 5000,
          });
      }
      AIService.trimOldToolResultsForTesting(msgs);
      final tools = msgs.where((m) => m['role'] == 'tool').toList();
      expect(_isClipped(tools[0]), isTrue);
      expect(_isClipped(tools[1]), isTrue);
    });
  });

  group('assistant tool-call arguments are not immortal receipts', () {
    test('old argument blobs are compacted while the latest calls stay intact', () {
      final msgs = <Map<String, dynamic>>[user('go')];
      for (var i = 0; i < 5; i++) {
        msgs
          ..add(asstToolCall('c$i', 'edit_file', 3000))
          ..add(tool('r$i', 40, name: 'edit_file'));
      }

      final saved = AIService.trimOldAssistantToolCallsForTesting(msgs);
      String argsAt(int i) => (((msgs[i]['tool_calls'] as List).first
          as Map)['function'] as Map)['arguments'] as String;

      expect(argsAt(1), contains('"_trimmed":true'));
      expect(argsAt(3), contains('"_trimmed":true'));
      expect(argsAt(5), contains('"_trimmed":true'));
      expect(argsAt(7).length, greaterThan(2500));
      expect(argsAt(9).length, greaterThan(2500));
      expect(saved, greaterThan(2000));
    });
  });
}
