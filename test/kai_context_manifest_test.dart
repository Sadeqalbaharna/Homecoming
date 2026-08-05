import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_capability_broker.dart';
import 'package:homecoming_app/services/core/kai_context_manifest.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

void main() {
  test('goggles-off manifest contains relationship context, not work context',
      () {
    final surface = KaiSurfaceContext.messenger;
    final manifest = KaiContextManifest.forTurn(
      route: KaiRoute.fastChat,
      capabilities: KaiCapabilityBroker.forContext(surface),
      surface: surface,
    );

    expect(
      manifest.included,
      containsAll({
        KaiContextPart.identity,
        KaiContextPart.mood,
        KaiContextPart.userModel,
        KaiContextPart.goals,
        KaiContextPart.bond,
      }),
    );
    expect(manifest.includes(KaiContextPart.activeJob), isFalse);
    expect(manifest.includes(KaiContextPart.codeWorkspace), isFalse);
    expect(manifest.includes(KaiContextPart.projectLadder), isFalse);
    expect(manifest.includeTechnicalPreamble, isFalse);
    expect(manifest.includeToolMachinery, isFalse);
  });

  test('forbidden providers are not invoked', () async {
    final surface = KaiSurfaceContext.messenger;
    final manifest = KaiContextManifest.forTurn(
      route: KaiRoute.fastChat,
      capabilities: KaiCapabilityBroker.forContext(surface),
      surface: surface,
    );
    var calls = 0;

    final value =
        await manifest.loadString(KaiContextPart.codeWorkspace, () async {
      calls++;
      return 'technical leak';
    });

    expect(calls, 0);
    expect(value, isEmpty);
  });

  test('allowed relationship providers still run', () async {
    final surface = KaiSurfaceContext.messenger;
    final manifest = KaiContextManifest.forTurn(
      route: KaiRoute.fastChat,
      capabilities: KaiCapabilityBroker.forContext(surface),
      surface: surface,
    );
    var calls = 0;

    final value = await manifest.loadString(KaiContextPart.bond, () async {
      calls++;
      return 'shared bit';
    });

    expect(calls, 1);
    expect(value, 'shared bit');
  });

  test('route-only manifests preserve the existing skip policy', () {
    final fast = KaiContextManifest.forRoute(KaiRoute.fastChat);
    expect(fast.includes(KaiContextPart.identity), isTrue);
    expect(fast.includes(KaiContextPart.codeWorkspace), isFalse);
    expect(fast.includes(KaiContextPart.bond), isFalse);

    final coding = KaiContextManifest.forRoute(KaiRoute.coding);
    expect(coding.includes(KaiContextPart.codeWorkspace), isTrue);
    expect(coding.includes(KaiContextPart.bond), isFalse);
  });
}
