/// Value objects for the Central Attention decision.
///
/// Pure Dart on purpose: no clock, no I/O, no Firebase, no model calls, no
/// singletons. Everything that changes is passed in, so a decision is a
/// function of its inputs and can be replayed exactly from an audit record.
///
/// This domain decides ONLY whether an event should be delivered, deferred, or
/// dropped, and to which single body. It does not deliver, does not generate
/// language, and does not touch memory.
library;

import '../core/kai_body_event.dart';

/// WHO a due commitment is for, as trusted typed policy.
///
/// Kind alone cannot answer this. A promise can be a friendly one ("remind me
/// it's her birthday") or a working one ("remind me the cert expires"), and the
/// two belong on different bodies. Brief 012's reminders are [work].
///
/// This is never read from reminder text, tool arguments, or an event payload.
/// A model that could name its own audience could route its way onto Messenger,
/// which is friend-only — so audience is supplied by the construction site and
/// validated, and a [KaiAttentionKind.dueCommitment] without one fails to build
/// rather than quietly defaulting to a friend surface.
enum KaiAttentionAudience { friend, work }

/// What kind of output is asking for Sadeq's attention.
///
/// Kept small and explicit. This is a policy, not a general agent framework —
/// there is no adaptive scoring and no personality heuristic here.
enum KaiAttentionKind {
  /// Kai reaching out unprompted. The only kind the budget and quiet hours
  /// exist to pace.
  proactiveNudge,

  /// An answer to something Sadeq said. Origin-bound, and never proactive.
  directReply,

  /// The result of work he asked for. Goes only to a body allowed work results.
  completedWork,

  /// Something Kai promised. Durable by nature: may be deferred or held, never
  /// silently dropped.
  dueCommitment,
}

enum KaiAttentionOutcome {
  deliverNow,
  deferUntil,
  discardDuplicate,
  discardExpired,

  /// Nothing suitable is online. The event stays owed.
  storeForLater,
}

/// Quiet-hours window expressed in Sadeq's wall clock.
///
/// [utcOffset] is trusted policy for the instant being evaluated. Keeping it
/// explicit makes the same decision replayable on a Bahrain laptop, a UTC
/// server, or a future failover host without depending on the host timezone.
class KaiQuietHours {
  const KaiQuietHours({
    required this.startHour,
    required this.endHour,
    this.utcOffset = Duration.zero,
  })  : assert(startHour >= 0 && startHour < 24),
        assert(endHour >= 0 && endHour < 24);

  /// No quiet window — used by surfaces or tests that do not pace.
  const KaiQuietHours.none()
      : startHour = -1,
        endHour = -1,
        utcOffset = Duration.zero;

  final int startHour;
  final int endHour;
  final Duration utcOffset;

  bool get isEnabled => startHour >= 0 && endHour >= 0;

  bool contains(DateTime now) {
    if (!isEnabled) return false;
    final hour = now.toUtc().add(utcOffset).hour;
    // A window that wraps midnight (22 → 07) is inside when EITHER side holds.
    return startHour > endHour
        ? hour >= startHour || hour < endHour
        : hour >= startHour && hour < endHour;
  }

  /// Returns the next end of this wall-clock window as a UTC instant.
  DateTime endsAfter(DateTime now) {
    final wallNow = now.toUtc().add(utcOffset);
    var wallEnd = DateTime.utc(
      wallNow.year,
      wallNow.month,
      wallNow.day,
      endHour,
    );
    if (!wallNow.isBefore(wallEnd)) {
      wallEnd = wallEnd.add(const Duration(days: 1));
    }
    return wallEnd.subtract(utcOffset).toUtc();
  }
}

/// One thing asking to be delivered.
///
/// [occurredAt] is the body's own clock and is DESCRIPTIVE ONLY. [receivedAt]
/// is Core receipt time and is what orders anything.
///
/// [payload] is untrusted body data. The engine never reads it — see
/// [KaiAttentionContext.urgentOverrideAuthorized].
class KaiAttentionEvent {
  factory KaiAttentionEvent({
    required String eventId,
    required String correlationId,
    required KaiAttentionKind kind,
    required DateTime receivedAt,
    required DateTime occurredAt,
    DateTime? expiresAt,
    String? originBodyId,
    int priority = 5,
    bool durableCommitment = false,
    KaiAttentionAudience? audience,
    Map<String, Object?> payload = const {},
  }) {
    if (priority < minPriority || priority > maxPriority) {
      throw RangeError.range(priority, minPriority, maxPriority, 'priority');
    }

    // A due commitment must SAY who it is for. Falling through to the friend
    // path is how a working reminder would end up on Messenger, which is
    // friend-only — so this fails construction rather than defaulting.
    if (kind == KaiAttentionKind.dueCommitment && audience == null) {
      throw ArgumentError.value(
        audience,
        'audience',
        'a dueCommitment must declare friend or work explicitly',
      );
    }

    // A direct reply is routed by its authoritative origin and nothing else.
    // Accepting an audience here would offer a second, weaker route to a body
    // that answered nobody — so supplying one is an error, not a hint.
    if (kind == KaiAttentionKind.directReply && audience != null) {
      throw ArgumentError.value(
        audience,
        'audience',
        'a directReply is origin-bound; audience is prohibited',
      );
    }

    // Every other kind already implies its audience, and a conflicting one is a
    // caller error rather than something to silently prefer.
    final implied = switch (kind) {
      KaiAttentionKind.proactiveNudge => KaiAttentionAudience.friend,
      KaiAttentionKind.completedWork => KaiAttentionAudience.work,
      KaiAttentionKind.directReply => null,
      KaiAttentionKind.dueCommitment => audience,
    };
    if (kind != KaiAttentionKind.dueCommitment &&
        audience != null &&
        implied != null &&
        audience != implied) {
      throw ArgumentError.value(
        audience,
        'audience',
        'incompatible with ${kind.name}, which is always ${implied.name}',
      );
    }

    return KaiAttentionEvent._(
      eventId: eventId,
      correlationId: correlationId,
      kind: kind,
      receivedAt: receivedAt,
      occurredAt: occurredAt,
      expiresAt: expiresAt,
      originBodyId: originBodyId,
      priority: priority,
      durableCommitment: durableCommitment,
      audience: audience ?? implied,
      payload: payload,
    );
  }

  const KaiAttentionEvent._({
    required this.eventId,
    required this.correlationId,
    required this.kind,
    required this.receivedAt,
    required this.occurredAt,
    required this.expiresAt,
    required this.originBodyId,
    required this.priority,
    required this.durableCommitment,
    required this.audience,
    required this.payload,
  });

  final String eventId;
  final String correlationId;
  final KaiAttentionKind kind;

  /// Core receipt time. Authoritative for ordering.
  final DateTime receivedAt;

  /// Device time. Never used for ordering or for any decision.
  final DateTime occurredAt;

  final DateTime? expiresAt;
  final String? originBodyId;

  /// Explicit, validated, and supplied by trusted policy.
  final int priority;

  /// True when Kai owes this. Durable events survive expiry, quiet hours,
  /// budget exhaustion and an empty body list.
  final bool durableCommitment;

  final Map<String, Object?> payload;

  /// Lowest attention priority. Nothing sorts below this.
  static const int minPriority = 0;

  /// Highest attention priority. Note this grants NOTHING on its own — it
  /// affects the order things are considered in, never whether quiet hours or
  /// the budget apply. Only [KaiAttentionContext.urgentOverrideAuthorized]
  /// crosses quiet hours, and it comes from policy rather than from an event.
  static const int maxPriority = 10;

  bool get isDurable =>
      durableCommitment || kind == KaiAttentionKind.dueCommitment;

  /// Only ordinary proactive output is paced. A reply is owed, work was asked
  /// for, and a commitment was promised.
  bool get isPaceable => kind == KaiAttentionKind.proactiveNudge && !isDurable;

  /// Who this is for. Never null except for origin-bound direct replies.
  final KaiAttentionAudience? audience;

  KaiOutboundKind get outboundKind {
    switch (kind) {
      case KaiAttentionKind.directReply:
        return KaiOutboundKind.directReply;
      case KaiAttentionKind.completedWork:
        return KaiOutboundKind.completedWork;
      case KaiAttentionKind.dueCommitment:
        // Declared audience decides, never the kind. `work` maps onto the
        // existing work-eligible routing path — which requires
        // allowsWorkResults, so a friend-only body such as Messenger is not a
        // candidate at all rather than being filtered out later.
        return audience == KaiAttentionAudience.work
            ? KaiOutboundKind.completedWork
            : KaiOutboundKind.proactiveFriend;
      case KaiAttentionKind.proactiveNudge:
        return KaiOutboundKind.proactiveFriend;
    }
  }
}

/// Everything changeable, supplied by the caller so the engine stays pure.
class KaiAttentionContext {
  factory KaiAttentionContext({
    required DateTime now,
    required List<KaiBodyRouteCandidate> candidates,
    required Duration budgetRetryDelay,
    KaiQuietHours quietHours = const KaiQuietHours.none(),
    int deliveriesUsed = 0,
    int deliveryBudget = 0,
    Set<String> processedEventIds = const {},
    bool urgentOverrideAuthorized = false,
  }) {
    if (budgetRetryDelay <= Duration.zero) {
      throw ArgumentError.value(
        budgetRetryDelay,
        'budgetRetryDelay',
        'must be positive',
      );
    }
    return KaiAttentionContext._(
      now: now.toUtc(),
      candidates: candidates,
      budgetRetryDelay: budgetRetryDelay,
      quietHours: quietHours,
      deliveriesUsed: deliveriesUsed,
      deliveryBudget: deliveryBudget,
      processedEventIds: processedEventIds,
      urgentOverrideAuthorized: urgentOverrideAuthorized,
    );
  }

  const KaiAttentionContext._({
    required this.now,
    required this.candidates,
    required this.budgetRetryDelay,
    required this.quietHours,
    required this.deliveriesUsed,
    required this.deliveryBudget,
    required this.processedEventIds,
    required this.urgentOverrideAuthorized,
  });

  final DateTime now;
  final List<KaiBodyRouteCandidate> candidates;
  final KaiQuietHours quietHours;
  final int deliveriesUsed;
  final int deliveryBudget;

  /// Explicit pacing policy. The decision engine never invents this interval.
  final Duration budgetRetryDelay;

  final Set<String> processedEventIds;

  /// Comes from POLICY, never from an event.
  ///
  /// A body can put `"urgent": true` in a payload; that is a body asserting its
  /// own importance, and it grants nothing. Only an authorization the policy
  /// layer supplies can cross quiet hours.
  final bool urgentOverrideAuthorized;

  bool get budgetExhausted =>
      deliveryBudget > 0 && deliveriesUsed >= deliveryBudget;
}

/// One reproducible decision, carrying enough to audit it later.
class KaiAttentionDecision {
  const KaiAttentionDecision({
    required this.outcome,
    required this.reasonCode,
    required this.eventId,
    required this.correlationId,
    this.bodyId,
    this.notBefore,
    this.remainsDurable = false,
  });

  final KaiAttentionOutcome outcome;

  /// Machine-readable, stable, lower_snake_case. Logs and audits key off this,
  /// so it is part of the contract rather than a message.
  final String reasonCode;

  final String eventId;
  final String correlationId;

  /// At most one body. Null for every non-delivering outcome.
  final String? bodyId;

  final DateTime? notBefore;

  /// True when Kai still owes this after the decision.
  final bool remainsDurable;

  Map<String, Object?> toJson() => {
        'outcome': outcome.name,
        'reasonCode': reasonCode,
        'eventId': eventId,
        'correlationId': correlationId,
        if (bodyId != null) 'bodyId': bodyId,
        if (notBefore != null) 'notBefore': notBefore!.toIso8601String(),
        'remainsDurable': remainsDurable,
      };

  @override
  bool operator ==(Object other) =>
      other is KaiAttentionDecision &&
      other.outcome == outcome &&
      other.reasonCode == reasonCode &&
      other.eventId == eventId &&
      other.correlationId == correlationId &&
      other.bodyId == bodyId &&
      other.notBefore == notBefore &&
      other.remainsDurable == remainsDurable;

  @override
  int get hashCode => Object.hash(outcome, reasonCode, eventId, correlationId,
      bodyId, notBefore, remainsDurable);

  @override
  String toString() => 'KaiAttentionDecision(${toJson()})';
}
