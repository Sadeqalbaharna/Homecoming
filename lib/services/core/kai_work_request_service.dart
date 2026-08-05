// KaiWorkRequestService — mobile-to-desktop work queue.
//
// This is the bridge between Kai's phone cockpit and desktop hands:
// mobile can create/observe a work request, desktop can claim it, append
// progress events, and close it with receipts. It deliberately uses KaiDb so
// mobile uses the Firebase plugin while desktop uses REST.
library;

import 'dart:async';

import 'kai_db.dart';

/// The lifecycle of a remote work request.
enum KaiWorkRequestStatus {
  queued,
  running,
  done,
  failed,
  cancelled;

  static KaiWorkRequestStatus parse(String? value) {
    return KaiWorkRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => KaiWorkRequestStatus.queued,
    );
  }
}

/// One event in a request transcript — the little stream Sadeq can watch from
/// mobile while desktop-Kai works in the engine room.
class KaiWorkRequestEvent {
  final String id;
  final String kind;
  final String text;
  final String? actor;
  final int createdAt;

  const KaiWorkRequestEvent({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.actor,
  });

  factory KaiWorkRequestEvent.fromMap(String id, Map<dynamic, dynamic> map) {
    return KaiWorkRequestEvent(
      id: id,
      kind: (map['kind'] ?? 'note').toString(),
      text: (map['text'] ?? '').toString(),
      actor: map['actor']?.toString(),
      createdAt: (map['createdAt'] is int) ? map['createdAt'] as int : 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'text': text,
        if (actor != null && actor!.isNotEmpty) 'actor': actor,
        'createdAt': createdAt,
      };
}

/// A durable request for Kai's desktop body to pick up.
class KaiWorkRequest {
  final String id;
  final String text;
  final KaiWorkRequestStatus status;
  final String createdFrom;
  final bool requiresDesktop;
  final String priority;
  final String? claimedBy;
  final String? summary;
  final String? error;
  final List<String> evidence;
  final int createdAt;
  final int updatedAt;
  final int? startedAt;
  final int? completedAt;

  const KaiWorkRequest({
    required this.id,
    required this.text,
    required this.status,
    required this.createdFrom,
    required this.requiresDesktop,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.claimedBy,
    this.summary,
    this.error,
    this.evidence = const [],
    this.startedAt,
    this.completedAt,
  });

  factory KaiWorkRequest.fromMap(String id, Map<dynamic, dynamic> map) {
    return KaiWorkRequest(
      id: id,
      text: (map['text'] ?? '').toString(),
      status: KaiWorkRequestStatus.parse(map['status']?.toString()),
      createdFrom: (map['createdFrom'] ?? 'unknown').toString(),
      requiresDesktop: map['requiresDesktop'] != false,
      priority: (map['priority'] ?? 'normal').toString(),
      claimedBy: map['claimedBy']?.toString(),
      summary: map['summary']?.toString(),
      error: map['error']?.toString(),
      evidence: (map['evidence'] is List)
          ? (map['evidence'] as List).map((e) => e.toString()).toList()
          : const [],
      createdAt: (map['createdAt'] is int) ? map['createdAt'] as int : 0,
      updatedAt: (map['updatedAt'] is int) ? map['updatedAt'] as int : 0,
      startedAt: (map['startedAt'] is int) ? map['startedAt'] as int : null,
      completedAt:
          (map['completedAt'] is int) ? map['completedAt'] as int : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'status': status.name,
        'createdFrom': createdFrom,
        'requiresDesktop': requiresDesktop,
        'priority': priority,
        if (claimedBy != null && claimedBy!.isNotEmpty) 'claimedBy': claimedBy,
        if (summary != null && summary!.isNotEmpty) 'summary': summary,
        if (error != null && error!.isNotEmpty) 'error': error,
        'evidence': evidence,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
      };

  bool get isOpen =>
      status == KaiWorkRequestStatus.queued ||
      status == KaiWorkRequestStatus.running;
}

/// Parses short mobile chat commands that should create a desktop work request
/// instead of being answered as ordinary conversation.
///
/// Examples:
///   queue for desktop: fix replay graph measurement
///   queue this for desktop: fix replay graph measurement
///   desktop task: fix replay graph measurement
class KaiWorkRequestCommand {
  static final _prefix = RegExp(
    r'^(?:queue(?:\s+this)?\s+for\s+desktop|desktop\s+task|desktop\s+job)\s*[:\-—]?\s*(.+)$',
    caseSensitive: false,
    dotAll: true,
  );

  static String? parse(String text) {
    final match = _prefix.firstMatch(text.trim());
    if (match == null) return null;
    final body = match.group(1)?.replaceFirst(RegExp(r'^[:\-—]\s*'), '').trim();
    if (body == null || body.isEmpty) return null;
    return body;
  }
}

class KaiWorkRequestService {
  static final KaiWorkRequestService instance = KaiWorkRequestService._();
  KaiWorkRequestService._();

  String _path(String personaId, [String? requestId]) =>
      'kai/$personaId/work_requests${requestId == null ? '' : '/$requestId'}';

  KaiRef _root(String personaId) => KaiDb.instance.ref(_path(personaId));
  KaiRef _request(String personaId, String requestId) =>
      KaiDb.instance.ref(_path(personaId, requestId));

  /// Create a request from mobile/chat. Returns the generated request id.
  Future<String> createRequest(
    String personaId, {
    required String text,
    String createdFrom = 'mobile',
    bool requiresDesktop = true,
    String priority = 'normal',
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Work request text cannot be empty');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final ref = _root(personaId).push();
    final id = ref.key ?? 'request_$now';
    await ref.set(KaiWorkRequest(
      id: id,
      text: cleanText,
      status: KaiWorkRequestStatus.queued,
      createdFrom: createdFrom,
      requiresDesktop: requiresDesktop,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    ).toMap());
    await appendEvent(
      personaId,
      id,
      kind: 'created',
      text: 'Queued for desktop body.',
      actor: createdFrom,
      at: now,
    );
    return id;
  }

  /// Live list for the mobile cockpit, newest first.
  Stream<List<KaiWorkRequest>> watchRequests(String personaId) {
    return _root(personaId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <KaiWorkRequest>[];
      final requests = <KaiWorkRequest>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          final request = KaiWorkRequest.fromMap(key.toString(), raw);
          if (request.text.trim().isNotEmpty) requests.add(request);
        }
      });
      requests.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return requests;
    });
  }

  Future<List<KaiWorkRequest>> fetchOpenRequests(String personaId) async {
    final snap = await _root(personaId).get();
    final value = snap.value;
    if (value is! Map) return const [];
    final requests = <KaiWorkRequest>[];
    value.forEach((key, raw) {
      if (raw is Map) {
        final request = KaiWorkRequest.fromMap(key.toString(), raw);
        if (request.isOpen && request.text.trim().isNotEmpty) {
          requests.add(request);
        }
      }
    });
    requests.sort((a, b) {
      final priority = _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
      if (priority != 0) return priority;
      return a.createdAt.compareTo(b.createdAt);
    });
    return requests;
  }

  /// Claim a queued request. Returns null if it is missing or already claimed.
  ///
  /// This is intentionally conservative; KaiDb has no transaction facade yet, so
  /// a future slice should add atomic compare-and-set before multiple desktop
  /// workers exist. For one desktop body, this is enough and honest.
  Future<KaiWorkRequest?> claimRequest(
    String personaId,
    String requestId, {
    String claimedBy = 'desktop',
  }) async {
    final ref = _request(personaId, requestId);
    final snap = await ref.get();
    final raw = snap.value;
    if (raw is! Map) return null;

    final current = KaiWorkRequest.fromMap(requestId, raw);
    if (current.status != KaiWorkRequestStatus.queued) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.update({
      'status': KaiWorkRequestStatus.running.name,
      'claimedBy': claimedBy,
      'startedAt': now,
      'updatedAt': now,
    });
    await appendEvent(
      personaId,
      requestId,
      kind: 'claimed',
      text: 'Desktop body picked this up.',
      actor: claimedBy,
      at: now,
    );

    return KaiWorkRequest.fromMap(requestId, {
      ...raw,
      'status': KaiWorkRequestStatus.running.name,
      'claimedBy': claimedBy,
      'startedAt': now,
      'updatedAt': now,
    });
  }

  Stream<List<KaiWorkRequestEvent>> watchEvents(
    String personaId,
    String requestId,
  ) {
    return _request(personaId, requestId).child('events').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <KaiWorkRequestEvent>[];
      final events = <KaiWorkRequestEvent>[];
      value.forEach((key, raw) {
        if (raw is Map) {
          final item = KaiWorkRequestEvent.fromMap(key.toString(), raw);
          if (item.text.trim().isNotEmpty) events.add(item);
        }
      });
      events.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return events;
    });
  }

  Future<void> appendEvent(
    String personaId,
    String requestId, {
    required String kind,
    required String text,
    String? actor,
    int? at,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    final now = at ?? DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).child('events').push().set(
          KaiWorkRequestEvent(
            id: '',
            kind: kind.trim().isEmpty ? 'note' : kind.trim(),
            text: cleanText,
            actor: actor,
            createdAt: now,
          ).toMap(),
        );
    await _request(personaId, requestId).update({'updatedAt': now});
  }

  Future<void> completeRequest(
    String personaId,
    String requestId, {
    required String summary,
    List<String> evidence = const [],
    String actor = 'desktop',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'status': KaiWorkRequestStatus.done.name,
      'summary': summary.trim(),
      'evidence': evidence.where((e) => e.trim().isNotEmpty).toList(),
      'completedAt': now,
      'updatedAt': now,
    });
    await appendEvent(
      personaId,
      requestId,
      kind: 'done',
      text: summary.trim().isEmpty ? 'Completed.' : summary.trim(),
      actor: actor,
      at: now,
    );
  }

  Future<void> failRequest(
    String personaId,
    String requestId, {
    required String error,
    String actor = 'desktop',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanError = error.trim();
    await _request(personaId, requestId).update({
      'status': KaiWorkRequestStatus.failed.name,
      'error': cleanError,
      'completedAt': now,
      'updatedAt': now,
    });
    await appendEvent(
      personaId,
      requestId,
      kind: 'failed',
      text: cleanError.isEmpty ? 'Failed.' : cleanError,
      actor: actor,
      at: now,
    );
  }

  Future<void> cancelRequest(
    String personaId,
    String requestId, {
    String actor = 'mobile',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _request(personaId, requestId).update({
      'status': KaiWorkRequestStatus.cancelled.name,
      'completedAt': now,
      'updatedAt': now,
    });
    await appendEvent(
      personaId,
      requestId,
      kind: 'cancelled',
      text: 'Cancelled.',
      actor: actor,
      at: now,
    );
  }

  static int _priorityRank(String priority) {
    return switch (priority.trim().toLowerCase()) {
      'urgent' => 3,
      'high' => 2,
      'normal' => 1,
      'low' => 0,
      _ => 1,
    };
  }
}
