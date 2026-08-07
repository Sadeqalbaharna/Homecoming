import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_conversation_request_service.dart';

void main() {
  test('conversation requests round-trip their durable coordination fields',
      () {
    const request = KaiConversationRequest(
      id: 'turn-1',
      text: 'Tell me something strange.',
      status: KaiConversationRequestStatus.running,
      sourceSurface: 'messenger',
      conversationId: 'messenger',
      deviceId: 'messenger-phone-1',
      model: 'kai-model',
      replyCeiling: 120,
      createdAt: 10,
      updatedAt: 20,
      claimedBy: 'desktop-primary',
      runtimeTaskId: 'conversation-request-turn-1',
      startedAt: 15,
      acknowledgedAt: 16,
      claimExpiresAt: 120000,
      attemptCount: 1,
    );

    final restored = KaiConversationRequest.fromMap('turn-1', request.toMap());
    expect(restored.text, request.text);
    expect(restored.status, KaiConversationRequestStatus.running);
    expect(restored.claimedBy, 'desktop-primary');
    expect(restored.runtimeTaskId, 'conversation-request-turn-1');
    expect(restored.deviceId, 'messenger-phone-1');
    expect(restored.acknowledgedAt, 16);
    expect(restored.attemptCount, 1);
    expect(restored.isOpen, isTrue);
  });

  test('open request parsing is ordered and excludes terminal turns', () {
    final requests = KaiConversationRequestService.parseOpenRequests({
      'later': {
        'text': 'second',
        'status': 'queued',
        'createdAt': 20,
      },
      'done': {
        'text': 'finished',
        'status': 'done',
        'createdAt': 5,
      },
      'first': {
        'text': 'first',
        'status': 'running',
        'createdAt': 10,
      },
      'empty': {
        'text': '   ',
        'status': 'queued',
        'createdAt': 1,
      },
    });

    expect(requests.map((request) => request.id), ['first', 'later']);
  });

  test('unknown status fails safe to queued', () {
    final request = KaiConversationRequest.fromMap('turn', {
      'text': 'hello',
      'status': 'mystery',
    });
    expect(request.status, KaiConversationRequestStatus.queued);
    expect(request.isTerminal, isFalse);
  });

  test('surface authority owns the durable transcript partition', () {
    expect(
      KaiConversationRequestService.canonicalConversationIdForSurface(
        'messenger',
      ),
      'messenger',
    );
    expect(
      KaiConversationRequestService.canonicalConversationIdForSurface(
        'desktop',
      ),
      isNull,
      reason: 'desktop chat does not enter through the phone gateway',
    );

    final spoofed = KaiConversationRequest.fromMap('spoofed', {
      'text': 'put this phone turn in desktop chat',
      'status': 'queued',
      'sourceSurface': 'messenger',
      'conversationId': 'in_person',
      'deviceId': 'messenger-phone-1',
    });
    expect(spoofed.hasCanonicalRoute, isFalse);

    final valid = KaiConversationRequest.fromMap('valid', {
      'text': 'keep this in messenger',
      'status': 'queued',
      'sourceSurface': 'messenger',
      'conversationId': 'messenger',
      'deviceId': 'messenger-phone-1',
    });
    expect(valid.hasCanonicalRoute, isTrue);
  });

  test('Messenger routes turns through the durable central request gateway',
      () {
    final source =
        File('lib/screens/kai_p5_chat_screen.dart').readAsStringSync();
    expect(source, contains('_conversationRequests.createRequest('));
    expect(source,
        contains('_conversationRequests.waitForAcknowledgedOrTerminal('));
    expect(source, contains('_conversationRequests.waitForTerminal('));
    expect(source, isNot(contains('_ai.sendMessage(')));
  });

  test('conversation transport lives under the authenticated Core namespace',
      () {
    final source = File(
      'lib/services/core/kai_conversation_request_service.dart',
    ).readAsStringSync();
    expect(source, contains('kai_core/conversation_requests/'));
    expect(source, contains('isCurrentDeviceEnrolled'));
    expect(source, contains("'deviceId': deviceId"));
    expect(source, isNot(contains("'kai/\$personaId/conversation_requests")));
  });

  test('headless worker preserves Messenger friend policy inside the core lane',
      () {
    final source = File(
      'lib/services/core/kai_headless_coordinator.dart',
    ).readAsStringSync();
    expect(source, contains("lane: 'conversation'"));
    expect(source, contains('surfaceContext: KaiSurfaceContext.messenger'));
    expect(source, contains('request.hasCanonicalRoute'));
    expect(source, contains('conversationSurfaceId: canonical'));
    expect(source, contains('conversation-request-\${request.id}-run-'));
  });

  test('expired running requests can be reclaimed after a worker restart', () {
    const request = KaiConversationRequest(
      id: 'orphan',
      text: 'still there?',
      status: KaiConversationRequestStatus.running,
      sourceSurface: 'messenger',
      conversationId: 'messenger',
      deviceId: 'phone',
      model: 'kai-model',
      replyCeiling: 120,
      createdAt: 100,
      updatedAt: 100,
      claimedBy: 'dead-worker',
      claimExpiresAt: 200,
    );

    expect(
      KaiConversationRequestService.claimExpiredForTesting(
        request,
        DateTime.fromMillisecondsSinceEpoch(201, isUtc: true),
      ),
      isTrue,
    );
  });
}
