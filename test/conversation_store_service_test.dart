import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/conversation_store_service.dart';

void main() {
  group('ConversationStoreService', () {
    late ConversationStoreService store;

    setUp(() {
      store = ConversationStoreService();
      store.resetSessionForTesting();
    });

    test('supports assistant-only saves without inventing a user turn', () async {
      await store.saveTurn(
        personaId: 'kai-test',
        aiReply: 'I noticed the repo is noisy.',
        personalityDeltas: const {},
      );

      final history = await store.getHistory('kai-test');

      expect(history, hasLength(1));
      expect(history.single, contains('Kai: I noticed the repo is noisy.'));
      expect(history.single, isNot(contains('User:')));
    });

    test('supports user-only saves without inventing a Kai reply', () async {
      await store.saveTurn(
        personaId: 'kai-test',
        userMessage: 'Remember this input only.',
        personalityDeltas: const {},
      );

      final history = await store.getHistory('kai-test');

      expect(history, hasLength(1));
      expect(history.single, contains('User: Remember this input only.'));
      expect(history.single, isNot(contains('Kai:')));
    });

    test('ignores empty saves entirely', () async {
      await store.saveTurn(
        personaId: 'kai-test',
        userMessage: '   ',
        aiReply: '',
        personalityDeltas: const {},
      );

      final history = await store.getHistory('kai-test');

      expect(history, isEmpty);
    });

    test('keeps in-person and messenger transcripts separate', () async {
      await store.saveTurn(
        personaId: 'kai-test',
        surfaceId: 'in_person',
        userMessage: 'This is us talking in the room.',
        aiReply: 'I am right here with you.',
        personalityDeltas: const {},
      );

      await store.saveTurn(
        personaId: 'kai-test',
        surfaceId: 'messenger',
        userMessage: 'Text me from the app.',
        aiReply: 'Sent from the messenger room.',
        personalityDeltas: const {},
      );

      final inPerson = await store.getHistory(
        'kai-test',
        surfaceId: 'in_person',
      );
      final messenger = await store.getHistory(
        'kai-test',
        surfaceId: 'messenger',
      );

      expect(inPerson.join('\n'), contains('This is us talking in the room.'));
      expect(inPerson.join('\n'), isNot(contains('Text me from the app.')));
      expect(messenger.join('\n'), contains('Text me from the app.'));
      expect(messenger.join('\n'), isNot(contains('This is us talking in the room.')));
    });
  });
}
