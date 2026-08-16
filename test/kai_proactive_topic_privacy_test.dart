import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_proactive_service.dart';

void main() {
  test('ordinary private inner thoughts cannot become proactive speech', () {
    expect(
      kaiShareableInnerThoughtFromEntry(
        'private-1',
        {'text': 'I am still thinking about the two Kai headers.'},
      ),
      isNull,
    );
  });

  test('only an explicit shareable thought receives a stable identity', () {
    final thought = kaiShareableInnerThoughtFromEntry(
      'shareable-7',
      {
        'text': 'The room name may be ambiguous.',
        'shareable': true,
      },
    );

    expect(thought, isNotNull);
    expect(thought!.id, 'shareable-7');
    expect(thought.text, 'The room name may be ambiguous.');
  });

  test('reflection continuations remain private even if mislabelled shareable',
      () {
    expect(
      kaiShareableInnerThoughtFromEntry(
        'reflection-2',
        {'text': '↳ repeated reflection', 'shareable': true},
      ),
      isNull,
    );
  });

  test('one silence episode has one identity until genuine activity changes',
      () {
    final firstActivity = DateTime.utc(2026, 8, 15, 8);
    final laterActivity = DateTime.utc(2026, 8, 15, 12);

    expect(
      kaiSilenceEpisodeTopicId(firstActivity),
      kaiSilenceEpisodeTopicId(firstActivity.toLocal()),
    );
    expect(
      kaiSilenceEpisodeTopicId(firstActivity),
      isNot(kaiSilenceEpisodeTopicId(laterActivity)),
    );
  });

  test('production proactive composition uses identified subjects only', () {
    final source = File(
      'lib/services/core/kai_proactive_service.dart',
    ).readAsStringSync();
    final compose =
        source.substring(source.indexOf('Future<KaiNudge?> _composeSeed'));

    expect(compose, contains('KaiNudge.identified('));
    expect(compose, isNot(contains('KaiNudge(')));
  });
}
