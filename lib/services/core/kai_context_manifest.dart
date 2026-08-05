import 'kai_capability_broker.dart';
import 'kai_router_service.dart';
import 'kai_surface_context.dart';

enum KaiContextPart {
  identity,
  mood,
  userModel,
  goals,
  activeJob,
  noticed,
  codeWorkspace,
  projectLadder,
  workingOn,
  bond,
  worlds,
  innerMonologue,
  embodiment,
  craftRules,
  selfNotes,
}

/// The single source of truth for which context providers may run this turn.
/// It subsumes KaiContextBlock's former independent route skip map.
class KaiContextManifest {
  const KaiContextManifest({
    required this.included,
    required this.includeTechnicalPreamble,
    required this.includeToolMachinery,
  });

  final Set<KaiContextPart> included;
  final bool includeTechnicalPreamble;
  final bool includeToolMachinery;

  bool includes(KaiContextPart part) => included.contains(part);

  Set<int> get skippedIndices => {
        for (var index = 0; index < KaiContextPart.values.length; index++)
          if (!included.contains(KaiContextPart.values[index])) index,
      };

  Future<String> loadString(
    KaiContextPart part,
    Future<String> Function() loader,
  ) =>
      includes(part) ? loader() : Future.value('');

  static KaiContextManifest forTurn({
    required KaiRoute route,
    required KaiCapabilityManifest capabilities,
    KaiSurfaceContext? surface,
  }) {
    if (!capabilities.allowsTechnicalConversation) {
      return KaiContextManifest(
        included: {
          KaiContextPart.identity,
          KaiContextPart.mood,
          KaiContextPart.userModel,
          KaiContextPart.goals,
          KaiContextPart.bond,
          if (surface?.surface == KaiSurface.ar ||
              surface?.surface == KaiSurface.vr)
            KaiContextPart.embodiment,
        },
        includeTechnicalPreamble: false,
        includeToolMachinery: false,
      );
    }

    return forRoute(route);
  }

  static KaiContextManifest forRoute(KaiRoute? route) {
    final skipped = switch (route) {
      KaiRoute.fastChat => {5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
      KaiRoute.coding => {9, 10, 11, 12, 13, 14},
      KaiRoute.tool => {7, 10},
      KaiRoute.emotional => {6, 7, 10},
      KaiRoute.contemplate || null => <int>{},
    };
    return KaiContextManifest(
      included: {
        for (var index = 0; index < KaiContextPart.values.length; index++)
          if (!skipped.contains(index)) KaiContextPart.values[index],
      },
      includeTechnicalPreamble: true,
      includeToolMachinery: true,
    );
  }
}
