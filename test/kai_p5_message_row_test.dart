import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_p5_chat.dart';

void main() {
  testWidgets('P5 message rows render messenger timestamps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: P5Background(
            child: Center(
              child: P5MessageRow.text(
                'hey captain',
                fromKai: true,
                timestamp: '12:34',
                seed: 1,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('hey captain'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
  });

  test('P5 messenger has a visible empty conversation state', () {
    final source = File('lib/screens/kai_p5_chat_screen.dart').readAsStringSync();

    expect(source, contains('class _P5EmptyConversation extends StatelessWidget'));
    expect(source, contains('_msgs.isEmpty && !_sending'));
    expect(source, contains('No messages yet.'));
  });

  test('P5 Kai message rows protect bubble width on cramped desktop rails', () {
    final source = File('lib/widgets/kai_p5_chat.dart').readAsStringSync();

    expect(source, contains('final cramped = constraints.maxWidth < 360'));
    expect(source, contains('if (!cramped) ...['));
    expect(source, contains('KaiFace(size: cramped ? 78 : 116)'));
  });

  test('restored P5 messenger history preserves stored timestamps', () {
    final source = File('lib/screens/kai_p5_chat_screen.dart').readAsStringSync();

    expect(source, contains('final rawMillis = int.tryParse(m.group(1)!)'));
    expect(source, contains('DateTime.fromMillisecondsSinceEpoch(rawMillis)'));
    expect(source, contains('time: rawMillis == null'));
    expect(source, contains('DateTime.fromMillisecondsSinceEpoch(line.timestampMillis)'));
  });

  test('P5 messenger restores a full app-sized transcript', () {
    final source = File('lib/screens/kai_p5_chat_screen.dart').readAsStringSync();

    expect(source, contains('static const _visibleHistoryTurns = 200'));
    expect(source, contains('maxTurns: _visibleHistoryTurns'));
    expect(source, isNot(contains('static const _historyTurns = 12')));
  });
}
