import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';

void main() {
  const router = KaiRouterService();

  test('routes ordinary short replies as fast chat', () {
    final decision = router.decide('yeah okay');

    expect(decision.route, KaiRoute.fastChat);
    expect(decision.confidence, greaterThan(0));
  });

  test('routes code/debug/build requests as coding', () {
    final decision = router.decide(
        'fix the Flutter analyzer error in lib/services/ai/ai_service.dart');

    expect(decision.route, KaiRoute.coding);
    expect(decision.confidence, greaterThanOrEqualTo(0.8));
    expect(decision.promptBlock(), contains('Route: coding'));
  });

  test('routes explicit device or assistant actions as tool', () {
    final decision = router.decide('turn off the TV and check the weather');

    expect(decision.route, KaiRoute.tool);
    expect(decision.promptBlock(),
        contains('call it instead of explaining manually'));
  });

  test('naming a shared place is conversation, not a phone call', () {
    final decision = router.decide(
      "Standing here makes me happy. Let's call this corner the Wobble Nook.",
    );

    expect(decision.route, KaiRoute.emotional);
  });

  test('an actual phone-call request remains a tool action', () {
    expect(router.decide('call my brother').route, KaiRoute.tool);
    expect(router.decide('could you call Ahmed').route, KaiRoute.tool);
  });

  test('routes vulnerable emotional messages as emotional', () {
    final decision = router.decide("I'm overwhelmed and anxious today");

    expect(decision.route, KaiRoute.emotional);
    expect(decision.promptBlock(), contains('be warm before being clever'));
  });

  test('routes strategy and architecture prompts as contemplate', () {
    final decision = router.decide(
        'think deeply about the architecture tradeoffs for memory routing');

    expect(decision.route, KaiRoute.contemplate);
    expect(decision.promptBlock(), contains('deepen the idea with structure'));
  });

  test('trust-mode continuation is cheap chat without an active job', () {
    final decision = router
        .decide('okay, go ahead, I give you trust on the Kai smarter layers');

    expect(decision.route, KaiRoute.fastChat);
  });

  test('trust-mode continuation of an active job stays in coding momentum', () {
    final decision = router.decide(
      'okay, go ahead',
      hasActiveJob: true,
    );

    expect(decision.route, KaiRoute.coding);
    expect(decision.promptBlock(), contains('Route: coding'));
  });

  test('and now continues an active coding job instead of falling to chat', () {
    final decision = router.decide('and now?', hasActiveJob: true);

    expect(decision.route, KaiRoute.coding);
    expect(decision.confidence, greaterThanOrEqualTo(0.8));
    expect(
        decision.reasons, contains('continuation of an active persisted job'));
  });
}
