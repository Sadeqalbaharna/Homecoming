// The middle of the reminder path: due Core commitments → attention decision →
// atomic dispatch or durable deferral.
//
//     commitments(dueOnly: true)
//       → one durable work-audience KaiAttentionEvent per record
//       → KaiAttentionEngine.decide(...)
//       → deliverNow    : dispatchCommitment(id, exact bodyId)
//       → deferUntil    : deferCommitment(id, engine's exact notBefore)
//       → storeForLater : leave scheduled and due; retry by loop/presence
//
// Extracted from the coordinator rather than written inside it, so the decision
// path can be driven deterministically — quiet hours, absent bodies, retries —
// without a wall clock, a Firebase connection, or a running app.
//
// The one rule underneath all of it: this class never marks a promise handled.
// It can dispatch it, or move when it is next looked at. Anything else leaves
// it owed, because Core is the only thing allowed to close a commitment and it
// only does so when a real body acknowledges delivery.
library;

import 'dart:async';

import '../attention/kai_attention_engine.dart';
import 'kai_body_event.dart';
import 'kai_core_client.dart';
import 'kai_global_presence_service.dart';

/// The coordinator's quiet-hours policy for due reminders.
///
/// Matches the proactive queue's window (01:00–08:00 Bahrain) so Kai does not
/// keep one set of hours for friendly nudges and a different set for work.
/// Stated as UTC+3 with no DST, never derived from the host clock — a
/// coordinator on a machine set to the wrong zone must still respect Sadeq's
/// night.
const KaiQuietHours kKaiCoordinatorQuietHours = KaiQuietHours(
  startHour: 1,
  endHour: 8,
  utcOffset: Duration(hours: 3),
);

/// Surfaces that may show Sadeq a work reminder in v1.
///
/// Deliberately a set of one. Messenger is the friend lane, and AR/VR have no
/// accepted presentation for work content — a reminder about an invoice must
/// not surface to a guest in the tavern.
const Set<String> kKaiWorkReminderSurfaces = {'desktop'};

/// How the scheduler reports what it did, without saying what was promised.
typedef KaiSchedulerJournal = Future<void> Function(
  String event, {
  String severity,
  Map<String, Object?> details,
});

class KaiDueCommitmentScheduler {
  KaiDueCommitmentScheduler({
    required this.client,
    required this.presence,
    required this.now,
    this.engine = const KaiAttentionEngine(),
    this.quietHours = const KaiQuietHours.none(),
    this.noBodyRetry = const Duration(minutes: 5),
    this.conversationId = 'in_person',
    KaiSchedulerJournal? journal,
    bool Function()? isActive,
  })  : _journal = journal,
        _isActive = isActive ?? _alwaysActive {
    // Retries are policy, not accidents. A zero or negative delay would either
    // spin Core continuously or ask it to schedule something in the past, and
    // both would be invisible until they were expensive.
    if (noBodyRetry <= Duration.zero) {
      throw ArgumentError.value(
          noBodyRetry, 'noBodyRetry', 'must be a positive delay');
    }
  }

  final KaiCoreClient client;

  /// The current global presence snapshot. A function, not a value, so the
  /// scheduler always reads presence as it is at decision time.
  final KaiGlobalPresenceSnapshot Function() presence;

  final DateTime Function() now;
  final KaiAttentionEngine engine;
  final KaiQuietHours quietHours;

  /// Bounded retry policy for a promise that has nowhere to be shown.
  ///
  /// No longer written to Core — see the `storeForLater` branch — so in
  /// practice the retry cadence is the loop's tick. It remains the engine's
  /// required `budgetRetryDelay`, and remains validated as a positive policy
  /// input rather than an accidental delay.
  final Duration noBodyRetry;

  final String conversationId;
  final KaiSchedulerJournal? _journal;

  /// Is this drain still authorized to touch Core?
  ///
  /// Re-asked after every suspension point, not once at the top. A drain that
  /// began before shutdown is still sitting inside `await commitments(...)`
  /// when `stop()` returns, and when the socket finally answers it would
  /// happily dispatch a reminder for a coordinator that no longer exists —
  /// waking a body, writing a transcript, and closing a promise on behalf of a
  /// process that is gone.
  final bool Function() _isActive;

  static bool _alwaysActive() => true;

  /// This drain's own guard.
  ///
  /// Deliberately NOT the coordinator's `_busy` or `_proactiveBusy`. A due
  /// reminder needs no model call — its text was written when the promise was
  /// made — so making it queue behind conversation work would delay a
  /// time-critical thing for a reason that does not apply to it.
  bool _draining = false;
  bool get isDraining => _draining;

  /// Last decision journalled per commitment, so an unchanged outcome on a
  /// 20-second tick does not write a line every 20 seconds forever.
  final Map<String, String> _lastJournalled = {};

  /// Work-eligible desktop body IDs at the last drain, for presence wake.
  Set<String> _lastEligibleBodies = const {};

  /// One pass over everything Core says is due. Overlapping calls collapse.
  ///
  /// The SAME method serves every trigger — startup, the periodic tick, and an
  /// eligible desktop appearing. That is only possible because the no-body path
  /// no longer moves `nextEvaluationAt`: a promise waiting for a body is still
  /// listed as due, so a wake finds it with the ordinary query. A promise
  /// deferred for quiet hours is not listed, and must not be — the wake is not
  /// a way around the engine's decision.
  Future<void> drain() async {
    if (_draining) return;
    if (!_isActive()) return;
    _draining = true;
    try {
      final List<Map<String, dynamic>> due;
      try {
        due = await client.commitments(dueOnly: true);
      } catch (error) {
        if (!_isActive()) return;
        // Core unreachable or mid-restart. Everything stays owed there.
        await _record('due_commitment_list_failed',
            severity: 'warning', details: {'error': error.toString()});
        return;
      }

      // The first re-check, and the important one: shutdown almost always
      // lands here, because the list call is the long wait.
      if (!_isActive()) return;

      final snapshot = presence();
      final candidates = workCandidates(snapshot);
      _lastEligibleBodies = eligibleBodyIds(snapshot);

      final context = KaiAttentionContext(
        now: now().toUtc(),
        candidates: candidates,
        budgetRetryDelay: noBodyRetry,
        quietHours: quietHours,
        // No budget and no processed-id set: a promise is not paced against a
        // nudge quota, and it is not a duplicate just because it was seen on a
        // previous tick — Core, not this process, decides when it is done.
      );

      for (final record in due) {
        await _handle(record, context);
      }
    } finally {
      _draining = false;
    }
  }

  /// Wake immediately when a body that could show a reminder appears.
  ///
  /// Returns true when this snapshot introduced a newly eligible desktop body.
  /// Presence churn that changes nothing relevant — a messenger phone
  /// reconnecting, a lease renewing — must not create work.
  bool shouldWakeFor(KaiGlobalPresenceSnapshot snapshot) {
    final current = eligibleBodyIds(snapshot);
    final newcomers = current.difference(_lastEligibleBodies);
    _lastEligibleBodies = current;
    return newcomers.isNotEmpty;
  }

  /// Body IDs that may be handed a work reminder right now.
  static Set<String> eligibleBodyIds(KaiGlobalPresenceSnapshot snapshot) {
    if (!snapshot.connected) return const {};
    return snapshot.bodies
        .where(_isWorkEligible)
        .map((body) => body.bodyId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  static bool _isWorkEligible(KaiGlobalBody body) =>
      kKaiWorkReminderSurfaces.contains(body.surface);

  /// Presence → routing candidates, with work eligibility set explicitly.
  ///
  /// Every body is offered to the router, but only a desktop one is marked
  /// `allowsWorkResults`. That is what stops a phone or a headset being chosen
  /// for this content, and it is expressed as data for the accepted router
  /// rather than as an `if` in this class.
  static List<KaiBodyRouteCandidate> workCandidates(
    KaiGlobalPresenceSnapshot snapshot,
  ) {
    if (!snapshot.connected) return const [];
    final candidates = <KaiBodyRouteCandidate>[];
    for (final body in snapshot.bodies) {
      if (body.bodyId.trim().isEmpty || body.surface.trim().isEmpty) continue;
      candidates.add(KaiBodyRouteCandidate(
        bodyId: body.bodyId,
        surface: body.surface,
        // Presence already drops expired leases, so anything still here holds
        // a live one.
        connected: true,
        foreground: body.foreground,
        lastUserActivityAt: body.lastUserActivityAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        allowsWorkResults: _isWorkEligible(body),
        // Irrelevant for a work reminder, and left at the router's default so
        // this class is not quietly redefining the friend lane too.
      ));
    }
    return candidates;
  }

  Future<void> _handle(
    Map<String, dynamic> record,
    KaiAttentionContext context,
  ) async {
    // Re-asked per record. A drain over several promises awaits Core between
    // each one, so shutdown can land mid-list; the ones already handled stand,
    // and the rest simply stay owed for the next generation.
    if (!_isActive()) return;

    final commitmentId = record['commitmentId']?.toString().trim() ?? '';
    if (commitmentId.isEmpty) {
      await _record('due_commitment_malformed', severity: 'warning');
      return;
    }

    final KaiAttentionEvent event;
    try {
      event = buildEvent(record);
    } catch (error) {
      await _record('due_commitment_unreadable',
          severity: 'warning',
          details: {'commitmentId': commitmentId, 'error': error.toString()});
      return;
    }

    final decision = engine.decide(event: event, context: context);

    switch (decision.outcome) {
      case KaiAttentionOutcome.deliverNow:
        await _dispatch(commitmentId, decision);
      case KaiAttentionOutcome.deferUntil:
        // The engine's EXACT instant. Rounding or re-deriving it here would
        // mean quiet hours ended at a time nobody decided.
        await _defer(commitmentId, decision.notBefore, decision.reasonCode);
      case KaiAttentionOutcome.storeForLater:
        // NOTHING is written to Core. This is the Option C contract resolution.
        //
        // Pushing `nextEvaluationAt` forward here looked like the tidy thing to
        // do — record the retry durably. But Core refuses dispatch while that
        // instant is in the future (Brief 013) and refuses to move it earlier
        // (Brief 014), both deliberately. So the moment the no-body path wrote
        // a retry, the promise became undeliverable until it elapsed: Sadeq
        // sits down at his desk and the reminder keeps waiting out a timer that
        // exists precisely because he WASN'T there.
        //
        // Leaving the evaluation instant alone keeps the ledger honest — the
        // promise IS owed right now — so Core keeps listing it as due, dispatch
        // stays open, and an eligible desktop appearing delivers it
        // immediately. The bounded retry is the loop's own tick.
        //
        // Both Core protections are untouched, and quiet hours still persists
        // the engine's exact instant in the branch above.
        await _record('due_commitment_awaiting_body', details: {
          'commitmentId': commitmentId,
          'reasonCode': decision.reasonCode,
        });
      case KaiAttentionOutcome.discardDuplicate:
      case KaiAttentionOutcome.discardExpired:
        // A contradiction, not an instruction. An outstanding Core commitment
        // cannot be duplicate or expired — it is durable and expiry-free by
        // construction — so reaching here means the event was built wrong.
        // Discarding would silently drop a promise, so it stays owed and
        // visible instead, and the next drain tries again.
        await _record('due_commitment_undeliverable_outcome',
            severity: 'warning',
            details: {
              'commitmentId': commitmentId,
              'outcome': decision.outcome.name,
              'reasonCode': decision.reasonCode,
            });
    }
  }

  /// One Core record → one durable, expiry-free, work-audience event.
  ///
  /// Ordering comes from Core's persisted instants, never from this device's
  /// clock: the coordinator may have been asleep, restarted, or running on a
  /// machine whose time is wrong, and none of that should change the order in
  /// which promises are considered.
  static KaiAttentionEvent buildEvent(Map<String, dynamic> record) {
    final commitmentId = record['commitmentId']!.toString();
    final nextEvaluationAt =
        DateTime.parse(record['nextEvaluationAt'].toString()).toUtc();
    final dueAt = DateTime.parse(record['dueAt'].toString()).toUtc();

    return KaiAttentionEvent(
      // Derived from the commitment ID ALONE. Not the outbound id, not the
      // evaluation instant, not a counter — so the same promise is the same
      // event across retries, restarts, and deferrals.
      eventId: eventIdFor(commitmentId),
      correlationId: commitmentId,
      kind: KaiAttentionKind.dueCommitment,
      // Explicit and trusted. A dueCommitment refuses to be constructed
      // without one, precisely so nobody infers it from the reminder's words.
      audience: KaiAttentionAudience.work,
      receivedAt: nextEvaluationAt,
      occurredAt: dueAt,
      // No expiry, ever. A promise does not stop being owed because it is old.
      durableCommitment: true,
    );
  }

  static String eventIdFor(String commitmentId) => 'due:$commitmentId';

  /// The deterministic envelope id for one commitment's delivery.
  ///
  /// Stable across processes, so a retry after a crash asks Core for the same
  /// envelope and Core's idempotent dispatch returns the existing one rather
  /// than minting a second reminder.
  static String outboundIdFor(String commitmentId) => '$commitmentId-outbound';

  Future<void> _dispatch(
    String commitmentId,
    KaiAttentionDecision decision,
  ) async {
    final bodyId = decision.bodyId;
    if (bodyId == null || bodyId.trim().isEmpty) {
      await _record('due_commitment_route_without_body',
          severity: 'warning', details: {'commitmentId': commitmentId});
      return;
    }

    try {
      await client.dispatchCommitment(
        commitmentId,
        outboundId: outboundIdFor(commitmentId),
        // Byte-for-byte the global presence id the desktop polls with. Not
        // rebuilt, not normalised.
        targetBodyId: bodyId,
        conversationId: conversationId,
      );
      await _record('due_commitment_dispatched', details: {
        'commitmentId': commitmentId,
        'bodyId': bodyId,
        'reasonCode': decision.reasonCode,
      });
    } on KaiCoreException catch (error) {
      // Includes the benign races: another coordinator got there first, or the
      // promise was acknowledged between listing and dispatch. Core's state is
      // authoritative either way, so nothing local is corrected here.
      await _record('due_commitment_dispatch_refused',
          severity: 'warning',
          details: {
            'commitmentId': commitmentId,
            'status': error.statusCode,
            'reasonCode': error.message,
          });
    } catch (error) {
      await _record('due_commitment_dispatch_failed',
          severity: 'warning',
          details: {'commitmentId': commitmentId, 'error': error.toString()});
    }
  }

  Future<void> _defer(
    String commitmentId,
    DateTime? notBefore,
    String reasonCode,
  ) async {
    if (notBefore == null) {
      await _record('due_commitment_defer_without_instant',
          severity: 'warning',
          details: {'commitmentId': commitmentId, 'reasonCode': reasonCode});
      return;
    }
    final instant = notBefore.toUtc();

    try {
      await client.deferCommitment(commitmentId, nextEvaluationAt: instant);
      await _record('due_commitment_deferred', details: {
        'commitmentId': commitmentId,
        'reasonCode': reasonCode,
        'nextEvaluationAt': instant.toIso8601String(),
      });
    } on KaiCoreException catch (error) {
      // A regression means Core already holds a LATER instant than the one
      // being asked for — the promise is already waiting at least this long,
      // so there is nothing to correct and nothing lost.
      await _record('due_commitment_defer_refused',
          severity: 'warning',
          details: {
            'commitmentId': commitmentId,
            'status': error.statusCode,
            'reasonCode': error.message,
          });
    } catch (error) {
      await _record('due_commitment_defer_failed',
          severity: 'warning',
          details: {'commitmentId': commitmentId, 'error': error.toString()});
    }
  }

  /// Journal, suppressing an unchanged repeat for the same commitment.
  ///
  /// The drain runs on a timer. Without this, a promise waiting out eight hours
  /// of quiet hours would write the same line every tick — thousands of
  /// identical entries burying the transitions that actually matter. Any change
  /// of outcome, target, reason, or retry instant is still recorded.
  Future<void> _record(
    String event, {
    String severity = 'info',
    Map<String, Object?> details = const {},
  }) async {
    final journal = _journal;
    if (journal == null) return;

    final commitmentId = details['commitmentId']?.toString();
    if (commitmentId != null) {
      // Reminder TEXT is never part of this — only ids, outcomes and instants.
      final fingerprint = [
        event,
        details['bodyId'],
        details['reasonCode'],
        details['nextEvaluationAt'],
        details['status'],
      ].join('|');
      if (_lastJournalled[commitmentId] == fingerprint) return;
      _lastJournalled[commitmentId] = fingerprint;
    }

    await journal(event, severity: severity, details: details);
  }

  /// Forget suppression state, so the next decision is journalled afresh.
  void resetJournalSuppression() => _lastJournalled.clear();
}
