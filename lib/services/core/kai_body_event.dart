/// Shared event and outbound-routing contracts for simultaneous embodiments.
///
/// This file is deliberately pure Dart. Transports authenticate a channel and
/// pass its authoritative surface into [KaiBodyEvent.receive]; payloads never
/// grant themselves a surface or capability set.
library;

class KaiBodyEvent {
  const KaiBodyEvent({
    required this.eventId,
    required this.type,
    required this.occurredAt,
    required this.receivedAt,
    required this.bodyId,
    required this.deviceId,
    required this.surface,
    required this.sessionId,
    required this.conversationId,
    required this.laneId,
    required this.correlationId,
    required this.payload,
    this.causationId,
  });

  final String eventId;
  final String type;
  final DateTime occurredAt;
  final DateTime receivedAt;
  final String bodyId;
  final String deviceId;
  final String surface;
  final String sessionId;
  final String conversationId;
  final String laneId;
  final String correlationId;
  final String? causationId;
  final Map<String, Object?> payload;

  /// Builds a trusted envelope from an authenticated channel plus untrusted
  /// body data. Device time is display-only; Core time orders the event stream.
  static KaiBodyEvent receive(
    Map<String, Object?> value, {
    required String authoritativeSurface,
    required DateTime receivedAt,
  }) {
    String requiredText(String key) {
      final text = value[key]?.toString().trim() ?? '';
      if (text.isEmpty) throw FormatException('body_event_${key}_required');
      return text;
    }

    final occurred = DateTime.tryParse(value['occurredAt']?.toString() ?? '');
    final rawPayload = value['payload'];
    return KaiBodyEvent(
      eventId: requiredText('eventId'),
      type: requiredText('type'),
      occurredAt: (occurred ?? receivedAt).toUtc(),
      receivedAt: receivedAt.toUtc(),
      bodyId: requiredText('bodyId'),
      deviceId: requiredText('deviceId'),
      surface: authoritativeSurface,
      sessionId: requiredText('sessionId'),
      conversationId: requiredText('conversationId'),
      laneId: requiredText('laneId'),
      correlationId: requiredText('correlationId'),
      causationId: value['causationId']?.toString().trim().isEmpty ?? true
          ? null
          : value['causationId']!.toString().trim(),
      payload: rawPayload is Map
          ? Map<String, Object?>.from(rawPayload)
          : const <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() => {
        'eventId': eventId,
        'type': type,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'receivedAt': receivedAt.toUtc().toIso8601String(),
        'bodyId': bodyId,
        'deviceId': deviceId,
        'surface': surface,
        'sessionId': sessionId,
        'conversationId': conversationId,
        'laneId': laneId,
        'correlationId': correlationId,
        if (causationId != null) 'causationId': causationId,
        'payload': payload,
      };
}

enum KaiOutboundKind { directReply, proactiveFriend, completedWork }

class KaiBodyRouteCandidate {
  const KaiBodyRouteCandidate({
    required this.bodyId,
    required this.surface,
    required this.lastUserActivityAt,
    this.connected = true,
    this.foreground = false,
    this.allowsFriendConversation = true,
    this.allowsWorkResults = false,
  });

  final String bodyId;
  final String surface;
  final DateTime lastUserActivityAt;
  final bool connected;
  final bool foreground;
  final bool allowsFriendConversation;
  final bool allowsWorkResults;
}

class KaiOutboundRoute {
  const KaiOutboundRoute._({
    required this.bodyId,
    required this.storeForLater,
    required this.reason,
  });

  const KaiOutboundRoute.toBody(String bodyId, String reason)
      : this._(bodyId: bodyId, storeForLater: false, reason: reason);

  const KaiOutboundRoute.inbox(String reason)
      : this._(bodyId: null, storeForLater: true, reason: reason);

  final String? bodyId;
  final bool storeForLater;
  final String reason;
}

/// Reverse attention routing: one output chooses one body, never fan-out.
/// Direct replies are origin-bound. Proactive friendship follows recent human
/// attention. Work results prefer their origin, then another capable body.
KaiOutboundRoute routeKaiOutput({
  required KaiOutboundKind kind,
  required Iterable<KaiBodyRouteCandidate> candidates,
  String? originBodyId,
}) {
  final connected = candidates.where((body) => body.connected).toList();
  KaiBodyRouteCandidate? origin;
  if (originBodyId != null) {
    for (final body in connected) {
      if (body.bodyId == originBodyId) {
        origin = body;
        break;
      }
    }
  }

  if (kind == KaiOutboundKind.directReply) {
    return origin == null
        ? const KaiOutboundRoute.inbox('origin_body_unavailable')
        : KaiOutboundRoute.toBody(origin.bodyId, 'origin_bound_reply');
  }
  if (kind == KaiOutboundKind.completedWork && origin != null) {
    return KaiOutboundRoute.toBody(origin.bodyId, 'origin_work_result');
  }

  final eligible = connected.where((body) {
    return kind == KaiOutboundKind.proactiveFriend
        ? body.allowsFriendConversation
        : body.allowsWorkResults;
  }).toList()
    ..sort((a, b) {
      if (a.foreground != b.foreground) return a.foreground ? -1 : 1;
      return b.lastUserActivityAt.compareTo(a.lastUserActivityAt);
    });
  if (eligible.isEmpty) {
    return const KaiOutboundRoute.inbox('no_suitable_body_online');
  }
  return KaiOutboundRoute.toBody(
    eligible.first.bodyId,
    kind == KaiOutboundKind.proactiveFriend
        ? 'most_relevant_friend_body'
        : 'most_relevant_work_body',
  );
}
