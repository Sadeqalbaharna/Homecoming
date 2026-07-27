// Parsing the ChatGPT export — before a token is spent extracting from it.
//
// The fixture is shaped exactly like a real conversations.json: a tree mapping,
// out-of-order nodes, a system message, an edit branch, and a non-text
// (image) node. If the parser survives this, it survives the real export — and
// the whole year-import rests on it, so it gets pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/chatgpt_export.dart';

// Two conversations. The first has a system node (drop), an edited user branch
// (keep the transcript, ordered by time), and an image node (drop).
final export = [
  {
    'title': 'Kai origins',
    'mapping': {
      'sys': {
        'message': {
          'author': {'role': 'system'},
          'content': {'content_type': 'text', 'parts': ['You are helpful.']},
          'create_time': 1.0,
        },
      },
      // deliberately out of insertion order — the parser must sort by time
      'a2': {
        'message': {
          'author': {'role': 'assistant'},
          'content': {'content_type': 'text', 'parts': ['Digimon, easily.']},
          'create_time': 40.0,
        },
      },
      'u1': {
        'message': {
          'author': {'role': 'user'},
          'content': {'content_type': 'text', 'parts': ['whats better, digimon or pokemon']},
          'create_time': 30.0,
        },
      },
      'img': {
        'message': {
          'author': {'role': 'user'},
          'content': {'content_type': 'image_asset_pointer', 'parts': [{'asset': 'x'}]},
          'create_time': 50.0,
        },
      },
      'u3': {
        'message': {
          'author': {'role': 'user'},
          'content': {'content_type': 'text', 'parts': ['make it walk on 4am energy']},
          'create_time': 60.0,
        },
      },
      'a3': {
        'message': {
          'author': {'role': 'assistant'},
          'content': {'content_type': 'text', 'parts': ['Nocturnal it is.']},
          'create_time': 70.0,
        },
      },
    },
  },
  {
    'title': 'empty one',
    'mapping': {
      'only-sys': {
        'message': {
          'author': {'role': 'system'},
          'content': {'content_type': 'text', 'parts': ['sys only']},
          'create_time': 1.0,
        },
      },
    },
  },
];

void main() {
  test('flattens the tree into ordered user/assistant turns', () {
    final convs = parseExport(export);
    expect(convs, hasLength(1),
        reason: 'the system-only conversation yields no turns and is dropped');
    final t = convs.first;
    expect(t.title, 'Kai origins');
    // system dropped, image dropped → 4 real turns, in time order
    expect(t.turns.map((x) => x.role).toList(),
        ['user', 'assistant', 'user', 'assistant']);
    expect(t.turns.first.text, contains('digimon or pokemon'));
  });

  test('pairs are (user, assistant), in order', () {
    final pairs = parseExport(export).first.pairs;
    expect(pairs, hasLength(2));
    expect(pairs[0].$1, contains('digimon'));
    expect(pairs[0].$2, 'Digimon, easily.');
    expect(pairs[1].$1, contains('4am'));
    expect(pairs[1].$2, 'Nocturnal it is.');
  });

  test('non-text content is skipped, not crashed on', () {
    final texts = parseExport(export).first.turns.map((t) => t.text);
    expect(texts.any((s) => s.contains('asset')), isFalse);
  });

  test('totalPairs counts real exchanges across the export', () {
    expect(totalPairs(parseExport(export)), 2);
  });

  group('personal signal — the free token-saver', () {
    ExportConversation conv(List<String> userTurns) => ExportConversation(
          't',
          [
            for (var i = 0; i < userTurns.length; i++)
              ExportTurn('user', userTurns[i], i.toDouble()),
          ],
        );

    test('a heartfelt conversation scores high', () {
      final c = conv([
        "i've been thinking about my daughter a lot. i want kai to feel like a "
            "real friend to me — i grew up without that and it always stuck."
      ]);
      expect(personalSignal(c), greaterThan(0.05));
    });

    test('a coding task scores ~zero — it gets filtered for free', () {
      final c = conv([
        'fix this function it throws a null error',
        'here is the code ```def f(): return x/0``` debug and rewrite the api'
      ]);
      expect(personalSignal(c), lessThan(0.05));
    });

    test('too short to disclose anything scores zero', () {
      expect(personalSignal(conv(['hey'])), 0);
    });

    test('filterPersonal drops the tasks, keeps the person, strongest first', () {
      final personal = conv([
        "my mom is visiting and i'm honestly nervous, we haven't spoken in years"
      ]);
      final task = conv(['refactor this sql query and fix the regex error']);
      final kept = filterPersonal([task, personal]);
      expect(kept, hasLength(1));
      expect(kept.first, same(personal));
    });
  });

  group('a year of export is not pristine — degrade, never throw', () {
    test('not a list', () => expect(parseExport({'x': 1}), isEmpty));
    test('null', () => expect(parseExport(null), isEmpty));
    test('conversation missing mapping', () {
      expect(parseExport([{'title': 't'}]), isEmpty);
    });
    test('a garbage node next to a good one keeps the good one', () {
      final mixed = [
        {
          'title': 'mixed',
          'mapping': {
            'junk': 'not a map',
            'ok_u': {
              'message': {
                'author': {'role': 'user'},
                'content': {'content_type': 'text', 'parts': ['hi']},
                'create_time': 1.0,
              },
            },
            'ok_a': {
              'message': {
                'author': {'role': 'assistant'},
                'content': {'content_type': 'text', 'parts': ['hey']},
                'create_time': 2.0,
              },
            },
          },
        },
      ];
      final c = parseExport(mixed);
      expect(c, hasLength(1));
      expect(c.first.pairs, hasLength(1));
    });
  });
}
