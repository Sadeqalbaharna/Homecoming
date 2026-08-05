enum KaiMemoryScope {
  identity,
  relationship,
  sharedLife,
  creative,
  world,
  episodic,
  ephemeral,
  privateCore,
  legacyUnscoped,
}

enum KaiMemoryProvenance {
  directConversation,
  directSharedEvent,
  worldArtifact,
  promoted,
  importedLegacy,
}

KaiMemoryScope parseKaiMemoryScope(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return KaiMemoryScope.legacyUnscoped;
  return KaiMemoryScope.values.firstWhere(
    (scope) => scope.name == raw,
    orElse: () => KaiMemoryScope.legacyUnscoped,
  );
}

class KaiVrMemoryPair {
  const KaiVrMemoryPair({
    required this.experienceScope,
    required this.artifactScope,
    required this.worldId,
  });

  final KaiMemoryScope experienceScope;
  final KaiMemoryScope artifactScope;
  final String worldId;

  static KaiVrMemoryPair forWorld(String worldId) => KaiVrMemoryPair(
        experienceScope: KaiMemoryScope.relationship,
        artifactScope: KaiMemoryScope.world,
        worldId: worldId,
      );
}

Map<String, dynamic> buildScopedMemoryRecord({
  required List<double> vector,
  required String summary,
  required KaiMemoryScope scope,
  required KaiMemoryProvenance provenance,
  required String timestamp,
  required int nowMs,
  String? surfaceId,
  String? worldId,
  String? sessionId,
}) =>
    {
      'vector': vector,
      'summary':
          summary.length > 1200 ? '${summary.substring(0, 1200)}…' : summary,
      'timestamp': timestamp,
      'source': 'live',
      'scope': scope.name,
      'provenance': provenance.name,
      if (surfaceId != null) 'surfaceId': surfaceId,
      if (worldId != null) 'worldId': worldId,
      if (sessionId != null) 'sessionId': sessionId,
      'strength': 1.0,
      'lastAccessed': nowMs,
      'hits': 0,
    };
