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
    final decision = router.decide('fix the Flutter analyzer error in lib/services/ai/ai_service.dart');

    expect(decision.route, KaiRoute.coding);
    expect(decision.confidence, greaterThanOrEqualTo(0.8));
    expect(decision.promptBlock(), contains('Route: coding'));
  });

  test('routes explicit device or assistant actions as tool', () {
    final decision = router.decide('turn off the TV and check the weather');

    expect(decision.route, KaiRoute.tool);
    expect(decision.promptBlock(), contains('call it instead of explaining manually'));
  });

  test('routes vulnerable emotional messages as emotional', () {
    final decision = router.decide("I'm overwhelmed and anxious today");

    expect(decision.route, KaiRoute.emotional);
    expect(decision.promptBlock(), contains('be warm before being clever'));
  });

  test('routes strategy and architecture prompts as contemplate', () {
    final decision = router.decide('think deeply about the architecture tradeoffs for memory routing');

    expect(decision.route, KaiRoute.contemplate);
    expect(decision.promptBlock(), contains('deepen the idea with structure'));
  });

  test('trust-mode continuation of Kai Smarter Project stays in coding momentum', () {
    final decision = router.decide('okay, go ahead, I give you trust on the Kai smarter layers');

    expect(decision.route, KaiRoute.coding);
    expect(decision.promptBlock(), contains('Route: coding'));
  });
}
