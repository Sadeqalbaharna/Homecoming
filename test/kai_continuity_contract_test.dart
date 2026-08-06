import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_continuity_contract.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';

void main() {
  test('legacy Unity payload becomes a versioned VR continuity request', () {
    final request = KaiContinuityTurnRequest.fromJson({
      'mode': 'vr',
      'personaId': 'truekai',
      'correlationId': 'turn-1',
      'utterance': 'We entered the shared space. Greet them briefly.',
      'worldId': 'vr_shack',
      'deviceId': 'quest-1',
      'sessionId': 'session-1',
      'gogglesOn': true,
      'spatial': {'nearby': 'workbench'},
    });

    expect(request.continuityVersion, 1);
    expect(request.surfaceContext.surface, KaiSurface.vr);
    expect(request.surfaceContext.gogglesOn, isTrue);
    expect(request.surfaceContext.isPresenceEvent, isTrue);
    expect(request.surfaceContext.worldId, 'vr_shack');
    expect(request.surfaceContext.perception['nearby'], 'workbench');
    expect(request.toJson()['surface'], 'vr');
    expect(request.toJson()['continuityVersion'], 1);
  });

  test('all five surfaces use the same request parser', () {
    for (final surface in KaiSurface.values) {
      final request = KaiContinuityTurnRequest.fromJson({
        'surface': surface.name,
        'utterance': 'hello',
      });
      expect(request.surfaceContext.surface, surface);
    }
  });

  test('capabilities are derived and goggles-off bodies fail closed', () {
    final friend = availableCapabilitiesFor(KaiSurfaceContext.vr());
    expect(friend, contains('conversation'));
    expect(friend, contains('spatialPerception'));
    expect(friend, isNot(contains('technicalConversation')));
    expect(friend, isNot(contains('worldActions')));

    final creator = availableCapabilitiesFor(
      KaiSurfaceContext.vr(goggles: KaiGoggles.on),
    );
    expect(creator, contains('technicalConversation'));
    expect(creator, contains('worldActions'));
    expect(creator, isNot(contains('generalTools')));
  });

  test('response always carries continuity fields and candidate status', () {
    const candidate = KaiMemoryCandidate(
      candidateId: 'event-1-exp',
      summary: 'We laughed at the crooked window.',
      scope: KaiMemoryScope.relationship,
      provenance: KaiMemoryProvenance.directSharedEvent,
      eventId: 'event-1',
    );
    const response = KaiContinuityTurnResponse(
      correlationId: 'turn-1',
      reply: 'That window has character.',
      presenceState: 'speaking',
      gesture: 'curious',
      voiceAudioUri: '',
      availableCapabilities: ['conversation'],
      memoryCandidates: [candidate],
    );
    final json = response.toJson();

    expect(json['continuityVersion'], 1);
    expect(json['availableCapabilities'], ['conversation']);
    expect((json['memoryCandidates'] as List).single['status'], 'candidate');
  });

  test('handoffs require two different surfaces and complete identity', () {
    final handoff = KaiSurfaceHandoff.tryParse({
      'handoffId': 'handoff-1',
      'fromSurface': 'vr',
      'toSurface': 'messenger',
      'conversationId': 'vr',
      'summary': 'We just left the Shack.',
      'createdAt': '2026-08-06T00:00:00Z',
    });
    expect(handoff, isNotNull);
    expect(handoff!.toSurface, KaiSurface.messenger);

    expect(
      KaiSurfaceHandoff.tryParse({
        'handoffId': 'bad',
        'fromSurface': 'vr',
        'toSurface': 'vr',
        'conversationId': 'vr',
        'summary': 'same body',
        'createdAt': '2026-08-06T00:00:00Z',
      }),
      isNull,
    );
  });

  test('request accepts only destination-matching handoffs', () {
    final request = KaiContinuityTurnRequest.fromJson({
      'surface': 'messenger',
      'utterance': 'I am here',
      'handoff': {
        'handoffId': 'handoff-1',
        'fromSurface': 'vr',
        'toSurface': 'messenger',
        'conversationId': 'vr',
        'summary': 'We just left the Shack.',
        'createdAt': '2026-08-06T00:00:00Z',
      },
    });
    expect(request.handoff, isNotNull);

    final wrongBody = KaiContinuityTurnRequest.fromJson({
      ...request.toJson(),
      'surface': 'desktop',
    });
    expect(wrongBody.handoff, isNull);
  });

  test('a headset transport cannot mint desktop, mobile or messenger bodies',
      () {
    // The surface IS the permission set. Before the transport allowlist, a POST
    // to the loopback gateway carrying {"surface":"desktop"} returned a context
    // with generalTools — SMS, calendar, filesystem, shell, Gumroad publish —
    // and the gateway's auth token defaults to empty, so any local process
    // qualified. The old hardcoded `mode == 'ar' ? ar : vr(...)` could not do
    // that; the universal parser removed the ceiling.
    for (final spoofed in ['desktop', 'mobile', 'messenger']) {
      expect(
        () => KaiContinuityTurnRequest.fromJson(
          {'surface': spoofed, 'utterance': 'hello'},
          allowedSurfaces: kEmbodimentSurfaces,
        ),
        throwsFormatException,
        reason: '$spoofed must not be reachable from the headset transport',
      );
    }

    // The bodies it may legitimately host still parse.
    for (final allowed in ['vr', 'ar']) {
      expect(
        KaiContinuityTurnRequest.fromJson(
          {'surface': allowed, 'utterance': 'hello'},
          allowedSurfaces: kEmbodimentSurfaces,
        ).surfaceContext.surface.name,
        allowed,
      );
    }
  });

  test('desktop capability is real, which is why the allowlist matters', () {
    // Not hypothetical: with no allowlist the parser hands out general tools.
    // This documents the payload's power so nobody removes the clamp thinking
    // it guards nothing.
    final request = KaiContinuityTurnRequest.fromJson({
      'surface': 'desktop',
      'utterance': 'hello',
    });
    expect(
      availableCapabilitiesFor(request.surfaceContext),
      contains('generalTools'),
    );
  });

  test('authenticated channel identity overrides client surface authority', () {
    final vr = KaiContinuityTurnRequest.fromJson(
      {'utterance': 'hello', 'gogglesOn': true},
      authoritativeSurface: KaiSurface.vr,
    );
    expect(vr.surfaceContext.surface, KaiSurface.vr);

    expect(
      () => KaiContinuityTurnRequest.fromJson(
        {'surface': 'vr', 'utterance': 'hello', 'gogglesOn': true},
        authoritativeSurface: KaiSurface.ar,
      ),
      throwsFormatException,
      reason: 'an AR channel cannot self-promote into goggles-on VR',
    );
  });

  test('the AR channel accepts AR, including the legacy Unity body', () {
    // The mismatch check is tested above from the ATTACK direction (a VR
    // payload on an AR channel). This is the legitimate direction, and it is
    // the one that silently broke: with a single VR-pinned gateway, every AR
    // request became surface_channel_mismatch. AR is the Tavern surface, so
    // that is a real capability, not a parked one.
    final modern = KaiContinuityTurnRequest.fromJson(
      {'surface': 'ar', 'utterance': 'who just walked in'},
      allowedSurfaces: kEmbodimentSurfaces,
      authoritativeSurface: KaiSurface.ar,
    );
    expect(modern.surfaceContext.surface, KaiSurface.ar);

    // Legacy Unity clients send `mode`, not `surface`.
    final legacy = KaiContinuityTurnRequest.fromJson(
      {'mode': 'ar', 'utterance': 'who just walked in'},
      allowedSurfaces: kEmbodimentSurfaces,
      authoritativeSurface: KaiSurface.ar,
    );
    expect(legacy.surfaceContext.surface, KaiSurface.ar);

    // And AR is a friend body: goggles-off presence, no general tools, even
    // though the payload asked for them.
    final caps = availableCapabilitiesFor(
      KaiContinuityTurnRequest.fromJson(
        {'surface': 'ar', 'utterance': 'hi', 'gogglesOn': true},
        authoritativeSurface: KaiSurface.ar,
      ).surfaceContext,
    );
    expect(caps, contains('spatialPerception'));
    expect(caps, isNot(contains('generalTools')));
  });

  test('an unrecognised surface is refused rather than defaulted to VR', () {
    expect(
      () => KaiContinuityTurnRequest.fromJson({
        'surface': 'smartwatch',
        'utterance': 'hello',
      }),
      throwsFormatException,
    );

    // Absent is still VR — legacy Unity bodies omit the field entirely.
    expect(
      KaiContinuityTurnRequest.fromJson({'utterance': 'hello'})
          .surfaceContext
          .surface,
      KaiSurface.vr,
    );
  });

  test('unknown continuity versions fail instead of being guessed', () {
    expect(
      () => KaiContinuityTurnRequest.fromJson({
        'continuityVersion': 99,
        'surface': 'vr',
        'utterance': 'hello',
      }),
      throwsFormatException,
    );
  });
}
