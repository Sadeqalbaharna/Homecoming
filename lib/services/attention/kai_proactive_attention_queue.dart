// Production adapter between KaiProactiveService and the pure attention policy.
//
// This queue is intentionally in-process for Brief 007. It stops live nudges
// disappearing during contention/no-body periods, but does not claim restart
// durability. Durable commitments require a separate persistent scheduler.
library;

import '../core/kai_body_event.dart';
import '../core/kai_proactive_service.dart';
import 'kai_attention_engine.dart';

class KaiPendingProactiveAttention {
  KaiPendingProactiveAttention({
    required this.event,
    required this.nudge,
    this.notBefore,
  });

  final KaiAttentionEvent event;
  final KaiNudge nudge;
  DateTime? notBefore;
}

class KaiProactiveAttentionDispatch {
  const KaiProactiveAttentionDispatch({
    required this.pending,
    required this.decision,
  });

  final KaiPendingProactiveAttention pending;
  final KaiAttentionDecision decision;
}

class KaiProactiveAttentionQueue {
  KaiProactiveAttentionQueue({
    this.quietHours = const KaiQuietHours(
      startHour: 22,
      endHour: 8,
      utcOffset: Duration(hours: 3),
    ),
    this.deliveryBudget = 2,
    this.budgetRetryDelay = const Duration(minutes: 45),
    this.noBodyRetryDelay = const Duration(minutes: 1),
    this.failureRetryDelay = const Duration(minutes: 1),
    this.relevanceWindow = const Duration(hours: 2),
    KaiAttentionEngine engine = const KaiAttentionEngine(),
  }) : _engine = engine;

  final KaiQuietHours quietHours;
  final int deliveryBudget;
  final Duration budgetRetryDelay;
  final Duration noBodyRetryDelay;
  final Duration failureRetryDelay;
  final Duration relevanceWindow;
  final KaiAttentionEngine _engine;

  final List<KaiPendingProactiveAttention> _pending = [];
  final Set<String> _processedEventIds = {};
  int _sequence = 0;
  int _deliveriesUsed = 0;
  int? _budgetDay;

  List<KaiPendingProactiveAttention> get pending => List.unmodifiable(_pending);
  Set<String> get processedEventIds => Set.unmodifiable(_processedEventIds);
  int get deliveriesUsed => _deliveriesUsed;

  int _revision = 0;

  /// Bumped on every durable state change.
  ///
  /// The coordinator persists when this moves, rather than after every call.
  /// It exists because `evaluate()` can reset the Bahrain budget day and then
  /// return null with nothing due — a real mutation on a path that returned
  /// early, so Brief 008 never wrote it. Restarting after midnight restored
  /// yesterday's exhausted budget.
  ///
  /// A plain counter and not a hash: it only has to answer "did anything
  /// change since you last looked", and it must never be expensive enough to
  /// discourage checking on a 20-second timer.
  int get revision => _revision;

  KaiPendingProactiveAttention enqueue(
    KaiNudge nudge, {
    required DateTime receivedAt,
    DateTime? occurredAt,
    String? eventId,
  }) {
    final receivedUtc = receivedAt.toUtc();
    final topicId = nudge.topicId?.trim();
    final id = eventId ??
        (topicId != null && topicId.isNotEmpty
            ? 'proactive-topic:$topicId'
            : 'proactive-${receivedUtc.microsecondsSinceEpoch}-${_sequence++}');
    if (topicId != null &&
        topicId.isNotEmpty &&
        _processedEventIds.any((processed) =>
            processed == id ||
            (processed.startsWith('proactive-topic:') &&
                processed.endsWith(':$topicId')))) {
      _rememberProcessed(id);
    }
    // The generator may rediscover the same unresolved subject while its first
    // delivery is still pending. Identity is the topic, not the model wording:
    // retain the original event instead of stacking another paraphrase.
    final existing = _find(id) ??
        (topicId == null || topicId.isEmpty ? null : _findTopic(topicId));
    if (existing != null) return existing;
    final pending = KaiPendingProactiveAttention(
      event: KaiAttentionEvent(
        eventId: id,
        correlationId: id,
        kind: KaiAttentionKind.proactiveNudge,
        receivedAt: receivedUtc,
        occurredAt: (occurredAt ?? receivedAt).toUtc(),
        expiresAt: receivedUtc.add(relevanceWindow),
      ),
      nudge: nudge,
    );
    _pending.add(pending);
    _revision++;
    return pending;
  }

  KaiProactiveAttentionDispatch? evaluate({
    required DateTime now,
    required List<KaiBodyRouteCandidate> candidates,
  }) {
    final nowUtc = now.toUtc();
    _resetBudgetIfNeeded(nowUtc);
    final due = _pending
        .where((item) =>
            item.notBefore == null || !nowUtc.isBefore(item.notBefore!))
        .toList();
    if (due.isEmpty) return null;

    final orderedEvents =
        KaiAttentionEngine.orderForAttention(due.map((item) => item.event));
    final selectedEvent = orderedEvents.first;
    final selected = due.firstWhere(
      (item) => item.event.eventId == selectedEvent.eventId,
    );
    final decision = _engine.decide(
      event: selected.event,
      context: KaiAttentionContext(
        now: nowUtc,
        candidates: candidates,
        quietHours: quietHours,
        deliveriesUsed: _deliveriesUsed,
        deliveryBudget: deliveryBudget,
        budgetRetryDelay: budgetRetryDelay,
        processedEventIds: _processedEventIds,
      ),
    );

    switch (decision.outcome) {
      case KaiAttentionOutcome.deferUntil:
        selected.notBefore = decision.notBefore;
        _revision++;
        break;
      case KaiAttentionOutcome.discardDuplicate:
      case KaiAttentionOutcome.discardExpired:
        _pending.remove(selected);
        _rememberProcessed(selected.event.eventId);
        _revision++;
        break;
      case KaiAttentionOutcome.deliverNow:
        break;
      case KaiAttentionOutcome.storeForLater:
        // Presence can wake this drain every few seconds. Without a retry
        // instant the same bodyless thought is reconsidered and journalled on
        // every lease refresh, creating thousands of identical decisions.
        // Keep the thought owed, but make the retry bounded and durable.
        selected.notBefore = nowUtc.add(noBodyRetryDelay);
        _revision++;
        break;
    }
    return KaiProactiveAttentionDispatch(
      pending: selected,
      decision: decision,
    );
  }

  /// The delivery path finished, even if Kai deliberately produced no sentence.
  void complete(String eventId, {required DateTime now}) {
    final removed = _remove(eventId);
    if (removed == null) return;
    _resetBudgetIfNeeded(now.toUtc());
    _deliveriesUsed++;
    _rememberProcessed(eventId);
    _revision++;
  }

  /// The delivery path threw before it could finish. Keep the event relevant.
  void fail(String eventId, {required DateTime now}) {
    final item = _find(eventId);
    if (item == null) return;
    item.notBefore = now.toUtc().add(failureRetryDelay);
    _revision++;
  }

  /// Re-check the non-negotiable sleep boundary after model generation but
  /// before any transcript or body write. A call that began at 21:59 can finish
  /// after 22:00; the earlier admission decision cannot authorize that later
  /// delivery.
  bool deferForQuietHours(String eventId, {required DateTime now}) {
    final nowUtc = now.toUtc();
    if (!quietHours.contains(nowUtc)) return false;
    final item = _find(eventId);
    if (item == null) return false;
    item.notBefore = quietHours.endsAfter(nowUtc);
    _revision++;
    return true;
  }

  KaiPendingProactiveAttention? _find(String eventId) {
    for (final item in _pending) {
      if (item.event.eventId == eventId) return item;
    }
    return null;
  }

  KaiPendingProactiveAttention? _findTopic(String topicId) {
    for (final item in _pending) {
      if (item.nudge.topicId?.trim() == topicId) return item;
    }
    return null;
  }

  KaiPendingProactiveAttention? _remove(String eventId) {
    final item = _find(eventId);
    if (item != null) _pending.remove(item);
    return item;
  }

  void _resetBudgetIfNeeded(DateTime nowUtc) {
    final wall = nowUtc.add(quietHours.utcOffset);
    final day = wall.year * 10000 + wall.month * 100 + wall.day;
    if (_budgetDay == day) return;
    _budgetDay = day;
    _deliveriesUsed = 0;
    _revision++;
  }

  void _rememberProcessed(String eventId) {
    _processedEventIds.add(eventId);
    while (_processedEventIds.length > 512) {
      _processedEventIds.remove(_processedEventIds.first);
    }
  }

  // ── Durability ─────────────────────────────────────────────────────────────
  //
  // Snapshot/restore live HERE and not in the engine, which stays pure. The
  // queue already owns the mutable state; serializing it is the queue's job.
  //
  // Only what resumption actually requires is written. The seed is included
  // because without it a restored nudge has nothing to say — that is explicitly
  // permitted, and it is also the ONLY conversational text here. No generated
  // reply, no transcript, no memory payload, no credential.

  static const snapshotVersion = 1;

  Map<String, dynamic> snapshot() => {
        'version': snapshotVersion,
        'pending': [
          for (final item in _pending)
            {
              'eventId': item.event.eventId,
              'correlationId': item.event.correlationId,
              'receivedAt': item.event.receivedAt.toIso8601String(),
              'occurredAt': item.event.occurredAt.toIso8601String(),
              if (item.event.expiresAt != null)
                'expiresAt': item.event.expiresAt!.toIso8601String(),
              if (item.notBefore != null)
                'notBefore': item.notBefore!.toIso8601String(),
              'seed': item.nudge.seed,
              'wantsHands': item.nudge.wantsHands,
              'nudgeKind': item.nudge.kind.name,
              if (item.nudge.topicId != null) 'topicId': item.nudge.topicId,
            },
        ],
        'processedEventIds': _processedEventIds.toList(),
        'deliveriesUsed': _deliveriesUsed,
        'budgetDay': _budgetDay,
        // Restored so a resumed process cannot mint an id that collides with
        // one already in flight from before the restart.
        'sequence': _sequence,
      };

  /// Rebuild from a snapshot. Replaces state; call on a fresh queue.
  ///
  /// A malformed individual record is SKIPPED rather than thrown, because the
  /// alternative is a coordinator that will not start. One unreadable row must
  /// not cost Kai every other thing he was waiting to say.
  void restore(Map<dynamic, dynamic> raw) {
    _pending.clear();
    _processedEventIds.clear();
    _deliveriesUsed = 0;
    _budgetDay = null;
    _sequence = 0;

    // An unknown version is not guessed at. A future schema read by an older
    // build would otherwise resume half-understood state.
    final version = raw['version'];
    if (version is! int || version != snapshotVersion) return;

    final pending = raw['pending'];
    if (pending is List) {
      for (final entry in pending) {
        final item = _restoreOne(entry);
        if (item != null) _pending.add(item);
      }
    }

    final processed = raw['processedEventIds'];
    if (processed is List) {
      for (final id in processed) {
        if (id is String && id.isNotEmpty) _processedEventIds.add(id);
      }
    }

    final used = raw['deliveriesUsed'];
    if (used is int && used >= 0) _deliveriesUsed = used;

    final day = raw['budgetDay'];
    if (day is int) _budgetDay = day;

    final sequence = raw['sequence'];
    if (sequence is int && sequence >= 0) _sequence = sequence;
  }

  static KaiPendingProactiveAttention? _restoreOne(Object? entry) {
    if (entry is! Map) return null;
    try {
      final eventId = entry['eventId']?.toString() ?? '';
      final seed = entry['seed']?.toString() ?? '';
      if (eventId.isEmpty || seed.isEmpty) return null;

      final receivedAt =
          DateTime.tryParse(entry['receivedAt']?.toString() ?? '');
      if (receivedAt == null) return null;
      final occurredAt =
          DateTime.tryParse(entry['occurredAt']?.toString() ?? '') ??
              receivedAt;

      return KaiPendingProactiveAttention(
        event: KaiAttentionEvent(
          eventId: eventId,
          correlationId: entry['correlationId']?.toString() ?? eventId,
          kind: KaiAttentionKind.proactiveNudge,
          // Original Core receipt time, carried through untouched. Restart must
          // not reorder the stream or refresh relevance.
          receivedAt: receivedAt.toUtc(),
          occurredAt: occurredAt.toUtc(),
          expiresAt:
              DateTime.tryParse(entry['expiresAt']?.toString() ?? '')?.toUtc(),
        ),
        nudge: KaiNudge(
          seed,
          wantsHands: entry['wantsHands'] == true,
          kind: KaiNudgeKind.values.firstWhere(
            (k) => k.name == entry['nudgeKind']?.toString(),
            orElse: () => KaiNudgeKind.companionship,
          ),
          topicId: entry['topicId']?.toString(),
        ),
        notBefore:
            DateTime.tryParse(entry['notBefore']?.toString() ?? '')?.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}
