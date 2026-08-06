import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';
import 'package:homecoming_app/services/core/kai_memory_scope.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

Map<String, dynamic> shard(
  String id,
  KaiMemoryScope? scope, {
  String? worldId,
}) =>
    {
      'id': id,
      'shardId': id,
      'summary': id,
      'vector': [1.0, 0.0],
      if (scope != null) 'scope': scope.name,
      if (worldId != null) 'worldId': worldId,
    };

void main() {
  const embed = <double>[1, 0];

  test('missing and unknown scopes fail closed as legacyUnscoped', () {
    expect(parseKaiMemoryScope(null), KaiMemoryScope.legacyUnscoped);
    expect(parseKaiMemoryScope(''), KaiMemoryScope.legacyUnscoped);
    expect(parseKaiMemoryScope('invented'), KaiMemoryScope.legacyUnscoped);
  });

  test('Messenger sees relationship memory but not legacy or private core',
      () async {
    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'remember our meaningful conversation about the evening',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [
        shard('relationship', KaiMemoryScope.relationship),
        shard('legacy', null),
        shard('private', KaiMemoryScope.privateCore),
      ],
      accessPolicy:
          KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger),
      sideEffects: MemoryQuerySideEffects.disabled,
    );

    expect(result!.results.map((memory) => memory.id), ['relationship']);
  });

  test('trusted core sees legacy records during migration', () async {
    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'remember the old imported technical discussion',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [shard('legacy', null)],
      accessPolicy: KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.desktop),
      sideEffects: MemoryQuerySideEffects.disabled,
    );

    expect(result!.results.single.scope, KaiMemoryScope.legacyUnscoped);
  });

  test('VR world memories require goggles and matching world identity', () {
    final off = KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.vr());
    final shack = KaiMemoryAccessPolicy.forContext(
      KaiSurfaceContext.vr(goggles: KaiGoggles.on, worldId: 'vr_shack'),
    );

    expect(
      off.allows(scope: KaiMemoryScope.world, memoryWorldId: 'vr_shack'),
      isFalse,
    );
    expect(
      shack.allows(scope: KaiMemoryScope.world, memoryWorldId: 'vr_shack'),
      isTrue,
    );
    expect(
      shack.allows(scope: KaiMemoryScope.world, memoryWorldId: 'other_world'),
      isFalse,
    );
    expect(
      shack.allows(scope: KaiMemoryScope.episodic),
      isFalse,
      reason: 'VR must not pre-authorize a scope before its writer exists',
    );
  });

  test('turn scoping keeps technical core memories out of friend surfaces', () {
    expect(
      scopeForTurn(
        context: KaiSurfaceContext.desktop,
        route: KaiRoute.coding,
      ),
      KaiMemoryScope.privateCore,
    );
    expect(
      scopeForTurn(
        context: KaiSurfaceContext.messenger,
        route: KaiRoute.fastChat,
      ),
      KaiMemoryScope.relationship,
    );
    expect(
      scopeForTurn(
        context: KaiSurfaceContext.vr(goggles: KaiGoggles.on),
        route: KaiRoute.contemplate,
      ),
      KaiMemoryScope.creative,
    );
  });

  test('a shared VR moment survives the trip back to Messenger', () async {
    // The one-Kai invariant, end to end: what he writes in the Shack must be
    // readable when Sadeq opens Messenger an hour later. This composes the
    // WRITE scope with the READ policy, because either one alone can be right
    // while the pair is broken — which is exactly what happened when VR wrote
    // `creative` (core + VR only) and every VR memory was stranded in VR.
    final vr =
        KaiSurfaceContext.vr(goggles: KaiGoggles.on, worldId: 'vr_shack');
    final writtenScope = scopeForTurn(context: vr, route: KaiRoute.fastChat);

    expect(writtenScope, KaiMemoryScope.relationship);

    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'what did we do in the shack',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [shard('shack_afternoon', writtenScope)],
      accessPolicy:
          KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger),
      sideEffects: MemoryQuerySideEffects.disabled,
    );

    expect(
      result!.results.map((memory) => memory.id),
      ['shack_afternoon'],
      reason: 'a meaningful VR experience must reach the friend surface',
    );
  });

  test('VR building work stays in VR even though the experience travels',
      () async {
    // The other half: the work of building is not the experience of building.
    final vr =
        KaiSurfaceContext.vr(goggles: KaiGoggles.on, worldId: 'vr_shack');
    final workScope = scopeForTurn(context: vr, route: KaiRoute.coding);

    expect(workScope, KaiMemoryScope.creative);

    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'what did we do in the shack',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [shard('lighting_rig_rework', workScope)],
      accessPolicy:
          KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger),
      sideEffects: MemoryQuerySideEffects.disabled,
    );

    expect(result!.results, isEmpty);
  });

  test('what Kai sees in AR does not become his personal memory', () async {
    // AR narrates a room containing other people. Before this, goggles-off
    // meant relationship scope, so "that's Ahmed, third visit, walnut allergy"
    // became durable personal memory and surfaced on Messenger as though it
    // were part of Kai's own life. Guest facts belong in the Tavern store,
    // reached by lookup — not in the record of his friendship with Sadeq.
    final arScope = scopeForTurn(
      context: KaiSurfaceContext.ar,
      route: KaiRoute.fastChat,
    );
    expect(arScope, KaiMemoryScope.ephemeral);

    for (final surface in [
      KaiSurfaceContext.messenger,
      KaiSurfaceContext.desktop,
      KaiSurfaceContext.ar,
    ]) {
      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'who was in the bar',
        embeddingProvider: (_) async => embed,
        shardLoader: (_) async => [shard('guest_chatter', arScope)],
        accessPolicy: KaiMemoryAccessPolicy.forContext(surface),
        sideEffects: MemoryQuerySideEffects.disabled,
      );
      expect(
        result!.results,
        isEmpty,
        reason: 'AR chatter must not resurface on ${surface.surfaceId}',
      );
    }
  });

  test('a real moment with Sadeq in AR is still his to keep', () {
    // The other half: AR being transient must not cost him a genuine one.
    expect(
      scopeForTurn(
        context: KaiSurfaceContext.ar,
        route: KaiRoute.emotional,
      ),
      KaiMemoryScope.relationship,
    );
  });

  test('VR creative event and artifact are two records by construction', () {
    final pair = KaiVrMemoryPair.forWorld('vr_shack');
    expect(pair.experienceScope, KaiMemoryScope.relationship);
    expect(pair.artifactScope, KaiMemoryScope.world);
    expect(pair.worldId, 'vr_shack');
  });

  test('scoped write record carries provenance and world metadata', () {
    final record = buildScopedMemoryRecord(
      vector: embed,
      summary: 'We built the crooked loft window together.',
      scope: KaiMemoryScope.world,
      provenance: KaiMemoryProvenance.worldArtifact,
      timestamp: '2026-08-05T20:00:00Z',
      nowMs: 42,
      surfaceId: 'vr',
      worldId: 'vr_shack',
      sessionId: 'visit-7',
    );

    expect(record['scope'], 'world');
    expect(record['provenance'], 'worldArtifact');
    expect(record['surfaceId'], 'vr');
    expect(record['worldId'], 'vr_shack');
    expect(record['sessionId'], 'visit-7');
  });
}
