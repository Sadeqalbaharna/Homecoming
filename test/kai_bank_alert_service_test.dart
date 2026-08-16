// Draining the phone's bank-alert queue into the ledger.
//
// The Android half catches and keeps; it deliberately does not interpret. All
// the deciding happens here, which is why this can be tested without a phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_ingest.dart';
import 'package:homecoming_app/services/core/kai_bank_alert_service.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';

final at = DateTime(2026, 8, 16, 14, 30);

Map<String, Object?> rawAlert(
  String text, {
  String sender = 'NBB',
  DateTime? when,
}) =>
    {
      'sender': sender,
      'text': text,
      'receivedAt': (when ?? at).millisecondsSinceEpoch,
    };

const coffee = KaiAutoConfirmRule(
  id: 'coffee',
  merchantContains: 'talabat',
  maxAmount: 20,
  direction: KaiCashImportDirection.expense,
  category: 'Food',
);

class AlertSink {
  final confirmed = <KaiCashImportCandidate>[];
  final pending = <KaiCashImportCandidate>[];

  Future<void> call(KaiCashImportCandidate c, bool wasConfirmed) async {
    (wasConfirmed ? confirmed : pending).add(c);
  }
}

KaiBankAlertService serviceFor(
  List<Map<String, Object?>> alerts, {
  AlertSink? sink,
  List<KaiAutoConfirmRule> rules = const [coffee],
  Future<List<Map<String, Object?>>> Function()? drain,
}) {
  final s = sink ?? AlertSink();
  return KaiBankAlertService(
    ingest: KaiLedgerIngest(trustedSenders: const {'NBB'}, rules: rules),
    drainAlerts: drain ?? () async => alerts,
    onCandidate: s.call,
  );
}

void main() {
  test('a matching alert lands confirmed, a stranger lands pending', () async {
    final sink = AlertSink();
    final result = await serviceFor([
      rawAlert('BHD 5.000 spent at TALABAT'),
      rawAlert('BHD 5.000 spent at TALABAT', sender: 'scammer'),
    ], sink: sink).drainOnce();

    expect(result.seen, 2);
    expect(result.confirmed, 1);
    expect(result.pending, 1);
    expect(sink.confirmed.single.selected, isTrue);
    expect(sink.pending.single.selected, isFalse);
  });

  test('a pending row still reaches the ledger', () async {
    // Dropping it would make an incomplete ledger look complete, which is the
    // failure mode this whole feature exists to avoid.
    final sink = AlertSink();
    await serviceFor([
      rawAlert('BHD 250.000 spent at TALABAT'),
    ], sink: sink).drainOnce();
    expect(sink.pending, hasLength(1));
    expect(sink.pending.single.amount, 250.0);
  });

  test('the same alert twice yields one row', () async {
    final sink = AlertSink();
    final result = await serviceFor([
      rawAlert('BHD 9.000 spent at LULU'),
      rawAlert('BHD 9.000 spent at LULU'),
    ], sink: sink).drainOnce();
    expect(sink.pending, hasLength(1));
    expect(result.reasons['duplicate'], 1);
  });

  test('a failed drain is not an empty drain', () async {
    // Saying "0 alerts" when the queue is still sitting on the phone is a lie
    // that looks like good news.
    final result = await serviceFor(
      const [],
      drain: () async => throw StateError('no notification access'),
    ).drainOnce();
    expect(result.seen, 0);
    expect(result.reasons['drain_failed'], 1);
  });

  test('malformed rows are counted, never silently skipped', () async {
    final result = await serviceFor([
      {'sender': '', 'text': 'BHD 1.000 spent at X', 'receivedAt': 1},
      {'sender': 'NBB', 'text': '   ', 'receivedAt': 1},
      {'sender': 'NBB', 'text': 'BHD 1.000 spent at X'},
      rawAlert('BHD 4.000 spent at TALABAT'),
    ]).drainOnce();

    expect(result.seen, 4);
    expect(result.unparsed, 3);
    expect(result.reasons['malformed_alert'], 3);
    expect(result.confirmed, 1);
  });

  test('an unreadable alert is reported with its reason', () async {
    final result =
        await serviceFor([rawAlert('Your statement is ready')]).drainOnce();
    expect(result.unparsed, 1);
    expect(result.reasons['no_amount_found'], 1);
  });

  test('the summary carries counts and reasons, never message text', () async {
    final result = await serviceFor([
      rawAlert('BHD 5.000 spent at TALABAT'),
      rawAlert('BHD 99.000 spent at SOMEWHERE PRIVATE'),
    ]).drainOnce();

    final encoded = result.toJson().toString();
    expect(encoded, isNot(contains('TALABAT')));
    expect(encoded, isNot(contains('SOMEWHERE PRIVATE')));
    expect(result.toJson().keys.toSet(),
        {'seen', 'confirmed', 'pending', 'unparsed', 'reasons'});
  });

  test('a second drain does not re-deliver what already landed', () async {
    // Clear-on-read covers the normal case; this covers the one it cannot —
    // a drain that succeeded on the phone and failed on the way to storage.
    final sink = AlertSink();
    final alerts = [rawAlert('BHD 5.000 spent at TALABAT')];
    final service = serviceFor(alerts, sink: sink);
    await service.drainOnce();
    final second = await service.drainOnce();
    expect(sink.confirmed, hasLength(1));
    expect(second.reasons['duplicate'], 1);
  });
}
