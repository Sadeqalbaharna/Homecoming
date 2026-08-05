import 'kai_router_service.dart';
import 'kai_surface_context.dart';

export 'kai_memory_types.dart';

class KaiMemoryAccessPolicy {
  const KaiMemoryAccessPolicy({
    required this.allowedScopes,
    this.worldId,
    this.allowAllWorlds = false,
  });

  final Set<KaiMemoryScope> allowedScopes;
  final String? worldId;
  final bool allowAllWorlds;

  bool allows({required KaiMemoryScope scope, String? memoryWorldId}) {
    if (!allowedScopes.contains(scope)) return false;
    if (scope != KaiMemoryScope.world) return true;
    if (allowAllWorlds) return true;
    return worldId != null && worldId == memoryWorldId;
  }

  static KaiMemoryAccessPolicy forContext(KaiSurfaceContext? context) {
    // Migration compatibility for existing untyped, trusted core call sites.
    if (context == null) {
      return const KaiMemoryAccessPolicy(
        allowAllWorlds: true,
        allowedScopes: {
          KaiMemoryScope.identity,
          KaiMemoryScope.relationship,
          KaiMemoryScope.sharedLife,
          KaiMemoryScope.creative,
          KaiMemoryScope.world,
          KaiMemoryScope.episodic,
          KaiMemoryScope.ephemeral,
          KaiMemoryScope.privateCore,
          KaiMemoryScope.legacyUnscoped,
        },
      );
    }

    if (context.surface == KaiSurface.desktop ||
        context.surface == KaiSurface.mobile) {
      return const KaiMemoryAccessPolicy(
        allowAllWorlds: true,
        allowedScopes: {
          KaiMemoryScope.identity,
          KaiMemoryScope.relationship,
          KaiMemoryScope.sharedLife,
          KaiMemoryScope.creative,
          KaiMemoryScope.world,
          KaiMemoryScope.episodic,
          KaiMemoryScope.privateCore,
          KaiMemoryScope.legacyUnscoped,
        },
      );
    }

    if (context.surface == KaiSurface.vr && context.gogglesOn) {
      return KaiMemoryAccessPolicy(
        worldId: context.worldId,
        allowedScopes: const {
          KaiMemoryScope.identity,
          KaiMemoryScope.relationship,
          KaiMemoryScope.sharedLife,
          KaiMemoryScope.creative,
          KaiMemoryScope.world,
        },
      );
    }

    return const KaiMemoryAccessPolicy(
      allowedScopes: {
        KaiMemoryScope.identity,
        KaiMemoryScope.relationship,
        KaiMemoryScope.sharedLife,
      },
    );
  }
}

KaiMemoryScope scopeForTurn({
  required KaiSurfaceContext? context,
  required KaiRoute route,
}) {
  if (context == null) return KaiMemoryScope.privateCore;
  if (!context.gogglesOn || route == KaiRoute.emotional) {
    return KaiMemoryScope.relationship;
  }
  if (context.surface == KaiSurface.vr) {
    // The shared EXPERIENCE travels with him; the work of building does not.
    // A VR session is both — "we built the loft and he lost it at the crooked
    // window" belongs on Messenger; "the lighting rig needs a second pass"
    // does not.
    //
    // This previously returned `creative` unconditionally. `creative` is
    // granted to core and goggles-on VR only, so EVERY VR memory was stranded
    // inside VR: leave the Shack, open Messenger, and the afternoon you just
    // spent together was gone. That is the one-Kai invariant failing in the
    // one place the whole surface model exists to protect, and it is the
    // reason Day 7 step 8 could not have passed.
    //
    // This is NOT the KaiVrMemoryPair two-record write. That pair is
    // experience + ARTIFACT, and no artifact exists until Unity world actions
    // are wired — writing the same conversation text under two scopes would be
    // duplication with two visibilities, not two records. The real pair lands
    // with the world-action event, keyed by eventId.
    //
    // Known limitation: this inherits KaiRouterService's keyword coverage.
    // "let's put a window here" hits 'design' → contemplate → creative, so a
    // genuinely memorable moment can still be scoped too narrow. It fails
    // CLOSED, which is the correct direction to be wrong in — an experience
    // that didn't travel is recoverable, a leaked one is not.
    return route == KaiRoute.fastChat
        ? KaiMemoryScope.relationship
        : KaiMemoryScope.creative;
  }
  if (route == KaiRoute.fastChat) return KaiMemoryScope.sharedLife;
  return KaiMemoryScope.privateCore;
}
