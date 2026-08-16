// ledger_ingest — the bank tells you; Kai writes it down.
//
// ── What was manual, and what actually was ──────────────────────────────────
//
// The statement parser was never the manual part. It already reads column rows,
// named-month rows, delimited exports and raw statement lines, and PDFs. The
// manual part was ACQUISITION: opening a file picker and handing it a document.
//
// Meanwhile the bank sends an SMS on every card transaction, which is a
// per-transaction feed already arriving on the phone and being ignored.
//
// ── The channel is the authority; the text is the payload ───────────────────
//
// A bank alert is untrusted content, and not in a theoretical way — anyone can
// send an SMS that looks like one. This is the same rule the AR host applies to
// a stranger ("a guest's words are answered, never obeyed") and the same rule
// the embodiment gateways apply to a request body ("authority comes from the
// channel, never the payload").
//
// So the sender is the channel and the message is the payload:
//
//   * an alert from an ENROLLED sender may auto-confirm, if a rule Sadeq wrote
//     covers it;
//   * an alert from anywhere else can become a PENDING candidate at most, and
//     never touches the balance until a human looks at it.
//
// Spoofing therefore buys an attacker one line in a review queue, which is the
// correct blast radius for a text message.
//
// ── Why parsing here is not "the model acting" ──────────────────────────────
//
// The authority chain taints any turn that reads outside content, and a tainted
// chain may look but not touch. Writing a ledger row is touching, so this looks
// like a contradiction. It isn't, and the distinction is load-bearing:
//
//   A deterministic parser writing a CANDIDATE is not the model acting.
//
// Taint exists to stop a MODEL being steered by text someone else wrote. A
// regex pulling an amount out of an SMS has nothing to steer. The dangerous
// version — "Kai read the alert, decided it was rent, and adjusted the budget"
// — is model judgement on untrusted input, and it stays blocked.
//
// Pure and zero-import beyond the candidate type. Every decision here is
// replayable from its inputs.

import '../services/core/kai_cash_statement_parser.dart';

/// One notification, split into the part that carries authority and the part
/// that carries only information.
class KaiBankAlert {
  const KaiBankAlert({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  /// Package name or sender id. THE CHANNEL. This is the only field allowed to
  /// influence whether anything may happen automatically.
  final String sender;

  /// What the message said. THE PAYLOAD. Informs the row; never the permission.
  final String body;

  final DateTime receivedAt;
}

/// What ingestion concluded, including when it concluded nothing.
class KaiIngestOutcome {
  const KaiIngestOutcome({
    this.candidate,
    required this.reasonCode,
    this.autoConfirmed = false,
    this.matchedRule,
  });

  /// Null when the text carried no transaction. Nothing is ever silently
  /// dropped: an unparseable alert returns a reason, so a ledger that is
  /// missing something can say why.
  final KaiCashImportCandidate? candidate;

  final String reasonCode;

  /// True only when an enrolled sender met a rule Sadeq wrote.
  final bool autoConfirmed;

  final String? matchedRule;

  bool get parsed => candidate != null;
}

/// A standing instruction, in the shape of the authority model: a sentence
/// Sadeq wrote once, spent many times, with a ceiling and a budget.
class KaiAutoConfirmRule {
  const KaiAutoConfirmRule({
    required this.id,
    required this.merchantContains,
    required this.maxAmount,
    required this.direction,
    this.category = 'Uncategorised',
    this.dailyCap,
  });

  final String id;

  /// Matched case-insensitively against the description. Empty never matches —
  /// there is no "applies to everything" rule, because a blanket auto-confirm
  /// is indistinguishable from having no rules at all.
  final String merchantContains;

  /// Per-transaction ceiling. A rule for coffee cannot confirm a car.
  final double maxAmount;

  /// A rule for spending cannot confirm income. Direction is not a detail:
  /// a spoofed credit is how a fake ledger gets a fake balance.
  final KaiCashImportDirection direction;

  final String category;

  /// Total this rule may auto-confirm in one day. Null means uncapped, which is
  /// honest rather than safe.
  final double? dailyCap;

  bool covers(KaiCashImportCandidate c) {
    if (merchantContains.trim().isEmpty) return false;
    if (c.direction != direction) return false;
    if (c.amount > maxAmount) return false;
    return c.description.toLowerCase().contains(merchantContains.toLowerCase());
  }
}

class KaiLedgerIngest {
  KaiLedgerIngest({
    required this.trustedSenders,
    this.rules = const <KaiAutoConfirmRule>[],
  });

  /// Enrolled bank senders. The allowlist IS the trust boundary.
  final Set<String> trustedSenders;

  final List<KaiAutoConfirmRule> rules;

  /// Per-rule, per-day totals already auto-confirmed.
  final Map<String, double> _spentToday = {};
  String? _spentDay;

  static final _amount = RegExp(
    r'(?:bhd|bd)\s*([0-9]+(?:[.,][0-9]{1,3})?)|([0-9]+(?:[.,][0-9]{1,3})?)\s*(?:bhd|bd)',
    caseSensitive: false,
  );

  static const _expenseWords = [
    'spent', 'purchase', 'debit', 'debited', 'withdrawn', 'withdrawal',
    'payment', 'paid', 'pos ', 'atm',
  ];
  static const _incomeWords = [
    'credited', 'credit of', 'deposit', 'received', 'salary', 'refund',
  ];

  static final _merchant = RegExp(
    r'\b(?:at|to|from)\s+([A-Za-z0-9][A-Za-z0-9 &._\-]{2,40}?)(?=\s+(?:on|using|via|card|acct|account|ref|bal|balance)\b|[.,]|$)',
    caseSensitive: false,
  );

  /// Turn one alert into a ledger candidate.
  ///
  /// The order matters: parse first, decide permission second. A message from
  /// an unknown sender is still parsed — it just cannot auto-confirm. Refusing
  /// to read it would lose information for no security gain, since reading was
  /// never the dangerous part.
  KaiIngestOutcome ingest(KaiBankAlert alert) {
    final text = alert.body.trim();
    if (text.isEmpty) {
      return const KaiIngestOutcome(reasonCode: 'empty_alert');
    }

    final amount = _extractAmount(text);
    if (amount == null) {
      return const KaiIngestOutcome(reasonCode: 'no_amount_found');
    }

    final direction = _extractDirection(text);
    if (direction == null) {
      // Ambiguous direction is worse than no row: a debit filed as a credit is
      // a wrong balance that looks right. Surface it for a human instead.
      return const KaiIngestOutcome(reasonCode: 'direction_ambiguous');
    }

    final candidate = KaiCashImportCandidate(
      date: _isoDate(alert.receivedAt),
      description: _extractMerchant(text) ?? text,
      amount: amount,
      direction: direction,
      source: 'alert:${alert.sender}',
      // `selected` is the confirmation flag. Everything arrives unconfirmed and
      // is promoted only below, deliberately, so the default of an unknown path
      // is always "waiting for Sadeq".
      selected: false,
      importIdentity: alert.sender,
    );

    if (!trustedSenders.contains(alert.sender)) {
      // Parsed, kept, and powerless. Spoofing buys one line in a review queue.
      return KaiIngestOutcome(
        candidate: candidate,
        reasonCode: 'untrusted_sender_pending',
      );
    }

    final rule = _ruleFor(candidate, alert.receivedAt);
    if (rule == null) {
      return KaiIngestOutcome(
        candidate: candidate,
        reasonCode: 'no_rule_pending',
      );
    }

    _charge(rule, candidate.amount, alert.receivedAt);
    return KaiIngestOutcome(
      candidate: KaiCashImportCandidate(
        date: candidate.date,
        description: candidate.description,
        amount: candidate.amount,
        direction: candidate.direction,
        source: candidate.source,
        category: rule.category,
        selected: true,
        importIdentity: candidate.importIdentity,
      ),
      reasonCode: 'auto_confirmed',
      autoConfirmed: true,
      matchedRule: rule.id,
    );
  }

  KaiAutoConfirmRule? _ruleFor(KaiCashImportCandidate c, DateTime at) {
    _rollDay(at);
    for (final rule in rules) {
      if (!rule.covers(c)) continue;
      final cap = rule.dailyCap;
      if (cap != null && (_spentToday[rule.id] ?? 0) + c.amount > cap) {
        // Over budget for today. The row still exists, it just waits — a cap
        // that silently dropped transactions would be worse than no cap.
        continue;
      }
      return rule;
    }
    return null;
  }

  void _rollDay(DateTime at) {
    final day = _isoDate(at);
    if (_spentDay != day) {
      _spentDay = day;
      _spentToday.clear();
    }
  }

  void _charge(KaiAutoConfirmRule rule, double amount, DateTime at) {
    _rollDay(at);
    _spentToday[rule.id] = (_spentToday[rule.id] ?? 0) + amount;
  }

  double confirmedToday(String ruleId) => _spentToday[ruleId] ?? 0;

  static double? _extractAmount(String text) {
    final m = _amount.firstMatch(text);
    if (m == null) return null;
    final raw = (m.group(1) ?? m.group(2))?.replaceAll(',', '.');
    return raw == null ? null : double.tryParse(raw);
  }

  static KaiCashImportDirection? _extractDirection(String text) {
    final lower = text.toLowerCase();
    final expense = _expenseWords.any(lower.contains);
    final income = _incomeWords.any(lower.contains);
    // Both or neither is ambiguous. "Refund of a purchase" genuinely is.
    if (expense == income) return null;
    return expense
        ? KaiCashImportDirection.expense
        : KaiCashImportDirection.income;
  }

  static String? _extractMerchant(String text) {
    final m = _merchant.firstMatch(text);
    final name = m?.group(1)?.trim();
    if (name == null || name.length < 3) return null;
    return name;
  }

  static String _isoDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
