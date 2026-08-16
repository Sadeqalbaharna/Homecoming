// ledger_sources — the list of things Kai may read to build the ledger.
//
// ── This list IS the security boundary ──────────────────────────────────────
//
// Everything downstream — the durable capture queue, the parser, the
// auto-confirm rules — trusts that whatever reached it came from a source
// Sadeq named. Nothing else in the ledger path checks provenance, because this
// is where provenance is decided.
//
// Which makes two properties non-negotiable:
//
//   EMPTY BY DEFAULT. An earlier version of the Android store shipped with five
//   guessed Bahraini sender ids already enrolled. That invented a trust
//   boundary instead of asking for one, and a wrong guess fails as SILENCE —
//   the ledger simply never fills and nothing reports an error. Enrolment is
//   something Sadeq does, not something a developer assumes.
//
//   EXACT MATCH, NEVER A PATTERN. "Anything containing BANK" matches a scammer
//   who calls themselves BANK-ALERT. Substring matching on a trust boundary is
//   the boundary agreeing to be talked around.
//
// ── The email trap ──────────────────────────────────────────────────────────
//
// An email From header has two halves and only one of them is real:
//
//     From: "NBB Alerts" <noreply@totally-not-a-bank.ru>
//
// The display name is chosen by the sender and means nothing. The address is
// the channel. Matching on the display name is the email-shaped version of
// trusting the payload — the same mistake as reading an SMS body to decide
// whether to trust the SMS.
//
// So email sources match on the ADDRESS ONLY, and the display name is kept
// purely so a human can read the list back.
//
// Pure and deterministic. Persistence is the caller's problem.

/// Which channel a source arrives through. Kept explicit so an SMS sender id
/// and an email address can never be compared to each other — "NBB" as a
/// sender id and "nbb@..." as an address are different claims.
enum KaiLedgerChannel { sms, email }

class KaiLedgerSource {
  const KaiLedgerSource({
    required this.channel,
    required this.identifier,
    this.label = '',
    this.enabled = true,
  });

  final KaiLedgerChannel channel;

  /// The SMS sender id, or the full email address. Compared case-insensitively
  /// and otherwise exactly.
  final String identifier;

  /// For the human reading the list. Never used for matching — see the header.
  final String label;

  /// Off keeps the entry visible while stopping capture. Deleting an enrolment
  /// you might want back encourages re-adding it hastily; disabling leaves the
  /// decision recorded.
  final bool enabled;

  String get key => '${channel.name}:${identifier.trim().toLowerCase()}';

  Map<String, dynamic> toJson() => {
        'channel': channel.name,
        'identifier': identifier,
        'label': label,
        'enabled': enabled,
      };

  static KaiLedgerSource? fromJson(Map<String, dynamic> json) {
    final id = (json['identifier'] as String?)?.trim() ?? '';
    if (id.isEmpty) return null;
    final channelName = json['channel'] as String?;
    final channel = KaiLedgerChannel.values
        .where((c) => c.name == channelName)
        .cast<KaiLedgerChannel?>()
        .firstWhere((c) => true, orElse: () => null);
    // An unknown channel fails closed: a source that cannot be classified
    // cannot be trusted, and dropping it is safer than defaulting it to SMS.
    if (channel == null) return null;
    return KaiLedgerSource(
      channel: channel,
      identifier: id,
      label: (json['label'] as String?) ?? '',
      enabled: json['enabled'] != false,
    );
  }
}

class KaiLedgerSources {
  KaiLedgerSources([Iterable<KaiLedgerSource> sources = const []]) {
    for (final s in sources) {
      _byKey[s.key] = s;
    }
  }

  final Map<String, KaiLedgerSource> _byKey = {};

  List<KaiLedgerSource> get all {
    final out = _byKey.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  List<KaiLedgerSource> get enabled =>
      all.where((s) => s.enabled).toList(growable: false);

  bool get isEmpty => _byKey.isEmpty;

  void add(KaiLedgerSource source) => _byKey[source.key] = source;

  /// Removing genuinely removes. A revocation that only stops future additions
  /// is not a revocation.
  void remove(KaiLedgerChannel channel, String identifier) =>
      _byKey.remove(KaiLedgerSource(channel: channel, identifier: identifier).key);

  void setEnabled(KaiLedgerChannel channel, String identifier, bool value) {
    final key =
        KaiLedgerSource(channel: channel, identifier: identifier).key;
    final existing = _byKey[key];
    if (existing == null) return;
    _byKey[key] = KaiLedgerSource(
      channel: existing.channel,
      identifier: existing.identifier,
      label: existing.label,
      enabled: value,
    );
  }

  /// May an SMS from this sender be captured?
  bool allowsSms(String? sender) =>
      _allows(KaiLedgerChannel.sms, sender);

  /// May this email be captured?
  ///
  /// Takes the raw From header and uses only the address inside it. A caller
  /// that passes a display name gets false, which is the correct answer.
  bool allowsEmail(String? fromHeader) {
    final address = addressOf(fromHeader);
    return address == null ? false : _allows(KaiLedgerChannel.email, address);
  }

  bool _allows(KaiLedgerChannel channel, String? identifier) {
    final id = identifier?.trim().toLowerCase() ?? '';
    if (id.isEmpty) return false;
    final source = _byKey['${channel.name}:$id'];
    return source != null && source.enabled;
  }

  /// The address out of a From header, ignoring the display name entirely.
  ///
  /// `"NBB Alerts" <noreply@evil.ru>` yields `noreply@evil.ru`, which will then
  /// fail to match — that is the point. A bare address is also accepted, since
  /// some sources supply one directly.
  static String? addressOf(String? fromHeader) {
    final raw = fromHeader?.trim() ?? '';
    if (raw.isEmpty) return null;
    final angled = RegExp(r'<([^<>]+)>').firstMatch(raw);
    final candidate = (angled?.group(1) ?? raw).trim().toLowerCase();
    // Must look like an address. A display name that happens to contain no
    // angle brackets must not be accepted as one.
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(candidate)) return null;
    return candidate;
  }

  /// What to push down to the Android capture filter. SMS only — the phone
  /// listener has no concept of email.
  List<String> get smsFilter => enabled
      .where((s) => s.channel == KaiLedgerChannel.sms)
      .map((s) => s.identifier.trim().toUpperCase())
      .toList(growable: false);

  List<Map<String, dynamic>> toJson() =>
      all.map((s) => s.toJson()).toList(growable: false);

  static KaiLedgerSources fromJson(List<dynamic> rows) => KaiLedgerSources(
        rows
            .whereType<Map<String, dynamic>>()
            .map(KaiLedgerSource.fromJson)
            .whereType<KaiLedgerSource>(),
      );
}
