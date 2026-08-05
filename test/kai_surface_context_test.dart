import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

void main() {
  group('Kai surface profiles', () {
    test('all surfaces preserve one identity while varying capabilities', () {
      expect(KaiSurfaceContext.desktop.profile.role, KaiPresenceRole.core);
      expect(KaiSurfaceContext.mobile.profile.role, KaiPresenceRole.core);
      expect(KaiSurfaceContext.messenger.profile.role, KaiPresenceRole.friend);
      expect(KaiSurfaceContext.ar.profile.role, KaiPresenceRole.embodiedFriend);
      expect(
        KaiSurfaceContext.vr().profile.role,
        KaiPresenceRole.friendAndCoCreator,
      );
    });

    test('Messenger and AR cannot receive general tools or technical posture',
        () {
      for (final context in [
        KaiSurfaceContext.messenger,
        KaiSurfaceContext.ar
      ]) {
        expect(context.goggles, KaiGoggles.off);
        expect(context.allowsGeneralTools, isFalse);
        expect(context.allowsTechnicalConversation, isFalse);
        expect(
          context.profile.memoryScopes,
          containsAll({
            KaiMemoryScope.identity,
            KaiMemoryScope.relationship,
            KaiMemoryScope.sharedLife,
          }),
        );
      }
    });

    test('VR is friend and co-creator with world-scoped context', () {
      final context = KaiSurfaceContext.vr(
        worldId: 'vr_shack',
        deviceId: 'quest-01',
        sessionId: 'visit-42',
        perception: const {'near': 'adventure table'},
      );

      expect(context.worldId, 'vr_shack');
      expect(context.deviceId, 'quest-01');
      expect(context.sessionId, 'visit-42');
      expect(context.profile.allowsGeneralTools, isFalse);
      expect(context.goggles, KaiGoggles.off);
      expect(
        context.profile.capabilities,
        containsAll({
          KaiSurfaceCapability.worldInspection,
          KaiSurfaceCapability.worldActions,
          KaiSurfaceCapability.worldCreation,
        }),
      );
      expect(context.profile.memoryScopes, contains(KaiMemoryScope.world));
      expect(context.source, 'unity_vr');
    });

    test('goggles visibly separate presence from available work', () {
      expect(KaiSurfaceContext.desktop.goggles, KaiGoggles.on);
      expect(KaiSurfaceContext.desktop.allowsGeneralTools, isTrue);
      expect(KaiSurfaceContext.messenger.goggles, KaiGoggles.off);
      expect(KaiSurfaceContext.messenger.allowsGeneralTools, isFalse);

      final creatingInVr = KaiSurfaceContext.vr(goggles: KaiGoggles.on);
      expect(creatingInVr.gogglesOn, isTrue);
      expect(creatingInVr.allowsTechnicalConversation, isTrue);
      expect(creatingInVr.gogglesPromptBlock, contains('GOGGLES ON'));
      // VR grants world capabilities, not the desktop's unrestricted tool loop.
      expect(creatingInVr.allowsGeneralTools, isFalse);

      final hangingOutInVr = KaiSurfaceContext.vr();
      expect(hangingOutInVr.allowsTechnicalConversation, isFalse);
      expect(
          hangingOutInVr.gogglesPromptBlock, contains('goggles need to go on'));
    });

    test('presence events retain surface identity but use ephemeral source',
        () {
      final context = KaiSurfaceContext.vr(isPresenceEvent: true);
      expect(context.surface, KaiSurface.vr);
      expect(context.source, 'unity_presence');
    });
  });
}
