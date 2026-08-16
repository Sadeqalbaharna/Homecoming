import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/conversation_store_service.dart';

void main() {
  test('session buffering keeps distinct outbound identities with identical text',
      () async {
    final store = ConversationStoreService();
    store.resetSessionForTesting();
    ConversationStoreService.debugOutboundWriter = (_, __) async {};
    addTearDown(() {
      ConversationStoreService.debugOutboundWriter = null;
      store.resetSessionForTesting();
    });

    const timestamp = 1786200000000;
    await store.saveAssistantOutbound(
      personaId: 'truekai',
      surfaceId: 'in_person',
      outboundId: 'outbound-a',
      exactText: 'chase the invoice',
      timestampMillis: timestamp,
    );
    await store.saveAssistantOutbound(
      personaId: 'truekai',
      surfaceId: 'in_person',
      outboundId: 'outbound-b',
      exactText: 'chase the invoice',
      timestampMillis: timestamp,
    );

    final history = await store.getHistory(
      'truekai',
      surfaceId: 'in_person',
    );
    expect(history, hasLength(2),
        reason: 'text equality cannot collapse two different promises');
  });
}
