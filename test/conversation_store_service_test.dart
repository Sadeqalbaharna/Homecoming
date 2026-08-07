import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/conversation_store_service.dart';

void main() {
  test('formatted history uses the millisecond contract consumed by both UIs',
      () {
    const user = ConversationLine(
      text: 'the window remembers me',
      fromKai: false,
      timestampMillis: 1786110502613,
    );
    const kai = ConversationLine(
      text: 'obviously. it has taste.',
      fromKai: true,
      timestampMillis: 1786110502613,
    );

    expect(user.formatted, '[1786110502613] User: the window remembers me');
    expect(kai.formatted, '[1786110502613] Kai: obviously. it has taste.');
  });

  group('ConversationStoreService', () {
    late ConversationStoreService store;

    setUp(() {
      store = ConversationStoreService();
      store.resetSessionForTesting();
    });

    test('unavailable Firebase does not mark messenger history as loaded',
        () async {
      expect(store.hasLoadedForTesting('kai-test', surfaceId: 'messenger'),
          isFalse);

      await store.getHistory('kai-test', surfaceId: 'messenger');

      expect(store.hasLoadedForTesting('kai-test', surfaceId: 'messenger'),
          isFalse);
    });

    test('supports assistant-only saves without inventing a user turn',
        () async {
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

    test('restores only tagged messenger turns from legacy root history', () {
      final history = store.legacyMessengerHistoryForTesting({
        'oldMessenger': {
          'surfaceId': 'messenger',
          'timestamp': 20,
          'userMessage': 'old app text',
          'aiResponse': 'old app reply',
        },
        'oldInPerson': {
          'surfaceId': 'in_person',
          'timestamp': 10,
          'userMessage': 'room text',
          'aiResponse': 'room reply',
        },
        'oldUntagged': {
          'timestamp': 30,
          'userMessage': 'untagged text',
          'aiResponse': 'untagged reply',
        },
      });

      final joined = history.join('\n');
      expect(joined, contains('old app text'));
      expect(joined, contains('old app reply'));
      expect(joined, isNot(contains('room text')));
      expect(joined, isNot(contains('untagged text')));
    });

    test(
        'restores tagged and untagged in-person turns from legacy root history',
        () {
      final history = store.legacyInPersonHistoryForTesting({
        'oldMessenger': {
          'surfaceId': 'messenger',
          'timestamp': 20,
          'userMessage': 'old app text',
          'aiResponse': 'old app reply',
        },
        'oldInPerson': {
          'surfaceId': 'in_person',
          'timestamp': 10,
          'userMessage': 'room text',
          'aiResponse': 'room reply',
        },
        'oldUntagged': {
          'timestamp': 30,
          'userMessage': 'untagged text',
          'aiResponse': 'untagged reply',
        },
      });

      final joined = history.join('\n');
      expect(joined, contains('room text'));
      expect(joined, contains('room reply'));
      expect(joined, contains('untagged text'));
      expect(joined, contains('untagged reply'));
      expect(joined, isNot(contains('old app text')));
    });

    test('legacy desktop restore never descends into scoped messenger folders',
        () {
      final history = store.legacyInPersonHistoryForTesting({
        'oldDesktopTurn': {
          'timestamp': 10,
          'userMessage': 'old untagged desktop message',
          'aiResponse': 'old untagged desktop reply',
        },
        'messenger': {
          'phoneTurn': {
            'surfaceId': 'messenger',
            'timestamp': 20,
            'userMessage': 'private phone transcript',
            'aiResponse': 'private phone reply',
          },
        },
        'in_person': {
          'desktopTurn': {
            'surfaceId': 'in_person',
            'timestamp': 30,
            'userMessage': 'scoped desktop transcript',
            'aiResponse': 'scoped desktop reply',
          },
        },
      });

      final joined = history.join('\n');
      expect(joined, contains('old untagged desktop message'));
      expect(joined, isNot(contains('private phone transcript')));
      expect(joined, isNot(contains('scoped desktop transcript')),
          reason: 'scoped folders are loaded through their own exact path');
    });

    test('restores messenger turns from nested chat buckets', () {
      final history = store.scopedHistoryForTesting({
        'chatA': {
          'turn1': {
            'timestamp': 30,
            'userMessage': 'first phone chat',
            'aiResponse': 'first phone reply',
          },
        },
        'chatB': {
          'turn1': {
            'timestamp': 10,
            'userMessage': 'second phone chat',
            'aiResponse': 'second phone reply',
          },
        },
      });

      final joined = history.join('\n');
      expect(joined, contains('second phone chat'));
      expect(joined, contains('first phone chat'));
      expect(
        joined.indexOf('second phone chat'),
        lessThan(joined.indexOf('first phone chat')),
      );
    });

    test('parses scoped messenger turns into ordered realtime lines', () {
      final lines = store.scopedLinesForTesting({
        'chatA': {
          'turn1': {
            'timestamp': 30,
            'userMessage': 'later user text',
            'aiResponse': 'later kai text',
          },
        },
        'chatB': {
          'session1': {
            'turn1': {
              'timestamp': 10,
              'userMessage': 'earlier user text',
              'aiResponse': 'earlier kai text',
            },
          },
        },
      });

      expect(lines.map((line) => line.text), [
        'earlier user text',
        'earlier kai text',
        'later user text',
        'later kai text',
      ]);
      expect(lines.map((line) => line.fromKai), [false, true, false, true]);
      expect(lines.map((line) => line.timestampMillis), [
        10,
        10,
        30,
        30,
      ]);
    });

    test('restores phone messenger bubble records from nested chat buckets',
        () {
      final lines = store.scopedLinesForTesting({
        'chatA': {
          'msg1': {
            'timestamp': 10,
            'text': 'phone bubble from Darc',
            'fromKai': false,
          },
          'msg2': {
            'timestamp': 20,
            'text': 'phone bubble from Kai',
            'fromKai': true,
          },
        },
        'chatB': {
          'msg1': {
            'timestamp': 30,
            'message': 'assistant synonym still works',
            'sender': 'assistant',
          },
        },
      });

      expect(lines, hasLength(3));
      expect(lines.map((line) => line.text), [
        'phone bubble from Darc',
        'phone bubble from Kai',
        'assistant synonym still works',
      ]);
      expect(lines.map((line) => line.fromKai), [false, true, true]);
    });

    test('merges scoped in-person history with legacy untagged desktop history',
        () {
      final history = store.mergeScopedAndLegacyHistoryForTesting(
        {
          'newScopedTurn': {
            'timestamp': 30,
            'surfaceId': 'in_person',
            'userMessage': 'new scoped desktop message',
            'aiResponse': 'new scoped desktop reply',
          },
        },
        {
          'oldDesktopTurn': {
            'timestamp': 10,
            'userMessage': 'old untagged desktop message',
            'aiResponse': 'old untagged desktop reply',
          },
          'messengerTurn': {
            'timestamp': 20,
            'surfaceId': 'messenger',
            'userMessage': 'phone-only message',
            'aiResponse': 'phone-only reply',
          },
        },
        surfaceId: 'in_person',
      );

      final joined = history.join('\n');
      expect(joined, contains('old untagged desktop message'));
      expect(joined, contains('new scoped desktop message'));
      expect(joined, isNot(contains('phone-only message')));
      expect(
        joined.indexOf('old untagged desktop message'),
        lessThan(joined.indexOf('new scoped desktop message')),
      );
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
      expect(messenger.join('\n'),
          isNot(contains('This is us talking in the room.')));
    });
  });
}
