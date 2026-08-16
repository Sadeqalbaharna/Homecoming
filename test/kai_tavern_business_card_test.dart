import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_fitness_tracker_card.dart';
import 'package:homecoming_app/widgets/kai_personal_cash_card.dart';
import 'package:homecoming_app/widgets/kai_tavern_business_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty tracker never invents Tavern revenue', () {
    const value = KaiTavernBusinessSnapshot();
    expect(value.latest, isNull);
    expect(value.periods, isEmpty);
    expect(value.revenueTarget, 0);
  });

  test('business metrics reconcile from one monthly source record', () {
    const month = KaiTavernPeriod(
      period: '2026-08',
      grossSales: 11000,
      discounts: 200,
      refunds: 100,
      cogs: 3000,
      labor: 2500,
      rent: 1000,
      utilities: 300,
      marketing: 400,
      deliveryFees: 500,
      otherExpenses: 200,
      taxes: 280,
      cash: 6000,
      receivables: 700,
      payables: 900,
      inventory: 1200,
      orders: 500,
      customers: 400,
      repeatCustomers: 160,
      covers: 1200,
      capacityCovers: 60,
      openingDays: 25,
    );

    expect(month.netSales, 10700);
    expect(month.grossProfit, 7700);
    expect(month.operatingExpenses, 4900);
    expect(month.operatingProfit, 2800);
    expect(month.netProfit, 2520);
    expect(month.averageOrderValue, 21.4);
    expect(month.repeatRate, 0.4);
    expect(month.occupancy, 0.8);
    expect(month.workingCapital, 7000);
    expect(month.breakEvenSales, closeTo(6538.889, 0.01));
  });

  test('monthly records goals and source references round-trip', () {
    const original = KaiTavernBusinessSnapshot(
      periods: [
        KaiTavernPeriod(
            period: '2026-08', grossSales: 11000, sourceNote: 'POS close 31')
      ],
      revenueTarget: 12000,
      profitTarget: 2500,
      cashBufferTarget: 5000,
      goalDate: '2026-12-31',
    );
    final restored = KaiTavernBusinessSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())))!;
    expect(restored.latest?.grossSales, 11000);
    expect(restored.latest?.sourceNote, 'POS close 31');
    expect(restored.revenueTarget, 12000);
    expect(restored.goalDate, '2026-12-31');
  });

  test('desktop stacks cash fitness and Tavern in one right dock column', () {
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final cash = shell.indexOf('Expanded(child: KaiPersonalCashDock())');
    final fitness = shell.indexOf('Expanded(child: KaiFitnessTrackerCard())');
    final tavern = shell.indexOf('Expanded(child: KaiTavernBusinessCard())');
    expect(cash, greaterThan(0));
    expect(fitness, greaterThan(cash));
    expect(tavern, greaterThan(fitness));
    expect(
        shell, contains("import '../widgets/kai_tavern_business_card.dart';"));
  });

  testWidgets('card and robust edit page expose the governed business model',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(455, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            backgroundColor: Color(0xFF070B12),
            body: Padding(
                padding: EdgeInsets.all(8), child: KaiTavernBusinessCard()))));
    await tester.pumpAndSettle();

    expect(find.text('TAVERN'), findsOneWidget);
    expect(find.textContaining('NO BUSINESS FIGURES ENTERED'), findsOneWidget);
    expect(find.byKey(const Key('tavern-history-chart')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tavern-edit')));
    await tester.pumpAndSettle();

    Future<void> reveal(Finder target) async {
      for (var attempt = 0;
          attempt < 10 && target.evaluate().isEmpty;
          attempt++) {
        await tester.drag(
            find.byKey(const Key('tavern-edit-scroll')), const Offset(0, -550));
        await tester.pumpAndSettle();
      }
      expect(target, findsOneWidget);
    }

    expect(find.text('Tavern business tracker'), findsOneWidget);
    expect(find.text('SALES + DEDUCTIONS'), findsOneWidget);
    await reveal(find.text('COSTS + PROFIT DRIVERS'));
    await reveal(find.text('CASH + BALANCE SHEET'));
    await reveal(find.text('CUSTOMERS + OPERATIONS'));
    await reveal(find.byKey(const Key('tavern-profit-target')));
    await reveal(find.text('AUTOMATIC BUSINESS METRICS'));
    await reveal(find.text('MONTHLY HISTORY'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three-card right dock remains overflow free',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(455, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF070B12),
        body: Padding(
          padding: EdgeInsets.all(8),
          child: Column(children: [
            Expanded(child: KaiPersonalCashDock()),
            SizedBox(height: 10),
            Expanded(child: KaiFitnessTrackerCard()),
            SizedBox(height: 10),
            Expanded(child: KaiTavernBusinessCard()),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('personal-cash-dock')), findsOneWidget);
    expect(find.byKey(const Key('fitness-tracker-card')), findsOneWidget);
    expect(find.byKey(const Key('tavern-business-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
