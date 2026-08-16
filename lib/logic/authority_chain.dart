// authority_chain — every action traces back to a sentence Sadeq wrote.
//
// ── The rule ────────────────────────────────────────────────────────────────
//
//   Omnipresent in what he sees. Free to speak. Acts only on authority that
//   traces back to you — deferred is fine, invented is not.
//
// Perception needs no permission and neither does speech: noticing that stays
// silent is not noticing. Action is the layer that needs an origin, and the
// origin is always a human sentence.
//
// ── Why "deferred, never invented" and not "needs a prompt" ─────────────────
//
// "Never acts without a prompt" is almost right and breaks on the first real
// case. `remind me at five` is the prompt; the reminder fires at five, when
// nobody is there and nothing is prompting anything. Under a literal reading
// that is an unprompted action and the whole commitment ledger is illegal.
//
// It is not unprompted, it is DEFERRED. The authority was granted earlier and
// spent later. So the rule is about where authority comes from, not about when
// it is used:
//
//   * granted — a human said something. This is the only root.
//   * deferred — a grant that fires later. Still rooted in the same sentence.
//   * derived — one authorised action needing a sub-action. Rooted through its
//     parent, and never wider than it.
//
// There is deliberately no fourth kind. A model cannot mint a root, because the
// constructor for one requires text a model did not write.
//
// ── What this is not ────────────────────────────────────────────────────────
//
// Provenance answers WHO AUTHORISED THIS. It does not answer HOW FAR THAT GOES.
// One sentence — "sort out my finances this month" — can authorise fifty
// writes, and "handle my emails" authorises reading a list whose contents are
// written by other people. Blast radius is a separate control that belongs on
// top of this one; see [AuthorityGrant.maxActions] for the crude first version.
//
// You cannot bound what you cannot trace, so tracing comes first.
//
// Pure, zero-import, deterministic. Same reason lib/logic exists.

/// How a piece of authority came to exist.
enum AuthorityKind {
  /// A human said something. The only root there is.
  granted,

  /// A grant that fires later — a reminder, a scheduled job. Same root.
  deferred,

  /// A sub-action of something already authorised. Never wider than its parent.
  derived,
}

/// Why an action was refused.
enum AuthorityRefusal {
  none,
  unknownAuthority,
  revoked,
  expired,
  exhausted,
  parentRefused,
  notInScope,
}

class AuthorityDecision {
  const AuthorityDecision._(this.allowed, this.refusal, this.rootId);

  const AuthorityDecision.allow(String rootId)
      : this._(true, AuthorityRefusal.none, rootId);

  const AuthorityDecision.refuse(AuthorityRefusal refusal)
      : this._(false, refusal, null);

  final bool allowed;
  final AuthorityRefusal refusal;

  /// The human sentence this action ultimately answers to. Present only when
  /// allowed — the point of the whole exercise is that this is always knowable.
  final String? rootId;

  String get reasonCode => refusal.name;
}

/// One link in the chain.
class AuthorityGrant {
  const AuthorityGrant({
    required this.id,
    required this.kind,
    required this.grantedAt,
    this.parentId,
    this.originText = '',
    this.scope = const <String>{},
    this.expiresAt,
    this.maxActions,
    this.revoked = false,
  });

  /// A root: something Sadeq actually said.
  ///
  /// [originText] is required and must be non-empty, which is the mechanism
  /// rather than the documentation. A model has no way to call this without
  /// producing text it claims a human wrote, and that claim is inspectable.
  factory AuthorityGrant.fromHuman({
    required String id,
    required String originText,
    required DateTime grantedAt,
    Set<String> scope = const <String>{},
    DateTime? expiresAt,
    int? maxActions,
  }) {
    if (originText.trim().isEmpty) {
      throw ArgumentError.value(
        originText,
        'originText',
        'a root authority must quote what was actually said',
      );
    }
    return AuthorityGrant(
      id: id,
      kind: AuthorityKind.granted,
      grantedAt: grantedAt,
      originText: originText,
      scope: scope,
      expiresAt: expiresAt,
      maxActions: maxActions,
    );
  }

  final String id;
  final AuthorityKind kind;
  final DateTime grantedAt;

  /// Null only for a root.
  final String? parentId;

  /// The sentence, for roots. Kept so a receipt can quote it rather than
  /// reconstruct it — "why did you move that money" should return what you
  /// typed, not a plausible paraphrase.
  final String originText;

  /// Which actions this permits. Empty means "inherit from parent"; a root with
  /// an empty scope permits anything, which is what a direct instruction in a
  /// chat window means.
  final Set<String> scope;

  final DateTime? expiresAt;

  /// Crude blast radius. Null means unbounded, which is honest rather than safe
  /// — see the header note.
  final int? maxActions;

  final bool revoked;

  AuthorityGrant copyWith({bool? revoked}) => AuthorityGrant(
        id: id,
        kind: kind,
        grantedAt: grantedAt,
        parentId: parentId,
        originText: originText,
        scope: scope,
        expiresAt: expiresAt,
        maxActions: maxActions,
        revoked: revoked ?? this.revoked,
      );
}

/// Holds the chains and answers the only question that matters: may this run?
class AuthorityLedger {
  final Map<String, AuthorityGrant> _grants = {};
  final Map<String, int> _spent = {};

  /// Register a root. Returns it so a caller can hold the id.
  AuthorityGrant grantFromHuman({
    required String id,
    required String originText,
    required DateTime at,
    Set<String> scope = const <String>{},
    DateTime? expiresAt,
    int? maxActions,
  }) {
    final grant = AuthorityGrant.fromHuman(
      id: id,
      originText: originText,
      grantedAt: at,
      scope: scope,
      expiresAt: expiresAt,
      maxActions: maxActions,
    );
    _grants[id] = grant;
    return grant;
  }

  /// A grant that will be spent later — a reminder, a scheduled run.
  ///
  /// Requires a parent, so a deferral cannot be conjured. This is what keeps
  /// the commitment ledger legal under the rule.
  AuthorityGrant defer({
    required String id,
    required String parentId,
    required DateTime at,
    DateTime? expiresAt,
    Set<String> scope = const <String>{},
  }) =>
      _add(AuthorityGrant(
        id: id,
        kind: AuthorityKind.deferred,
        grantedAt: at,
        parentId: parentId,
        scope: scope,
        expiresAt: expiresAt,
      ));

  /// A sub-action of something already authorised.
  AuthorityGrant derive({
    required String id,
    required String parentId,
    required DateTime at,
    Set<String> scope = const <String>{},
  }) =>
      _add(AuthorityGrant(
        id: id,
        kind: AuthorityKind.derived,
        grantedAt: at,
        parentId: parentId,
        scope: scope,
      ));

  AuthorityGrant _add(AuthorityGrant g) {
    _grants[g.id] = g;
    return g;
  }

  /// Kill an authority. Everything descended from it dies with it, because
  /// [check] walks to the root every time and finds the revocation on the way.
  ///
  /// Revoking is why broad standing permissions are safe to grant at all.
  void revoke(String id) {
    final g = _grants[id];
    if (g != null) _grants[id] = g.copyWith(revoked: true);
  }

  bool isKnown(String id) => _grants.containsKey(id);

  int spent(String id) => _spent[id] ?? 0;

  /// May [action] run under [authorityId] at [now]?
  ///
  /// Walks to the root. An unknown id refuses — there is no "assume it's fine"
  /// path, because that path is exactly how an invented authority would work.
  AuthorityDecision check({
    required String authorityId,
    required String action,
    required DateTime now,
  }) {
    final seen = <String>{};
    var currentId = authorityId;
    Set<String>? narrowest;

    while (true) {
      final g = _grants[currentId];
      if (g == null) {
        return AuthorityDecision.refuse(
          currentId == authorityId
              ? AuthorityRefusal.unknownAuthority
              : AuthorityRefusal.parentRefused,
        );
      }
      if (!seen.add(currentId)) {
        // A cycle cannot reach a human sentence, so it is not authority.
        return const AuthorityDecision.refuse(AuthorityRefusal.parentRefused);
      }
      if (g.revoked) {
        return AuthorityDecision.refuse(
          currentId == authorityId
              ? AuthorityRefusal.revoked
              : AuthorityRefusal.parentRefused,
        );
      }
      final expires = g.expiresAt;
      if (expires != null && !now.isBefore(expires)) {
        return AuthorityDecision.refuse(
          currentId == authorityId
              ? AuthorityRefusal.expired
              : AuthorityRefusal.parentRefused,
        );
      }
      final cap = g.maxActions;
      if (cap != null && (_spent[currentId] ?? 0) >= cap) {
        return AuthorityDecision.refuse(
          currentId == authorityId
              ? AuthorityRefusal.exhausted
              : AuthorityRefusal.parentRefused,
        );
      }
      // Scope narrows going down and can never widen: a child may restrict what
      // its parent allowed, never add to it.
      if (g.scope.isNotEmpty) {
        narrowest =
            narrowest == null ? g.scope : narrowest.intersection(g.scope);
      }

      if (g.kind == AuthorityKind.granted) {
        if (narrowest != null && !narrowest.contains(action)) {
          return const AuthorityDecision.refuse(AuthorityRefusal.notInScope);
        }
        return AuthorityDecision.allow(g.id);
      }

      final parent = g.parentId;
      if (parent == null) {
        // Non-root with no parent cannot reach a sentence. This is the shape an
        // invented authority would have, and it is refused by construction.
        return const AuthorityDecision.refuse(AuthorityRefusal.parentRefused);
      }
      currentId = parent;
    }
  }

  /// Record that an action ran, so [AuthorityGrant.maxActions] means something.
  /// Charges the whole chain — a budget on a root cannot be dodged by deriving.
  void recordSpend(String authorityId) {
    var currentId = authorityId;
    final seen = <String>{};
    while (seen.add(currentId)) {
      final g = _grants[currentId];
      if (g == null) return;
      _spent[currentId] = (_spent[currentId] ?? 0) + 1;
      final parent = g.parentId;
      if (parent == null) return;
      currentId = parent;
    }
  }

  /// The sentence an action answers to. Null when the chain does not reach one.
  String? originTextFor(String authorityId) {
    var currentId = authorityId;
    final seen = <String>{};
    while (seen.add(currentId)) {
      final g = _grants[currentId];
      if (g == null) return null;
      if (g.kind == AuthorityKind.granted) return g.originText;
      final parent = g.parentId;
      if (parent == null) return null;
      currentId = parent;
    }
    return null;
  }
}
