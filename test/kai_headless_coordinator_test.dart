import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_headless_coordinator.dart';

void main() {
  test('network and timeout failures are retried with bounded backoff', () {
    expect(isTransientConversationFailure(TimeoutException('slow')), isTrue);
    expect(isTransientConversationFailure(const SocketException('offline')),
        isTrue);
    expect(isTransientConversationFailure(StateError('empty reply')), isFalse);
    expect(kaiRetryDelay(0), const Duration(seconds: 1));
    expect(kaiRetryDelay(1), const Duration(seconds: 2));
    expect(kaiRetryDelay(9), const Duration(seconds: 5));
  });

  test('only real user transcript turns reset proactive silence', () {
    expect(
      latestUserActivityMillis({
        'proactive': {'userMessage': '', 'timestamp': 20},
        'human': {'userMessage': 'hey', 'timestamp': 10},
      }),
      10,
    );
    expect(
      latestUserActivityMillis({
        'assistant-only': {'aiResponse': 'still here', 'timestamp': 30},
      }),
      0,
    );
  });

  test('proactive generation cannot echo the prior room transcript', () {
    expect(kKaiProactiveContextTurns, 0);

    final headless = File(
      'lib/services/core/kai_headless_coordinator.dart',
    ).readAsStringSync();
    expect(headless, contains('ctxTurns: kKaiProactiveContextTurns'));
    expect(headless, contains('useMemory: false'));
    expect(headless, contains('saveUserMessage: false'));
  });

  test('desktop room no longer owns Messenger, embodiment, or proactive loops',
      () {
    final desktop =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final headless = File('lib/services/core/kai_headless_coordinator.dart')
        .readAsStringSync();

    expect(desktop, isNot(contains('watchOpenRequests(_kPersona).listen')));
    expect(desktop, isNot(contains('KaiProactiveService.instance.start')));
    expect(headless, contains('watchOpenRequests(kKaiCentralPersona).listen'));
    expect(headless, contains('KaiProactiveService.instance.start'));
    expect(headless, contains('_startEmbodimentGateways'));
    expect(headless, contains('Future<void> _recoverCore()'));
    expect(headless, contains('KaiCoreServer? _embeddedCore'));
    expect(headless, contains("'embedded_core_started'"));
    expect(headless, contains("retry: false"));
    expect(headless, contains('_watchCrossProcessActivity'));
    expect(headless, isNot(contains("'conversation': 4")));
    expect(headless, contains("'proactive_friend'"));
    expect(headless, contains('targetBodyId: body.bodyId'));
    expect(headless, contains('saveAssistantReply: false'));
    expect(headless, contains('deferForQuietHours'));
    expect(headless, contains("'proactive_delivery_deferred_quiet_hours'"));
    expect(headless, contains('ConversationStoreService().saveTurn'));
    expect(headless, contains('KaiProactiveAttentionQueue'));
    expect(headless, contains('_enqueueProactiveNudge'));
    expect(headless, contains('_drainProactiveAttention'));
    expect(headless, contains("'attention_decision'"));
    expect(headless, isNot(contains('final route = routeKaiOutput(')),
        reason: 'proactive attention must use the accepted decision engine');
  });

  test('embodied bodies use independent ordered lanes', () {
    final gateway = File(
      'lib/services/embodiment/kai_embodiment_gateway_service.dart',
    ).readAsStringSync();
    expect(gateway, contains('bool _busy = false'));
    expect(gateway, isNot(contains('static bool _busy = false')));
  });

  test('headless entrypoint mounts no desktop application', () {
    final main = File('lib/main_mobile.dart').readAsStringSync();
    expect(main, contains("args.contains('--coordinator-worker')"));
    expect(
      main,
      contains('final coordinator = KaiHeadlessCoordinator.instance'),
    );
    expect(main, contains('await coordinator.start'));
    expect(main, contains('await shutdownService.start'));
    expect(main, contains('if (!coordinatorMode)'));
  });
}
