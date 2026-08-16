// The pipes between the phone and the ledger.
//
// Both ends already existed and could not reach each other. This is the
// sequence that joins them, and it is deliberately boring: every real decision
// belongs to a pure unit that is tested on its own.
//
// The alerts here are verbatim from Sadeq's Al Salam messages, and the senders
// are the real enrolled ones — Alsalambank and Credimax.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_ingest.dart';
import 'package:homecoming_app/logic/ledger_sources.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';
import 'package:homecoming_app/services/core/kai_ledger_pipeline.dart';

final at = DateTime(2026, 8, 11, 11, 16);

Map<String, Object?> alert(String text, {String sender = 'Alsalambank'}) => {
      'sender': sender,
      'text': text,
      'receivedAt': at.millisecondsSinceEpoch,
    };

const purchase =
    'BHD 24.420 debited from Acc. XXX94150000 at FINE FOODS - MINA SALMMANAMA '
    'BH.Bal: BHD 354.620 on 11/08/26 at 11:16. Tel 17005500';
const coffee =
    'BHD 1.500 debited from Acc. XXX94150000 at THE COFFEE BEAN TEA MANAMA '
    'BH.Bal: BHD 330.732 on 08/08/26 at 10:40.';
const coffeeAgain =
    'BHD 1.500 debited from Acc. XXX94150000 at THE COFFEE BEAN TEA MANAMA '
    'BH.Bal: BHD 329.232 on 08/08/26 at 12:06.';

KaiLedgerSources enrolled() => KaiLedgerSources([
      const KaiLedgerSource(
        channel: KaiLedgerChannel.sms,
        identifier: 'Alsalambank',
      ),
      const KaiLedgerSource(
        channel: KaiLedgerChannel.sms,
        identifier: 'Credimax',
      ),
    ]);

class _Harness {
  _Harness({
    List<Map<String, Object?>> queue = const [],
    List<KaiAutoConfirmRule> rules = const [],
    KaiLedgerSources? sources,
    bool failDrain = false,
  }) {
    pipeline = KaiLedgerPipeline(
      sources: sources ?? enrolled(),
      rules: rules,
      pushSenders: (s) async => pushed.add(s),
      drainAlerts: () async {
        if (failDrain) throw StateError('no notification access');
        return queue;
      },
      append: (rows) async => appended.addAll(rows),
    );
  }

  late final KaiLedgerPipeline pipeline;
  final List<List<String>> pushed = [];
  final List<KaiLedgerRow> appended = [];
}

void main() {
  test('the enrolment list reaches the phone before every drain', () {
    // Also how revocation reaches it: pushing an empty list is meaningful.
    final h = _Harness();
    return h.pipeline.runOnce().then((_) {
      expect(h.pushed.single, ['ALSALAMBANK', 'CREDIMAX']);
    });
  });

  test('a real alert becomes a pending row with its balance', () async {
    final h = _Harness(queue: [alert(purchase)]);
    final run = await h.pipeline.runOnce();

    expect(run.ok, isTrue);
    expect(run.drained, 1);
    expect(run.appended, 1);
    expect(run.autoApproved, 0);

    final row = h.appended.single;
    expect(row.candidate.amount, 24.42);
    expect(row.candidate.description, contains('FINE FOODS'));
    expect(row.approved, isFalse, reason: 'no rule covers it, so it waits');
    expect(row.balance!.balance, 354.620);
    expect(row.balance!.account, '94150000');
  });

  test('a rule Sadeq wrote approves, and nothing else does', () async {
    final h = _Harness(
      queue: [alert(coffee), alert(purchase)],
      rules: const [
        KaiAutoConfirmRule(
          id: 'coffee',
          merchantContains: 'coffee bean',
          maxAmount: 5,
          direction: KaiCashImportDirection.expense,
          category: 'Coffee',
        ),
      ],
    );
    final run = await h.pipeline.runOnce();

    expect(run.appended, 2);
    expect(run.autoApproved, 1);
    final approved = h.appended.where((r) => r.approved).single;
    expect(approved.candidate.category, 'Coffee');
    expect(h.appended.where((r) => !r.approved).single.candidate.amount, 24.42);
  });

  test('an unenrolled sender lands pending, never approved', () async {
    final h = _Harness(
      queue: [alert(coffee, sender: 'AlsalamBankk')],
      rules: const [
        KaiAutoConfirmRule(
          id: 'coffee',
          merchantContains: 'coffee bean',
          maxAmount: 5,
          direction: KaiCashImportDirection.expense,
        ),
      ],
    );
    final run = await h.pipeline.runOnce();
    expect(run.appended, 1, reason: 'kept — reading was never the risk');
    expect(h.appended.single.approved, isFalse);
  });

  test('two identical coffees on one day stay two rows', () async {
    // The case that rules out date+amount+merchant as an identity.
    final h = _Harness(queue: [alert(coffee), alert(coffeeAgain)]);
    final run = await h.pipeline.runOnce();
    expect(run.appended, 2);
    expect(run.duplicates, 0);
  });

  test('the same alert twice in one drain is one row', () async {
    final h = _Harness(queue: [alert(coffee), alert(coffee)]);
    final run = await h.pipeline.runOnce();
    expect(run.appended, 1);
    expect(run.duplicates, 1);
  });

  test('a redelivered drain does not double-post', () async {
    // Clear-on-read covers the phone side; this covers a drain that succeeded
    // there and failed on the way to storage.
    final h = _Harness(queue: [alert(coffee)]);
    await h.pipeline.runOnce();
    final second = await h.pipeline.runOnce();
    expect(h.appended, hasLength(1));
    expect(second.appended, 0);
    expect(second.duplicates, 1);
  });

  test('a failed drain is not an empty drain', () async {
    final h = _Harness(failDrain: true);
    final run = await h.pipeline.runOnce();
    expect(run.ok, isFalse);
    expect(run.failure, isNotNull);
    expect(h.appended, isEmpty);
  });

  test('an unreadable alert is counted with its reason', () async {
    final h = _Harness(queue: [
      alert('Your Al Salam Bank statement is ready'),
      {'sender': '', 'text': 'x', 'receivedAt': 1},
      alert(purchase),
    ]);
    final run = await h.pipeline.runOnce();
    expect(run.drained, 3);
    expect(run.appended, 1);
    expect(run.unreadable, 2);
    expect(run.reasons['no_amount_found'], 1);
    expect(run.reasons['malformed_alert'], 1);
  });

  test('an empty registry reads nothing, and says so to the phone', () async {
    final h = _Harness(
      queue: [alert(purchase)],
      sources: KaiLedgerSources(),
    );
    final run = await h.pipeline.runOnce();
    expect(h.pushed.single, isEmpty);
    expect(run.appended, 1, reason: 'parsed and kept');
    expect(h.appended.single.approved, isFalse, reason: 'but powerless');
  });

  test('the run summary carries counts, never message text', () async {
    final h = _Harness(queue: [alert(purchase)]);
    final json = (await h.pipeline.runOnce()).toJson().toString();
    expect(json, isNot(contains('FINE FOODS')));
    expect(json, isNot(contains('94150000')));
  });

  test('one append per run, so the ledger is never half-written', () async {
    var calls = 0;
    final pipeline = KaiLedgerPipeline(
      sources: enrolled(),
      rules: const [],
      pushSenders: (_) async {},
      drainAlerts: () async => [alert(coffee), alert(coffeeAgain), alert(purchase)],
      append: (_) async => calls++,
    );
    final run = await pipeline.runOnce();
    expect(run.appended, 3);
    expect(calls, 1);
  });
}
