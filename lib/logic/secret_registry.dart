// secret_registry — what needs rotating, how old it is, and where to go.
//
// ── The rule that shapes everything here ────────────────────────────────────
//
// THIS NEVER HOLDS OR SHOWS A SECRET VALUE.
//
// A panel that prints keys on screen is a new exposure surface, and this app in
// particular has `read_screen` as a tool. Anything rendered is readable by the
// assistant, by a screenshot, by a share. So the registry stores a short
// FINGERPRINT — enough to confirm a rotation actually changed something, and
// useless to anyone who copies it.
//
// ── Why a tracker and not an auto-rotator ───────────────────────────────────
//
// Rotating an OpenAI or Firebase key is console work, and automating it would
// mean holding a management credential that can mint and revoke every other
// credential — trading six keys for one master key, which is a worse position.
//
// The friction was never the clicking. It was "which ones are there, which did
// I already do, and where do I go" — three questions with no single place to
// ask them. That is what this answers.
//
// ── Not everything that looks like a key is a secret ────────────────────────
//
// Firebase web/mobile API keys identify a PROJECT; they are meant to ship in
// clients and security comes from database rules, not from hiding them. Listing
// them beside a live OpenAI key as equally urgent produces alarm fatigue, and a
// panel nobody believes is worse than no panel.
//
// So they appear, labelled as identifiers, with the honest note that the thing
// to audit is the rules rather than the string.
//
// Pure, deterministic, no I/O.

/// What a credential actually is, which decides how loudly to talk about it.
enum KaiSecretKind {
  /// Grants access on its own. Rotate on a schedule; never commit.
  secret,

  /// Identifies a project and is meant to be public. Shipping it is not a
  /// breach — permissive rules are. Shown for completeness, never as an alarm.
  publicIdentifier,
}

/// Where a credential lives, which decides how bad an exposure is.
enum KaiSecretStore {
  /// Compile-time constants in a gitignored file. Local only.
  sourceLocal,

  /// Runtime secure storage on the device.
  secureStorage,

  /// Committed to the repository. For a real secret this is the worst case,
  /// because history keeps it after any later deletion.
  tracked,
}

enum KaiSecretUrgency {
  /// Committed real secret. Rotation does not fix history; it limits the
  /// window. Always first.
  exposed,

  /// Past the rotation interval.
  overdue,

  /// No rotation has ever been recorded. Distinct from "rotated long ago" on
  /// purpose: an unknown age is not a safe age, and treating it as fresh is how
  /// a key from three years ago looks fine.
  neverRotated,

  /// Approaching the interval.
  aging,

  fresh,

  /// A public identifier. Nothing to rotate on a clock.
  informational,
}

class KaiSecret {
  const KaiSecret({
    required this.id,
    required this.label,
    required this.provider,
    required this.store,
    required this.location,
    this.kind = KaiSecretKind.secret,
    this.consoleUrl = '',
    this.lastRotated,
    this.fingerprint = '',
    this.inGitHistory = false,
    this.note = '',
  });

  final String id;
  final String label;
  final String provider;
  final KaiSecretStore store;

  /// File path or storage key. Where to go, not what is there.
  final String location;

  final KaiSecretKind kind;

  /// Deep link to the page that rotates it. The whole point is removing the
  /// "where do I even go" step.
  final String consoleUrl;

  final DateTime? lastRotated;

  /// First 8 hex of a hash of the value. Enough to confirm a rotation changed
  /// something; useless to anyone who reads it. NEVER the value.
  final String fingerprint;

  /// The value has been committed at some point. Deleting it later does not
  /// undo this — history keeps it.
  final bool inGitHistory;

  final String note;

  int? ageInDays(DateTime now) {
    final at = lastRotated;
    return at == null ? null : now.difference(at).inDays;
  }

  KaiSecretUrgency urgency(DateTime now, {int intervalDays = 90}) {
    if (kind == KaiSecretKind.publicIdentifier) {
      return KaiSecretUrgency.informational;
    }
    if (inGitHistory) return KaiSecretUrgency.exposed;
    final age = ageInDays(now);
    if (age == null) return KaiSecretUrgency.neverRotated;
    if (age >= intervalDays) return KaiSecretUrgency.overdue;
    if (age >= (intervalDays * 2) ~/ 3) return KaiSecretUrgency.aging;
    return KaiSecretUrgency.fresh;
  }

  KaiSecret rotated(DateTime at, String newFingerprint) => KaiSecret(
        id: id,
        label: label,
        provider: provider,
        store: store,
        location: location,
        kind: kind,
        consoleUrl: consoleUrl,
        lastRotated: at,
        fingerprint: newFingerprint,
        // Rotating clears the exposure: the committed value no longer opens
        // anything. History still holds the OLD string, which is now inert.
        inGitHistory: false,
        note: note,
      );
}

class KaiSecretRegistry {
  const KaiSecretRegistry(this.secrets, {this.intervalDays = 90});

  final List<KaiSecret> secrets;
  final int intervalDays;

  /// Ordered so the top of the list is the answer to "what now".
  ///
  /// Urgency first, then oldest first within a band. A panel that needs reading
  /// to be understood is a panel that gets ignored.
  List<KaiSecret> ranked(DateTime now) {
    final out = [...secrets];
    out.sort((a, b) {
      final ua = a.urgency(now, intervalDays: intervalDays).index;
      final ub = b.urgency(now, intervalDays: intervalDays).index;
      if (ua != ub) return ua.compareTo(ub);
      final aa = a.ageInDays(now) ?? 1 << 30;
      final ab = b.ageInDays(now) ?? 1 << 30;
      return ab.compareTo(aa);
    });
    return out;
  }

  int countAt(DateTime now, KaiSecretUrgency urgency) => secrets
      .where((s) => s.urgency(now, intervalDays: intervalDays) == urgency)
      .length;

  /// The one-line answer, for a card header.
  String summary(DateTime now) {
    final exposed = countAt(now, KaiSecretUrgency.exposed);
    final overdue = countAt(now, KaiSecretUrgency.overdue);
    final never = countAt(now, KaiSecretUrgency.neverRotated);
    if (exposed > 0) return '$exposed exposed';
    if (overdue > 0) return '$overdue overdue';
    if (never > 0) return '$never never rotated';
    final aging = countAt(now, KaiSecretUrgency.aging);
    if (aging > 0) return '$aging due soon';
    return 'all current';
  }

  bool get needsAttention => secrets.any((s) =>
      s.kind == KaiSecretKind.secret &&
      (s.inGitHistory || s.lastRotated == null));
}
