import 'kai_router_service.dart';
import 'kai_surface_context.dart';

/// The authoritative capabilities for one turn.
///
/// A missing surface context has no authority. Trusted core callers must name
/// their desktop/mobile body explicitly; authority is never inferred from null.
class KaiCapabilityManifest {
  const KaiCapabilityManifest({
    required this.allowsGeneralTools,
    required this.allowsTechnicalConversation,
    required this.worldCapabilities,
  });

  final bool allowsGeneralTools;
  final bool allowsTechnicalConversation;
  final Set<KaiSurfaceCapability> worldCapabilities;

  bool get allowsWorldTools => worldCapabilities.isNotEmpty;

  /// Whether this turn may carry the tool-awareness system block.
  ///
  /// Named separately from [allowsGeneralTools] because it answers a different
  /// question: not "may he call tools" but "may he be TOLD ABOUT tools". A body
  /// with no toolbox must not receive "CURRENT TOOLS: none are attached" — that
  /// is tool machinery, the goggles-off directive forbids exposing it, and it
  /// primes him to think about tools on a turn where the concept shouldn't
  /// exist. A capable body whose route filter emptied the toolbox this turn
  /// still needs that warning, so this cannot key off the tool list being empty.
  bool get exposesToolManifest => allowsGeneralTools;

  KaiRouteDecision constrainRoute(KaiRouteDecision proposed) {
    if (allowsTechnicalConversation) return proposed;

    if (proposed.route == KaiRoute.emotional) return proposed;

    // contemplate IS collapsed here, and that is correct: despite the name,
    // KaiRouterService._contemplateSignals is 'design', 'architecture',
    // 'strategy', 'roadmap', 'tradeoff', 'pros and cons' — a WORK posture
    // ("deepen the idea with structure"), not philosophical musing. Letting it
    // through would hand Messenger a technical posture on "design the system
    // architecture", which is exactly the leak this broker exists to stop.
    //
    // The gap this exposes is a MISSING route, not a mis-constrained one: there
    // is no posture for personal reflection, so goggles-off Kai can be warm
    // (emotional) or brief (fastChat) but never pensive about non-technical
    // things. A `reflect` route split out of these signals would fix that
    // without reopening the leak. Until it exists, collapsing is the safe call.
    if (proposed.route != KaiRoute.coding &&
        proposed.route != KaiRoute.tool &&
        proposed.route != KaiRoute.contemplate) {
      return proposed;
    }

    return const KaiRouteDecision(
      route: KaiRoute.fastChat,
      confidence: 1,
      reasons: [
        'goggles are off; friend presence cannot enter technical or tool posture',
      ],
    );
  }
}

class KaiCapabilityBroker {
  KaiCapabilityBroker._();

  static KaiCapabilityManifest forContext(KaiSurfaceContext? context) {
    if (context == null) {
      return const KaiCapabilityManifest(
        allowsGeneralTools: false,
        allowsTechnicalConversation: false,
        worldCapabilities: {},
      );
    }

    final worldCapabilities = context.gogglesOn
        ? context.profile.capabilities
            .where((capability) =>
                capability == KaiSurfaceCapability.worldInspection ||
                capability == KaiSurfaceCapability.worldActions ||
                capability == KaiSurfaceCapability.worldCreation)
            .toSet()
        : <KaiSurfaceCapability>{};

    return KaiCapabilityManifest(
      allowsGeneralTools: context.allowsGeneralTools,
      allowsTechnicalConversation: context.allowsTechnicalConversation,
      worldCapabilities: worldCapabilities,
    );
  }
}
