import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/ai_service.dart';

void main() {
  test('background memory receipt cannot replace Kai natural reply', () {
    final reply = AIService.chooseAgenticReply(
      synthesizedReply:
          'Darc. Right. That belongs in the bones, not on a sticky note.',
      toolCallCount: 1,
      lastToolResult: 'Noted about Sadeq.',
    );

    expect(
      reply,
      'Darc. Right. That belongs in the bones, not on a sticky note.',
    );
    expect(reply, isNot(contains('Noted about Sadeq')));
  });

  test('short tool receipt remains a fallback when synthesis is empty', () {
    final reply = AIService.chooseAgenticReply(
      synthesizedReply: '   ',
      toolCallCount: 1,
      lastToolResult: 'Saved.',
    );

    expect(reply, 'Saved.');
  });

  test('structured or multiline data is never leaked as empty-reply fallback',
      () {
    expect(
      AIService.chooseAgenticReply(
        synthesizedReply: '',
        toolCallCount: 1,
        lastToolResult: '{"private":"memory"}',
      ),
      isEmpty,
    );
    expect(
      AIService.chooseAgenticReply(
        synthesizedReply: '',
        toolCallCount: 1,
        lastToolResult: 'internal\nreceipt',
      ),
      isEmpty,
    );
  });
}
