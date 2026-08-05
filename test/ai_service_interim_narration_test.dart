import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/ai_service.dart';

void main() {
  group('agentic interim narration surface gate', () {
    test('shows tool-loop narration only for tool and coding routes', () {
      expect(shouldSurfaceAgenticInterimNarration('tool'), isTrue);
      expect(shouldSurfaceAgenticInterimNarration('coding'), isTrue);

      expect(shouldSurfaceAgenticInterimNarration('fastChat'), isFalse);
      expect(shouldSurfaceAgenticInterimNarration('emotional'), isFalse);
      expect(shouldSurfaceAgenticInterimNarration('contemplate'), isFalse);
    });

    test('suppresses canned bridge lines but keeps useful progress', () {
      expect(
        shouldSurfaceAgenticInterimNarration(
          'coding',
          narration: 'Right, reading the desktop shell first.',
        ),
        isTrue,
      );

      expect(
        shouldSurfaceAgenticInterimNarration(
          'coding',
          narration: 'Still thinking about that, classic me.',
        ),
        isFalse,
      );
    });

    test('does not persist conversation turns when both save flags are false', () {
      expect(
        shouldPersistConversationTurn(
          saveUserMessage: false,
          saveAssistantReply: false,
        ),
        isFalse,
      );

      expect(
        shouldPersistConversationTurn(
          saveUserMessage: false,
          saveAssistantReply: true,
        ),
        isTrue,
      );

      expect(
        shouldPersistConversationTurn(
          saveUserMessage: true,
          saveAssistantReply: false,
        ),
        isTrue,
      );
    });
  });
}
