// Durable cross-device turns for the Central Kai conversation worker.
//
// Firebase is transport and recovery; KaiCore is scheduling authority. A body
// submits one request here, the desktop coordinator mirrors/claims it in the
// KaiCore conversation lane, and the resulting AI turn is saved once through
// ConversationStoreService before this record is marked done.
library;

import 'dart:async';

import 'kai_db.dart';
import 'kai_global_presence_service.dart';

enum KaiConversationRequestStatus {
  queued,
  running,
  done,
  failed,
  cancelled;

  static KaiConversationRequestStatus parse(Object? value) {
    final text = value?.toString();
    return values.firstWhere(
      (item) => item.name == text,
      orElse: () => queued,
    );
  }
}

class KaiConversationRequest {
  const KaiConversationRequest({
    required this.id,
    required this.text,
    required this.status,
    required this.sourceSurface,
    required this.conversationId,
    required this.deviceId,
    required this.model,
    required this.replyCeiling,
    required this.createdAt,
    required this.updatedAt,
    this.claimedBy,
    this.runtimeTaskId,
    this.reply,
    this.error,
    this.startedAt,
    this.completedAt,
    this.acknowledgedAt,
    this.claimExpiresAt,
    this.attemptCount = 0,
  });

  final String id;
  final String text;
  final KaiConversationRequestStatus status;
  final String sourceSurface;
  final String conversationId;
  final String deviceId;
  final String model;
  final int replyCeiling;
  final int createdAt;
  final int updatedAt;
  final String? claimedBy;
  final String? runtimeTaskId;
  final String? reply;
  final String? error;
  final int? startedAt;
  final int? completedAt;
  final int? acknowledgedAt;
  final int? claimExpiresAt;
  final int attemptCount;

  bool get isOpen =>
      status == KaiConversationRequestStatus.queued ||
      status == KaiConversationRequestStatus.running;

  bool get isTerminal => !isOpen;

  bool get hasCanonicalRoute =>
      KaiConversationRequestService.canonicalConversationIdForSurface(
        sourceSurface,
      ) ==
      conversationId;

  factory KaiConversationRequest.fromMap(String id, Map<dynamic, dynamic> map) {
    return KaiConversationRequest(
      id: id,
      text: (map['text'] ?? '').toString(),
      status: KaiConversationRequestStatus.parse(map['status']),
      sourceSurface: (map['sourceSurface'] ?? 'messenger').toString(),
      conversationId: (map['conversationId'] ?? 'messenger').toString(),
      deviceId: (map['deviceId'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      replyCeiling: (map['replyCeiling'] as num?)?.toInt() ?? 120,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      claimedBy: map['claimedBy']?.toString(),
      runtimeTaskId: map['runtimeTaskId']?.toString(),
      reply: map['reply']?.toString(),
      error: map['error']?.toString(),
      startedAt: (map['startedAt'] as num?)?.toInt(),
      completedAt: (map['completedAt'] as num?)?.toInt(),
      acknowledgedAt: (map['acknowledgedAt'] as num?)?.toInt(),
      claimExpiresAt: (map['claimExpiresAt'] as num?)?.toInt(),
      attemptCount: (map['attemptCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'status': status.name,
        'sourceSurface': sourceSurface,
        'conversationId': conversationId,
        'deviceId': deviceId,
        'model': model,
        'replyCeiling': replyCeiling,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (claimedBy != null) 'claimedBy': claimedBy,
        if (runtimeTaskId != null) 'runtimeTaskId': runtimeTaskId,
        if (reply != null) 'reply': reply,
        if (error != null) 'error': error,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (acknowledgedAt != null) 'acknowledgedAt': acknowledgedAt,
        if (claimExpiresAt != null) 'claimExpiresAt': claimExpiresAt,
        'attemptCount': attemptCount,
      };
}

class KaiConversationRequestService {
  static final KaiConversationRequestService instance =
      KaiConversationRequestService._();
  KaiConversationRequestService._();

  /// Central conversation gateways own their transcript room. The body may
  /// identify its surface, but it may not choose an arbitrary conversation
  /// partition and thereby write one body's raw transcript into another room.
  static String? canonicalConversationIdForSurface(String sourceSurface) {
    return switch (sourceSurface) {
      'messenger' => 'messenger',
      _ => null,
    };
  }

  String _path(String personaId, [String? requestId]) =>
      'kai_core/conversation_requests/$personaId${requestId == null ? '' : '/$requestId'}';

  KaiRef _root(String personaId) => KaiDb.instance.ref(_path(personaId));
  KaiRef _request(String personaId, String requestId) =>
      KaiDb.instance.ref(_path(personaId, requestId));

  Future<String> createRequest(
    String personaId, {
    required String text,
    required String model,
    String sourceSurface = 'messenger',
    int replyCeiling = 120,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Message cannot be empty');
    }
    final conversationId = canonicalConversationIdForSurface(sourceSurface);
    if (conversationId == null) {
      throw ArgumentError.value(
        sourceSurface,
        'sourceSurface',
        'This surface has no central conversation gateway',
      );
    }
    final presence = KaiGlobalPresenceService.instance;
    final deviceId = presence.deviceId?.trim() ?? '';
    if (deviceId.isEmpty || presence.surface != sourceSurface) {
      throw StateError('This Messenger body has no verified identity');
    }
    if (!await presence.isCurrentDeviceEnrolled) {
      throw StateError('This Messenger body is not paired with Central Kai');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _root(personaId).push();
    final id = ref.key ?? 'conversation_$now';
    await ref.set(KaiConversationRequest(
      id: id,
      text: clean,
      status: KaiConversationRequestStatus.queued,
      sourceSurface: sourceSurface,
      conversationId: conversationId,
      deviceId: deviceId,
      model: model,
      replyCeiling: replyCeiling.clamp(32, 600),
      createdAt: now,
      updatedAt: now,
    ).toMap());
    return id;
  }

  Stream<List<KaiConversationRequest>> watchOpenRequests(String personaId) {
    return _root(personaId).onValue.map((event) {
      return parseOpenRequests(event.snapshot.value);
    });
  }

  Stream<KaiConversationRequest?> watchRequest(
    String personaId,
    String requestId,
  ) {
    return _request(personaId, requestId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return KaiConversationRequest.fromMap(requestId, value);
    });
  }

  Future<KaiConversationRequest?> waitForTerminal(
    String personaId,
    String requestId, {
    Duration timeout = const Duration(seconds: 75),
  }) async {
    try {
      return await watchRequest(personaId, requestId)
          .where((request) => request?.isTerminal == true)
          .cast<KaiConversationRequest>()
          .first
          .timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  /// Returns as soon as Central Kai has visibly accepted the turn, or if it
  /// completes so quickly that the running state is never observed.
  Future<KaiConversationRequest?> waitForAcknowledgedOrTerminal(
    String personaId,
    String requestId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await watchRequest(personaId, requestId)
          .where((request) =>
              request != null &&
              (request.isTerminal || request.acknowledgedAt != null))
          .cast<KaiConversationRequest>()
          .first
          .timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  Future<KaiConversationRequest?> claimRequest(
    String personaId,
    String requestId, {
    required String workerId,
    required String runtimeTaskId,
    Duration lease = const Duration(minutes: 2),
    DateTime? nowUtc,
  }) async {
    final ref = _request(personaId, requestId);
    final snapshot = await ref.get();
    final value = snapshot.value;
    if (value is! Map) return null;
    final current = KaiConversationRequest.fromMap(requestId, value);
    final now = (nowUtc ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    if (current.status == KaiConversationRequestStatus.running &&
        current.claimedBy == workerId &&
        !_claimExpired(current, now)) {
      final expiresAt = now + lease.inMilliseconds;
      // The worker ID names the durable coordinator role, not one OS process.
      // After watchdog recovery that role resumes its own live claim and points
      // it at the new Core runtime task without waiting for lease expiry.
      await ref.update({
        'runtimeTaskId': runtimeTaskId,
        'claimExpiresAt': expiresAt,
        'updatedAt': now,
      });
      return KaiConversationRequest.fromMap(requestId, {
        ...Map<dynamic, dynamic>.from(value),
        'runtimeTaskId': runtimeTaskId,
        'claimExpiresAt': expiresAt,
        'updatedAt': now,
      });
    }
    if (current.status != KaiConversationRequestStatus.queued &&
        !(current.status == KaiConversationRequestStatus.running &&
            _claimExpired(current, now))) {
      return null;
    }
    final expiresAt = now + lease.inMilliseconds;
    await ref.update({
      'status': KaiConversationRequestStatus.running.name,
      'claimedBy': workerId,
      'runtimeTaskId': runtimeTaskId,
      'startedAt': now,
      'acknowledgedAt': current.acknowledgedAt ?? now,
      'claimExpiresAt': expiresAt,
      'attemptCount': current.attemptCount + 1,
      'updatedAt': now,
    });
    return KaiConversationRequest.fromMap(requestId, {
      ...Map<dynamic, dynamic>.from(value),
      'status': KaiConversationRequestStatus.running.name,
      'claimedBy': workerId,
      'runtimeTaskId': runtimeTaskId,
      'startedAt': now,
      'acknowledgedAt': current.acknowledgedAt ?? now,
      'claimExpiresAt': expiresAt,
      'attemptCount': current.attemptCount + 1,
      'updatedAt': now,
    });
  }

  static bool _claimExpired(KaiConversationRequest request, int nowMillis) {
    final explicit = request.claimExpiresAt;
    if (explicit != null) return explicit <= nowMillis;
    // Migration fallback for records claimed before leases existed.
    return request.updatedAt + const Duration(minutes: 2).inMilliseconds <=
        nowMillis;
  }

  static bool claimExpiredForTesting(
    KaiConversationRequest request,
    DateTime nowUtc,
  ) =>
      _claimExpired(request, nowUtc.toUtc().millisecondsSinceEpoch);

  Future<void> renewClaim(
    String personaId,
    String requestId, {
    required String workerId,
    Duration lease = const Duration(minutes: 2),
  }) async {
    final snapshot = await _request(personaId, requestId).get();
    if (snapshot.value is! Map) return;
    final request = KaiConversationRequest.fromMap(
      requestId,
      snapshot.value as Map,
    );
    if (request.status != KaiConversationRequestStatus.running ||
        request.claimedBy != workerId) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'claimExpiresAt': now + lease.inMilliseconds,
      'updatedAt': now,
    });
  }

  Future<void> requeueRequest(
    String personaId,
    String requestId, {
    required String error,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'status': KaiConversationRequestStatus.queued.name,
      'lastError': error.trim(),
      'claimedBy': null,
      'runtimeTaskId': null,
      'claimExpiresAt': null,
      'updatedAt': now,
    });
  }

  Future<void> completeRequest(
    String personaId,
    String requestId, {
    required String reply,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'status': KaiConversationRequestStatus.done.name,
      'reply': reply.trim(),
      'completedAt': now,
      'claimExpiresAt': null,
      'updatedAt': now,
    });
  }

  Future<void> failRequest(
    String personaId,
    String requestId, {
    required String error,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'status': KaiConversationRequestStatus.failed.name,
      'error': error.trim(),
      'completedAt': now,
      'claimExpiresAt': null,
      'updatedAt': now,
    });
  }

  static List<KaiConversationRequest> parseOpenRequests(Object? value) {
    if (value is! Map) return const [];
    final requests = <KaiConversationRequest>[];
    value.forEach((key, raw) {
      if (raw is! Map) return;
      final request = KaiConversationRequest.fromMap(key.toString(), raw);
      if (request.isOpen && request.text.trim().isNotEmpty) {
        requests.add(request);
      }
    });
    requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return requests;
  }
}
