import 'kai_capability_broker.dart';
import 'kai_surface_context.dart';

/// Versioned transport contract shared by every body that hosts Kai.
///
/// The client declares where the turn came from; Homecoming derives authority
/// from [surfaceContext] and never trusts a client-provided capability list.
class KaiContinuityContract {
  KaiContinuityContract._();

  static const version = 1;
}

/// The only bodies the local embodiment transport may host.
///
/// Lives beside the contract rather than inside the gateway so the allowlist is
/// visible to anyone reading what the parser can be asked to build, and so a
/// second transport has to make its own deliberate declaration rather than
/// inheriting this one by accident.
const Set<KaiSurface> kEmbodimentSurfaces = {KaiSurface.vr, KaiSurface.ar};

class KaiMemoryCandidate {
  const KaiMemoryCandidate({
    required this.candidateId,
    required this.summary,
    required this.scope,
    required this.provenance,
    this.worldId,
    this.eventId,
  });

  final String candidateId;
  final String summary;
  final KaiMemoryScope scope;
  final KaiMemoryProvenance provenance;
  final String? worldId;
  final String? eventId;

  Map<String, Object?> toJson() => {
        'candidateId': candidateId,
        'summary': summary,
        'scope': scope.name,
        'provenance': provenance.name,
        if (worldId != null) 'worldId': worldId,
        if (eventId != null) 'eventId': eventId,
        // A candidate is a proposal. Persistence remains MemoryService's job.
        'status': 'candidate',
      };
}

class KaiSurfaceHandoff {
  const KaiSurfaceHandoff({
    required this.handoffId,
    required this.fromSurface,
    required this.toSurface,
    required this.conversationId,
    required this.summary,
    required this.createdAt,
  });

  final String handoffId;
  final KaiSurface fromSurface;
  final KaiSurface toSurface;
  final String conversationId;
  final String summary;
  final String createdAt;

  Map<String, Object?> toJson() => {
        'handoffId': handoffId,
        'fromSurface': fromSurface.name,
        'toSurface': toSurface.name,
        'conversationId': conversationId,
        'summary': summary,
        'createdAt': createdAt,
      };

  static KaiSurfaceHandoff? tryParse(Object? value) {
    if (value is! Map) return null;
    final from = _parseSurface(value['fromSurface']);
    final to = _parseSurface(value['toSurface']);
    final id = value['handoffId']?.toString().trim() ?? '';
    final conversation = value['conversationId']?.toString().trim() ?? '';
    final summary = value['summary']?.toString().trim() ?? '';
    final createdAt = value['createdAt']?.toString().trim() ?? '';
    if (from == null ||
        to == null ||
        from == to ||
        id.isEmpty ||
        conversation.isEmpty ||
        summary.isEmpty ||
        createdAt.isEmpty) {
      return null;
    }
    return KaiSurfaceHandoff(
      handoffId: id,
      fromSurface: from,
      toSurface: to,
      conversationId: conversation,
      summary: summary,
      createdAt: createdAt,
    );
  }
}

class KaiContinuityTurnRequest {
  const KaiContinuityTurnRequest({
    required this.personaId,
    required this.correlationId,
    required this.utterance,
    required this.surfaceContext,
    this.handoff,
  });

  final String personaId;
  final String correlationId;
  final String utterance;
  final KaiSurfaceContext surfaceContext;
  final KaiSurfaceHandoff? handoff;

  int get continuityVersion => KaiContinuityContract.version;

  Map<String, Object?> toJson() => {
        'continuityVersion': continuityVersion,
        'personaId': personaId,
        'correlationId': correlationId,
        'utterance': utterance,
        'surface': surfaceContext.surface.name,
        'conversationId': surfaceContext.conversationId,
        if (surfaceContext.deviceId != null)
          'deviceId': surfaceContext.deviceId,
        if (surfaceContext.worldId != null) 'worldId': surfaceContext.worldId,
        if (surfaceContext.sessionId != null)
          'sessionId': surfaceContext.sessionId,
        'gogglesOn': surfaceContext.gogglesOn,
        'isPresenceEvent': surfaceContext.isPresenceEvent,
        if (surfaceContext.perception.isNotEmpty)
          'spatial': surfaceContext.perception,
        if (handoff != null) 'handoff': handoff!.toJson(),
      };

  /// Backward-compatible parser for the existing Unity body. New clients send
  /// `surface`; old clients may continue sending `mode`.
  /// [allowedSurfaces] is the set of bodies THIS TRANSPORT may legitimately
  /// host. Pass it from the transport, never from the payload.
  ///
  /// ── Why this parameter exists ─────────────────────────────────────────────
  ///
  /// The surface is the authority. `allowsGeneralTools`, `allowsTechnical
  /// Conversation` and the world capabilities are all derived from it, so a
  /// caller that chooses its own surface has chosen its own permissions. The
  /// class doc says Homecoming "never trusts a client-provided capability
  /// list", and that is true — but it was trusting the client-provided SURFACE,
  /// which decides the list.
  ///
  /// Before this parser existed the embodiment gateway hardcoded
  /// `mode == 'ar' ? ar : vr(...)`, so the worst a malicious loopback POST
  /// could obtain was goggles-on VR: world capabilities, no general tools.
  /// A universal five-surface parser removed that ceiling. `{"surface":
  /// "desktop"}` returns a context with generalTools — SMS, calendar,
  /// filesystem, shell, Gumroad publish — and the gateway's auth token defaults
  /// to empty, so `_authorized` returns true for any local process.
  ///
  /// The contract stays universal; the TRANSPORT declares what it can host.
  /// That is the same principle the broker must eventually follow server-side:
  /// authority comes from the channel, never from the body.
  static KaiContinuityTurnRequest fromJson(
    Map<String, dynamic> body, {
    String defaultPersona = 'truekai',
    Set<KaiSurface>? allowedSurfaces,
    KaiSurface? authoritativeSurface,
  }) {
    final declaredVersion = body['continuityVersion'];
    if (declaredVersion != null &&
        int.tryParse(declaredVersion.toString()) !=
            KaiContinuityContract.version) {
      throw const FormatException('unsupported_continuity_version');
    }

    // An unrecognised surface used to fall through to VR. That is the wrong
    // direction to fail: a typo or a client from the future silently became an
    // embodied body with goggles taken from its own payload. Absent is still
    // VR (legacy Unity bodies omit the field); present-but-unknown is refused.
    final declaredSurface = body['surface'] ?? body['mode'];
    final parsedSurface = _parseSurface(declaredSurface);
    if (declaredSurface != null && parsedSurface == null) {
      throw const FormatException('unknown_surface');
    }
    if (authoritativeSurface != null &&
        parsedSurface != null &&
        parsedSurface != authoritativeSurface) {
      throw const FormatException('surface_channel_mismatch');
    }
    final surface = authoritativeSurface ?? parsedSurface ?? KaiSurface.vr;

    if (allowedSurfaces != null && !allowedSurfaces.contains(surface)) {
      throw const FormatException('surface_not_permitted_on_this_transport');
    }
    final spatial = body['spatial'];
    final perception = spatial is Map
        ? Map<String, dynamic>.from(spatial)
        : const <String, dynamic>{};
    final utterance = (body['utterance'] ?? '').toString().trim();
    final lower = utterance.toLowerCase();
    final presenceEvent = body['isPresenceEvent'] == true ||
        lower.contains('shared space') ||
        lower.contains('approached you') ||
        lower.contains('greet them briefly');

    final context = switch (surface) {
      KaiSurface.desktop => KaiSurfaceContext.desktop.copyWith(
          deviceId: body['deviceId']?.toString(),
          sessionId: body['sessionId']?.toString(),
        ),
      KaiSurface.mobile => KaiSurfaceContext.mobile.copyWith(
          deviceId: body['deviceId']?.toString(),
          sessionId: body['sessionId']?.toString(),
        ),
      KaiSurface.messenger => KaiSurfaceContext.messenger.copyWith(
          deviceId: body['deviceId']?.toString(),
          sessionId: body['sessionId']?.toString(),
        ),
      KaiSurface.ar => KaiSurfaceContext.ar.copyWith(
          deviceId: body['deviceId']?.toString(),
          sessionId: body['sessionId']?.toString(),
          isPresenceEvent: presenceEvent,
          perception: perception,
        ),
      KaiSurface.vr => KaiSurfaceContext.vr(
          worldId: (body['worldId'] ?? 'vr_shack').toString(),
          deviceId: body['deviceId']?.toString(),
          sessionId: body['sessionId']?.toString(),
          goggles: body['gogglesOn'] == true ? KaiGoggles.on : KaiGoggles.off,
          isPresenceEvent: presenceEvent,
          perception: perception,
        ),
    };

    final parsedHandoff = KaiSurfaceHandoff.tryParse(body['handoff']);
    return KaiContinuityTurnRequest(
      personaId: (body['personaId'] ?? defaultPersona).toString(),
      correlationId: (body['correlationId'] ?? '').toString().trim(),
      utterance: utterance,
      surfaceContext: context,
      // An incoming handoff is meaningful only on its declared destination.
      handoff: parsedHandoff?.toSurface == surface ? parsedHandoff : null,
    );
  }
}

class KaiContinuityTurnResponse {
  const KaiContinuityTurnResponse({
    required this.correlationId,
    required this.reply,
    required this.presenceState,
    required this.gesture,
    required this.voiceAudioUri,
    required this.availableCapabilities,
    this.memoryCandidates = const [],
    this.handoff,
    this.error = '',
  });

  final String correlationId;
  final String reply;
  final String presenceState;
  final String gesture;
  final String voiceAudioUri;
  final List<String> availableCapabilities;
  final List<KaiMemoryCandidate> memoryCandidates;
  final KaiSurfaceHandoff? handoff;
  final String error;

  Map<String, Object?> toJson() => {
        'continuityVersion': KaiContinuityContract.version,
        'correlationId': correlationId,
        'reply': reply,
        'presenceState': presenceState,
        'gesture': gesture,
        'voiceAudioUri': voiceAudioUri,
        'availableCapabilities': availableCapabilities,
        'memoryCandidates':
            memoryCandidates.map((item) => item.toJson()).toList(),
        if (handoff != null) 'handoff': handoff!.toJson(),
        'error': error,
      };
}

List<String> availableCapabilitiesFor(KaiSurfaceContext context) {
  final manifest = KaiCapabilityBroker.forContext(context);
  final available = <KaiSurfaceCapability>{KaiSurfaceCapability.conversation};

  if (manifest.allowsTechnicalConversation) {
    available.add(KaiSurfaceCapability.technicalConversation);
  }
  if (manifest.allowsGeneralTools) {
    available.add(KaiSurfaceCapability.generalTools);
  }
  available.addAll(manifest.worldCapabilities);

  // Embodiment capabilities are body features, not tool permissions.
  for (final capability in context.profile.capabilities) {
    if (capability == KaiSurfaceCapability.spatialPerception ||
        capability == KaiSurfaceCapability.embodiedExpression) {
      available.add(capability);
    }
  }

  final names = available.map((item) => item.name).toList()..sort();
  return names;
}

KaiSurface? _parseSurface(Object? value) {
  final raw = value?.toString().trim().toLowerCase();
  for (final surface in KaiSurface.values) {
    if (surface.name == raw) return surface;
  }
  return null;
}
