// The one place that starts the ledger pipeline.
//
// Everything below it was built and tested in isolation and had no caller —
// which meant a perfect build would have done nothing at all: no enrolment
// pushed, no queue drained. This is that caller, and the platform channel is
// injected so all of it runs without a phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/capture_health.dart';
import 'package:homecoming_app/logic/ledger_ingest.dart';
import 'package:homecoming_app/logic/ledger_sources.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';
import 'package:homecoming_app/services/core/kai_ledger_bootstrap.dart';
import 'package:homecoming_app/services/core/kai_ledger_pipeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

const purchase =
    'BHD 24.420 debited from Acc. XXX94150000 at FINE FOODS - MINA SALMMANAMA '
    'BH.Bal: BHD 354.620 on 11/08/26 at 11:16. Tel 17005500';

class FakePlatform {
  FakePlatform({
    this.alerts = const [],
    this.health = const {},
    this.repair = const {},
  });

  List<Map<String, Object?>> alerts;
  Map<String, Object?> health;
  Map<String, Object?> repair;

  final List<String> calls = [];
  List<String>? pushedSenders;

  Future<Object?> invoke(String method, [Map<String, Object?>? args]) async {
    calls.add(method);
    switch (method) {
      case 'setBankSenders':
        pushedSenders = (args?['senders'] as List?)?.cast<String>();
        return pushedSenders?.length;
      case 'drainBankAlerts':
        return alerts;
      case 'captureHealth':
        return health;
      case 'repairCapture':
        return repair;
    }
    return null;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  KaiLedgerBootstrap bootstrapFor(FakePlatform p, List<KaiLedgerRow> sink) =>
      KaiLedgerBootstrap(
        invoke: p.invoke,
        appendRows: (rows) async => sink.addAll(rows),
      );

  group('the senders Sadeq named are recorded, once', () {
    test('a first run seeds Alsalambank and Credimax', () async {
      final p = FakePlatform();
      final sources = await bootstrapFor(p, []).loadSources();
      expect(sources.smsFilter, ['ALSALAMBANK', 'CREDIMAX']);
    });

    test('removing a sender is not undone by a restart', () async {
      // A revocation that a restart reverses is not a revocation.
      final p = FakePlatform();
      final boot = bootstrapFor(p, []);
      final sources = await boot.loadSources();
      sources.remove(KaiLedgerChannel.sms, 'Credimax');
      await boot.saveSources(sources);

      final reloaded = await bootstrapFor(FakePlatform(), []).loadSources();
      expect(reloaded.smsFilter, ['ALSALAMBANK']);
    });

    test('a corrupt registry fails to empty, not to re-seeded', () async {
      // Re-seeding would silently restore a sender that was deliberately
      // removed; an empty registry reads nothing and the health check reports
      // it. Both are bad, but only one is invisible.
      SharedPreferences.setMockInitialValues({
        'kai_ledger_sources_v1': 'not json at all',
      });
      final sources = await bootstrapFor(FakePlatform(), []).loadSources();
      expect(sources.isEmpty, isTrue);
    });
  });

  group('one pass', () {
    test('pushes the filter, drains, and appends', () async {
      final rows = <KaiLedgerRow>[];
      final p = FakePlatform(alerts: [
        {
          'sender': 'Alsalambank',
          'text': purchase,
          'receivedAt': DateTime(2026, 8, 11, 11, 16).millisecondsSinceEpoch,
        }
      ]);

      final run = await bootstrapFor(p, rows).run();

      expect(p.calls, containsAllInOrder(['setBankSenders', 'drainBankAlerts']));
      expect(p.pushedSenders, ['ALSALAMBANK', 'CREDIMAX']);
      expect(run.ok, isTrue);
      expect(run.appended, 1);
      expect(rows.single.candidate.amount, 24.42);
      expect(rows.single.approved, isFalse, reason: 'no rule, so it waits');
      expect(rows.single.balance!.balance, 354.620);
    });

    test('a rule Sadeq wrote approves it', () async {
      final rows = <KaiLedgerRow>[];
      final p = FakePlatform(alerts: [
        {
          'sender': 'Alsalambank',
          'text': purchase,
          'receivedAt': DateTime(2026, 8, 11, 11, 16).millisecondsSinceEpoch,
        }
      ]);
      await bootstrapFor(p, rows).run(rules: const [
        KaiAutoConfirmRule(
          id: 'groceries',
          merchantContains: 'fine foods',
          maxAmount: 50,
          direction: KaiCashImportDirection.expense,
          category: 'Groceries',
        ),
      ]);
      expect(rows.single.approved, isTrue);
      expect(rows.single.candidate.category, 'Groceries');
    });

    test('an empty queue is a harmless no-op', () async {
      final rows = <KaiLedgerRow>[];
      final run = await bootstrapFor(FakePlatform(), rows).run();
      expect(run.ok, isTrue);
      expect(run.appended, 0);
      expect(rows, isEmpty);
    });

    test('a platform that answers with nothing does not crash', () async {
      final rows = <KaiLedgerRow>[];
      final p = FakePlatform();
      p.alerts = const [];
      final run = await bootstrapFor(p, rows).run();
      expect(run.ok, isTrue);
    });
  });

  group('health', () {
    test('a live listener needs no repair, and is not churned', () async {
      final p = FakePlatform(health: {
        'accessGranted': true,
        'listenerConnected': true,
        'lastAnyNotification':
            DateTime.now().subtract(const Duration(minutes: 3))
                .millisecondsSinceEpoch,
        'queued': 0,
      });
      final report = await bootstrapFor(p, []).checkHealth();
      expect(report.health.ok, isTrue);
      expect(report.repairs, isEmpty);
      expect(p.calls, isNot(contains('repairCapture')),
          reason: 'rebinding a healthy listener is churn in a recovery path');
    });

    test('a dead listener is repaired and the causes are named', () async {
      final p = FakePlatform(
        health: {
          'accessGranted': true,
          'listenerConnected': false,
          'lastAnyNotification': DateTime.now()
              .subtract(const Duration(hours: 20))
              .millisecondsSinceEpoch,
          'queued': 3,
        },
        repair: {
          'accessGranted': true,
          'rebindRequested': true,
          'batteryExempt': false,
          'autoRevokeExempt': true,
        },
      );
      final report = await bootstrapFor(p, []).checkHealth();
      expect(report.health.state, KaiCaptureState.listenerDisconnected);
      expect(report.repairs, [
        KaiCaptureRepair.exemptFromBatteryOptimisation,
        KaiCaptureRepair.rebindRequested,
      ]);
      expect(report.needsSadeq, isTrue);
    });

    test('a rebind alone does not need Sadeq', () async {
      final p = FakePlatform(
        health: {
          'accessGranted': true,
          'listenerConnected': false,
          'lastAnyNotification':
              DateTime.now().millisecondsSinceEpoch,
        },
        repair: {
          'accessGranted': true,
          'rebindRequested': true,
          'batteryExempt': true,
          'autoRevokeExempt': true,
        },
      );
      final report = await bootstrapFor(p, []).checkHealth();
      expect(report.repairs, [KaiCaptureRepair.rebindRequested]);
      expect(report.needsSadeq, isFalse,
          reason: 'Kai fixed it himself; interrupting would be noise');
    });

    test('a fresh install is quiet', () async {
      final p = FakePlatform(health: {
        'accessGranted': true,
        'listenerConnected': true,
      });
      final report = await bootstrapFor(p, []).checkHealth();
      expect(report.health.state, KaiCaptureState.neverStarted);
      expect(report.repairs, isEmpty);
      expect(p.calls, isNot(contains('repairCapture')));
    });
  });
}
