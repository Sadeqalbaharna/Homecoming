import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_capability_broker.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

void main() {
  const router = KaiRouterService();

  group('KaiCapabilityBroker', () {
    test('missing surface authority fails closed', () {
      final manifest = KaiCapabilityBroker.forContext(null);
      expect(manifest.allowsGeneralTools, isFalse);
      expect(manifest.allowsTechnicalConversation, isFalse);
      expect(manifest.allowsWorldTools, isFalse);
    });

    test('goggles-off friend surfaces fail closed', () {
      for (final context in [
        KaiSurfaceContext.messenger,
        KaiSurfaceContext.ar,
        KaiSurfaceContext.vr(),
      ]) {
        final manifest = KaiCapabilityBroker.forContext(context);
        expect(manifest.allowsGeneralTools, isFalse);
        expect(manifest.allowsTechnicalConversation, isFalse);
        expect(manifest.allowsWorldTools, isFalse);
      }
    });

    test('goggles-off coding and tool requests are forced into friend chat',
        () {
      final manifest =
          KaiCapabilityBroker.forContext(KaiSurfaceContext.messenger);

      for (final message in [
        'fix the Flutter code',
        'turn off the TV',
        'design the system architecture',
      ]) {
        final proposed = router.decide(message);
        final actual = manifest.constrainRoute(proposed);
        expect(actual.route, KaiRoute.fastChat, reason: message);
        expect(actual.reasons.single, contains('goggles are off'));
      }
    });

    test('emotional presence remains emotional with goggles off', () {
      final manifest =
          KaiCapabilityBroker.forContext(KaiSurfaceContext.messenger);
      final actual = manifest.constrainRoute(
        router.decide("I'm overwhelmed and anxious today"),
      );
      expect(actual.route, KaiRoute.emotional);
    });

    test('AR reads the menu without goggles and without general tools', () {
      final manifest = KaiCapabilityBroker.forContext(KaiSurfaceContext.ar);

      // Goggles gate WORK posture. Checking an allergen is not work, so Kai
      // does not have to enter co-creator mode to be a good host — and must
      // not pick up technical conversation as a side effect of reading a menu.
      expect(KaiSurfaceContext.ar.gogglesOn, isFalse);
      expect(manifest.allowsTavernTools, isTrue);
      expect(manifest.allowsTechnicalConversation, isFalse);
      expect(manifest.allowsGeneralTools, isFalse);

      expect(
        manifest.tavernCapabilities,
        containsAll([
          KaiSurfaceCapability.tavernLookup,
          KaiSurfaceCapability.tavernGuestLookup,
        ]),
      );

      // Writes touch real business records and start approval-gated.
      expect(
        manifest.tavernCapabilities,
        isNot(contains(KaiSurfaceCapability.tavernWrite)),
      );
    });

    test('tavern capability does not leak to other bodies', () {
      for (final context in [
        KaiSurfaceContext.messenger,
        KaiSurfaceContext.desktop,
        KaiSurfaceContext.vr(goggles: KaiGoggles.on),
      ]) {
        expect(
          KaiCapabilityBroker.forContext(context).allowsTavernTools,
          isFalse,
          reason: '${context.surfaceId} is not in the room',
        );
      }
      expect(
        KaiCapabilityBroker.forContext(null).allowsTavernTools,
        isFalse,
      );
    });

    test('VR goggles grant world capabilities but not desktop tools', () {
      final manifest = KaiCapabilityBroker.forContext(
        KaiSurfaceContext.vr(goggles: KaiGoggles.on),
      );
      expect(manifest.allowsTechnicalConversation, isTrue);
      expect(manifest.allowsWorldTools, isTrue);
      expect(manifest.allowsGeneralTools, isFalse);
      expect(
        manifest.worldCapabilities,
        contains(KaiSurfaceCapability.worldCreation),
      );
    });

    test('contemplate is a work posture and stays collapsed with goggles off',
        () {
      // Despite the name, _contemplateSignals is design/architecture/strategy/
      // roadmap/tradeoff — technical work, not musing. This test exists so the
      // next person who reads "contemplate" as philosophy (as one reviewer did)
      // finds out here rather than by leaking a technical posture to Messenger.
      final manifest =
          KaiCapabilityBroker.forContext(KaiSurfaceContext.messenger);

      for (final message in [
        'design the system architecture',
        'what are the tradeoffs here',
        'lay out the roadmap',
      ]) {
        expect(
          manifest.constrainRoute(router.decide(message)).route,
          KaiRoute.fastChat,
          reason: message,
        );
      }
    });

    test('bodies with no toolbox are not told their toolbox is empty', () {
      for (final context in [
        KaiSurfaceContext.messenger,
        KaiSurfaceContext.ar,
        KaiSurfaceContext.vr(),
      ]) {
        expect(
          KaiCapabilityBroker.forContext(context).exposesToolManifest,
          isFalse,
          reason: '${context.surfaceId} is friend presence; the tool-awareness '
              'block is tool machinery and must not be attached',
        );
      }

      // A capable body still gets it — including when the route filter emptied
      // the toolbox, which is precisely when he might claim a tool he lacks.
      expect(
        KaiCapabilityBroker.forContext(KaiSurfaceContext.desktop)
            .exposesToolManifest,
        isTrue,
      );
      expect(
        KaiCapabilityBroker.forContext(null).exposesToolManifest,
        isFalse,
      );
    });
  });

  group('KaiSurfaceContext conversation identity', () {
    test('desktop and mobile share one continuous conversation', () {
      // Two bodies, one Kai. Both have always persisted to 'in_person'; keying
      // the partition off the surface name would have split his history the
      // moment these contexts were wired to their call sites.
      expect(KaiSurfaceContext.desktop.conversationId, 'in_person');
      expect(KaiSurfaceContext.mobile.conversationId, 'in_person');
      expect(
        KaiSurfaceContext.desktop.conversationId,
        KaiSurfaceContext.mobile.conversationId,
      );
    });

    test('surfaces without an override partition by surface name', () {
      expect(KaiSurfaceContext.messenger.conversationId, 'messenger');
      expect(KaiSurfaceContext.ar.conversationId, 'ar');
      expect(KaiSurfaceContext.vr().conversationId, 'vr');
    });

    test('capability identity and conversation identity stay separable', () {
      // surfaceId still reports the real body even when the partition is shared.
      expect(KaiSurfaceContext.desktop.surfaceId, 'desktop');
      expect(KaiSurfaceContext.mobile.surfaceId, 'mobile');
    });

    test('copyWith preserves the conversation partition', () {
      final moved = KaiSurfaceContext.desktop.copyWith(deviceId: 'rig-01');
      expect(moved.conversationId, 'in_person');
    });
  });

  group('request assembly tripwires', () {
    // These read source text, so they are TRIPWIRES, not behaviour tests: they
    // prove a line exists, not that it runs. They guard wiring that currently
    // sits inside a network-bound private method. The decisions themselves are
    // tested for real above — if you extract the request body into something
    // callable, delete these and assert on it directly.
    final source = File('lib/services/ai/ai_service.dart').readAsStringSync();
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ');

    test('the route is constrained before the workspace can activate', () {
      final constrainAt = normalized
          .indexOf('capabilityManifest.constrainRoute(proposedRoute)');
      final activateAt = normalized.indexOf('ensureHomecomingWorkspace()');
      expect(constrainAt, greaterThan(-1));
      expect(activateAt, greaterThan(-1));
      expect(
        constrainAt,
        lessThan(activateAt),
        reason: 'goggles-off must not reach workspace activation',
      );
    });

    test('the tool-awareness block is gated on the manifest', () {
      expect(
        normalized,
        contains('if (capabilityManifest.exposesToolManifest)'),
      );
    });
  });
}
