import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_inner_monologue.dart';

void main() {
  test('only explicitly model-generated records qualify as inner thoughts', () {
    expect(
      KaiInnerMonologue.isGenuineThought({
        'text': 'a new connection clicked',
        'origin': 'model_generated',
      }),
      isTrue,
    );
    expect(
      KaiInnerMonologue.isGenuineThought({
        'text': 'Ideas are smashing into each other in here and I love it.',
        'synthetic': true,
      }),
      isFalse,
    );
    expect(
      KaiInnerMonologue.isGenuineThought({
        'text': 'legacy unproven record',
      }),
      isFalse,
    );
  });

  testWidgets('ambient thought positions only as a direct Stack child',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 500,
          child: KaiInnerMonologue.ambientLayer(
            anchor: const Offset(40, 60),
            duration: const Duration(milliseconds: 100),
            child: const Text('a passing thought'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Stack), findsOneWidget);
    expect(find.byType(AnimatedPositioned), findsOneWidget);
    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(positioned.left, 40);
    expect(positioned.top, 60);
  });
}
