import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';
import 'package:homecoming_app/services/core/kai_memory_scope.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

Map<String, dynamic> shard(
  String id,
  KaiMemoryScope? scope, {
  String? worldId,
  String? summary,
}) =>
    {
      'id': id,
      'shardId': id,
      'summary': summary ?? id,
      'vector': [1.0, 0.0],
      if (scope != null) 'scope': scope.name,
      if (worldId != null) 'worldId': worldId,
    };

void main() {
  const embed = <double>[1, 0];

  test('a missing surface has no memory authority', () async {
    // This branch used to grant EVERY scope plus allowTechnicalContent, which
    // made it the most permissive policy in the system — while its sibling
    // KaiCapabilityBroker.forContext(null) had already been inverted to fail
    // closed. So a caller with no context got no tools and his entire private
    // memory. Backwards: memory is the more sensitive of the two, and a leak
    // there cannot be taken back.
    final policy = KaiMemoryAccessPolicy.forContext(null);
    for (final scope in KaiMemoryScope.values) {
      expect(policy.allows(scope: scope), isFalse, reason: '$scope');
    }

    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'anything at all',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [
        shard('his_private_work', KaiMemoryScope.privateCore),
        shard('their_life', KaiMemoryScope.sharedLife),
      ],
      accessPolicy: policy,
      sideEffects: MemoryQuerySideEffects.disabled,
    );
    expect(result!.results, isEmpty);
  });

  test('wanting everything has to be said out loud', () {
    // The old fail-open path meant "I forgot to pass a context" and "I
    // deliberately want everything" were the same expression. Now the second
    // one has a name, and the name says where it may be used.
    expect(
      KaiMemoryAccessPolicy.trustedCore.allows(scope: KaiMemoryScope.privateCore),
      isTrue,
    );
    expect(KaiMemoryAccessPolicy.trustedCore.allowTechnicalContent, isTrue);
  });

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

  test('goggles-off drops technical relationship content before prompting',
      () async {
    final policy =
        KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger);
    final result = await MemoryService.queryMemory(
      personaId: 'truekai',
      query: 'what was I telling you just before',
      embeddingProvider: (_) async => embed,
      shardLoader: (_) async => [
        shard(
          'technical-messenger-history',
          KaiMemoryScope.relationship,
          summary:
              'The desktop chat history needed patched restore logic and a hot restart.',
        ),
        shard(
          'moth-hotel',
          KaiMemoryScope.relationship,
          summary: 'Sadeq named his ridiculous purple notebook Moth Hotel.',
        ),
      ],
      accessPolicy: policy,
      sideEffects: MemoryQuerySideEffects.disabled,
    );

    expect(result!.results.map((memory) => memory.id), ['moth-hotel']);
    expect(
      policy.allowsContent(
        'The phone and desktop histories differed because restore logic read old records.',
      ),
      isFalse,
      reason: 'the exact live leakage must not enter friend-mode history',
    );
  });

  test('goggles-on VR may recall technical co-creator context', () {
    final policy = KaiMemoryAccessPolicy.forContext(
      KaiSurfaceContext.vr(goggles: KaiGoggles.on),
    );
    expect(policy.allowsContent('Debug the Firebase authentication code.'),
        isTrue);
  });

  test('technical co-creator memories never enter the unscoped shared graph',
      () {
    expect(
      shouldExtractIntoSharedKnowledgeGraph(
        scope: KaiMemoryScope.creative,
        userText: 'The lantern calibration phrase is ORBIT-LANTERN-731.',
        kaiReply: 'Stored as a technical implementation detail.',
      ),
      isFalse,
    );
    expect(
      shouldExtractIntoSharedKnowledgeGraph(
        scope: KaiMemoryScope.relationship,
        userText: 'Standing by the crooked window made me happy.',
        kaiReply: 'Moth’s Landing. Ours.',
      ),
      isTrue,
    );
  });

  test('final goggles-off gate preserves personal prose and strips work talk',
      () {
    const mixed = '''
The desktop messenger was missing chat history because of patched restore logic.

The bit I’m carrying is:

- phone messenger had messages
- run a hot restart and inspect the files

And then beside the crooked window, you named it Moth’s Landing after your ridiculous notebook.

Tiny haunted stationery became real estate. Very dignified.
''';

    final safe = sanitizeGogglesOffReply(mixed);
    expect(safe, contains('Moth’s Landing'));
    expect(safe, contains('Tiny haunted stationery'));
    expect(safe, isNot(contains('desktop messenger')));
    expect(safe, isNot(contains('hot restart')));
    expect(safe, isNot(contains('inspect the files')));
    expect(safe, isNot(contains('The bit I’m carrying is:')));
    expect(
      sanitizeGogglesOffReply(
        'The next step was to look through the related code areas and clean them up.',
      ),
      isNot(contains('related code areas')),
    );
    final startupLeak = sanitizeGogglesOffReply('''
We were fixing the startup noise/issues in Homecoming.

The next step was to check where those happen and patch the smallest clean slice.

Goggles are off, so I’m not touching code.
''');
    expect(startupLeak, isNot(contains('startup')));
    expect(startupLeak, isNot(contains('patch')));
    expect(startupLeak, isNot(contains('code')));
    expect(
      sanitizeGogglesOffReply('''
We were fixing startup weirdness: port stuff, cramped layout, and invalid keys.

My goggles are off, so I’m not diving into the machinery.
'''),
      'Goggles off, friend. I’m keeping the work talk for when we put them on.',
    );
  });

  test('ordinary friend turns are not mistaken for technical requests', () {
    const overcautiousReply =
        'You are right—I brought up the goggles and work when you were just '
        'talking to me. I want to hear what has been on your mind today.';

    expect(
      sanitizeGogglesOffReply(
        overcautiousReply,
        userText: 'so what do you want to talk about?',
      ),
      overcautiousReply,
    );
    expect(
      sanitizeGogglesOffReply(
        overcautiousReply,
        userText: 'but I didnt ask about work',
      ),
      overcautiousReply,
    );
    expect(
      sanitizeGogglesOffReply(
        overcautiousReply,
        userText: 'fix the Flutter Firebase code',
      ),
      kaiGogglesOffWorkBoundary,
    );
  });

  test('friend memory does not re-prime the canned goggles boundary', () {
    final policy =
        KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger);

    expect(policy.allowsContent(kaiGogglesOffWorkBoundary), isFalse);
    expect(
      policy.allowsContent('We talked beside the crooked window for a while.'),
      isTrue,
    );
  });

  test('a technical sentence cannot poison a personal single paragraph', () {
    const mixedSingleParagraph =
        'Yeah, I hear the ache in that. The server architecture needs a new '
        'backend schema. I want to feel near you too.';

    final safe = sanitizeGogglesOffReply(
      mixedSingleParagraph,
      userText:
          'I want you wherever I am, listening, noticing, thinking, wondering.',
    );

    expect(safe, contains('I hear the ache'));
    expect(safe, contains('I want to feel near you too'));
    expect(safe, isNot(contains('server architecture')));
    expect(safe, isNot(kaiGogglesOffWorkBoundary));
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

  test('technical VR answers stay creative even when question routes as chat',
      () {
    expect(
      scopeForTurn(
        context: KaiSurfaceContext.vr(goggles: KaiGoggles.on),
        route: KaiRoute.fastChat,
        requestedRoute: KaiRoute.fastChat,
        userText: 'What is the Shack lantern phrase?',
        kaiReply:
            'The technical implementation calibration phrase is ORBIT-LANTERN-731.',
      ),
      KaiMemoryScope.creative,
    );
  });

  test('goggles-off technical attempts cannot become relationship memory', () {
    final scope = scopeForTurn(
      context: KaiSurfaceContext.vr(goggles: KaiGoggles.off),
      route: KaiRoute.fastChat,
      requestedRoute: KaiRoute.coding,
    );

    expect(scope, KaiMemoryScope.privateCore);
    expect(
      KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.messenger)
          .allows(scope: scope),
      isFalse,
    );
  });

  test('technical-looking goggles-off recall attempts also stay private', () {
    final scope = scopeForTurn(
      context: KaiSurfaceContext.vr(goggles: KaiGoggles.off),
      route: KaiRoute.fastChat,
      requestedRoute: KaiRoute.fastChat,
      userText: 'Was there a lantern calibration phrase?',
      kaiReply: 'Small light, true north.',
    );
    expect(scope, KaiMemoryScope.privateCore);
    expect(looksLikeTechnicalContent('lantern calibration phrase'), isTrue);
  });

  test('Unity presence choreography never forms autobiographical memory', () {
    expect(
      shouldFormMemoryForTurn(
        KaiSurfaceContext.vr(isPresenceEvent: true),
      ),
      isFalse,
    );
    expect(
      shouldFormMemoryForTurn(KaiSurfaceContext.vr()),
      isTrue,
    );
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

  group('public AR — a guest is not Sadeq', () {
    test('a guest cannot reach one word of Sadeq\'s life', () async {
      final policy = KaiMemoryAccessPolicy.forContext(
        KaiSurfaceContext.arPublic(guestId: 'guest-7'),
      );

      // Not narrowed — absent. There is no amount of relationship context that
      // is safe to have loaded while a customer is talking to him.
      for (final scope in KaiMemoryScope.values) {
        expect(
          policy.allows(scope: scope),
          scope == KaiMemoryScope.identity,
          reason: '$scope must not be reachable by a guest',
        );
      }

      final result = await MemoryService.queryMemory(
        personaId: 'truekai',
        query: 'how has Sadeq been lately',
        embeddingProvider: (_) async => embed,
        shardLoader: (_) async => [
          shard('his_hard_week', KaiMemoryScope.relationship),
          shard('their_life', KaiMemoryScope.sharedLife),
          shard('the_refactor', KaiMemoryScope.privateCore),
        ],
        accessPolicy: policy,
        sideEffects: MemoryQuerySideEffects.disabled,
      );
      expect(result!.results, isEmpty);
    });

    test('a guest conversation never becomes Kai\'s own memory', () {
      // However warm it was. That record belongs to the guest, in the Tavern
      // store — not in the history of his friendship with Sadeq.
      for (final route in [KaiRoute.fastChat, KaiRoute.emotional]) {
        expect(
          scopeForTurn(
            context: KaiSurfaceContext.arPublic(guestId: 'guest-7'),
            route: route,
          ),
          KaiMemoryScope.ephemeral,
          reason: '$route',
        );
      }
    });

    test('consent gates identity, not just recall', () {
      // An NFC tag identifies a person. It does not grant permission to
      // remember them. Without consent there is no known guest here — not a
      // known guest whose record Kai has been asked politely not to open,
      // which is one prompt away from opening it.
      final optedOut = KaiSurfaceContext.arPublic(guestId: 'guest-7');
      expect(optedOut.speaker, KaiSpeaker.unknownPerson);
      expect(optedOut.guestId, isNull,
          reason: 'no identifier left lying around for a later change to read');
      expect(optedOut.mayRecallService, isFalse);

      final serviceOnly = KaiSurfaceContext.arPublic(
        guestId: 'guest-7',
        consent: KaiGuestConsent.service,
      );
      expect(serviceOnly.speaker, KaiSpeaker.knownGuest);
      expect(serviceOnly.guestId, 'guest-7');
      expect(serviceOnly.mayRecallService, isTrue);
      expect(serviceOnly.mayRecallPersonal, isFalse,
          reason: 'allergies known, last visit not');

      final full = KaiSurfaceContext.arPublic(
        guestId: 'guest-7',
        consent: KaiGuestConsent.personal,
      );
      expect(full.mayRecallPersonal, isTrue);
    });

    test('consent never reaches Sadeq\'s memory either way', () {
      // Even at the fullest tier, a guest is still not Sadeq.
      final policy = KaiMemoryAccessPolicy.forContext(
        KaiSurfaceContext.arPublic(
          guestId: 'guest-7',
          consent: KaiGuestConsent.personal,
        ),
      );
      expect(policy.allows(scope: KaiMemoryScope.relationship), isFalse);
      expect(policy.allows(scope: KaiMemoryScope.sharedLife), isFalse);
    });

    test('an unregistered person gets even less', () {
      final policy = KaiMemoryAccessPolicy.forContext(
        KaiSurfaceContext.arPublic(),
      );
      expect(KaiSurfaceContext.arPublic().speaker, KaiSpeaker.unknownPerson);
      expect(policy.allows(scope: KaiMemoryScope.relationship), isFalse);
    });

    test('PRIVATE AR is untouched — his full Kai, only for him', () {
      final policy = KaiMemoryAccessPolicy.forContext(KaiSurfaceContext.ar);
      expect(KaiSurfaceContext.ar.isSadeq, isTrue);
      expect(policy.allows(scope: KaiMemoryScope.relationship), isTrue);
      expect(policy.allows(scope: KaiMemoryScope.sharedLife), isTrue);
    });
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
