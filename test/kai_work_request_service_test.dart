import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_work_request_service.dart';

void main() {
  group('KaiWorkRequestCommand', () {
    test('extracts desktop queue commands from mobile chat text', () {
      expect(
        KaiWorkRequestCommand.parse('queue for desktop: fix replay graph'),
        'fix replay graph',
      );
      expect(
        KaiWorkRequestCommand.parse('queue this for desktop - run tests'),
        'run tests',
      );
      expect(
        KaiWorkRequestCommand.parse('desktop task: wire mobile watcher'),
        'wire mobile watcher',
      );
      expect(KaiWorkRequestCommand.parse('just chatting'), isNull);
      expect(KaiWorkRequestCommand.parse('queue for desktop:'), isNull);
    });
  });

  group('KaiWorkRequestStatus', () {
    test('parses known statuses and defaults safely to queued', () {
      expect(
        KaiWorkRequestStatus.parse('queued'),
        KaiWorkRequestStatus.queued,
      );
      expect(
        KaiWorkRequestStatus.parse('running'),
        KaiWorkRequestStatus.running,
      );
      expect(
        KaiWorkRequestStatus.parse('done'),
        KaiWorkRequestStatus.done,
      );
      expect(
        KaiWorkRequestStatus.parse('nonsense'),
        KaiWorkRequestStatus.queued,
      );
      expect(
        KaiWorkRequestStatus.parse(null),
        KaiWorkRequestStatus.queued,
      );
    });
  });

  group('KaiWorkRequest', () {
    test('round-trips the durable queue fields', () {
      const request = KaiWorkRequest(
        id: 'r1',
        text: 'Fix replay graph measurement',
        status: KaiWorkRequestStatus.running,
        createdFrom: 'mobile',
        requiresDesktop: true,
        priority: 'high',
        claimedBy: 'desktop',
        summary: 'Working on it',
        evidence: ['claimed by desktop'],
        createdAt: 10,
        updatedAt: 20,
        startedAt: 15,
      );

      final map = request.toMap();
      final back = KaiWorkRequest.fromMap('r1', map);

      expect(back.id, 'r1');
      expect(back.text, 'Fix replay graph measurement');
      expect(back.status, KaiWorkRequestStatus.running);
      expect(back.createdFrom, 'mobile');
      expect(back.requiresDesktop, isTrue);
      expect(back.priority, 'high');
      expect(back.claimedBy, 'desktop');
      expect(back.summary, 'Working on it');
      expect(back.evidence, ['claimed by desktop']);
      expect(back.createdAt, 10);
      expect(back.updatedAt, 20);
      expect(back.startedAt, 15);
      expect(back.completedAt, isNull);
      expect(back.isOpen, isTrue);
    });

    test('defaults missing optional fields honestly', () {
      final request = KaiWorkRequest.fromMap('r2', {
        'text': 'Queue this',
        'createdAt': 1,
        'updatedAt': 2,
      });

      expect(request.status, KaiWorkRequestStatus.queued);
      expect(request.createdFrom, 'unknown');
      expect(request.requiresDesktop, isTrue);
      expect(request.priority, 'normal');
      expect(request.evidence, isEmpty);
      expect(request.isOpen, isTrue);
    });

    test('done, failed, and cancelled requests are not open', () {
      for (final status in [
        KaiWorkRequestStatus.done,
        KaiWorkRequestStatus.failed,
        KaiWorkRequestStatus.cancelled,
      ]) {
        final request = KaiWorkRequest.fromMap('x', {
          'text': 'closed',
          'status': status.name,
        });
        expect(request.isOpen, isFalse);
      }
    });
  });

  group('KaiWorkRequestEvent', () {
    test('round-trips event transcript fields', () {
      const event = KaiWorkRequestEvent(
        id: 'e1',
        kind: 'claimed',
        text: 'Desktop body picked this up.',
        actor: 'desktop',
        createdAt: 123,
      );

      final back = KaiWorkRequestEvent.fromMap('e1', event.toMap());

      expect(back.id, 'e1');
      expect(back.kind, 'claimed');
      expect(back.text, 'Desktop body picked this up.');
      expect(back.actor, 'desktop');
      expect(back.createdAt, 123);
    });
  });
}
