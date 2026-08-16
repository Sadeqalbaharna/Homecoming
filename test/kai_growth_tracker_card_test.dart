import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_growth_tracker_service.dart';
import 'package:homecoming_app/widgets/kai_growth_tracker_card.dart';

KaiGrowthDay _day(
  String date, {
  double? instagram,
  double? tiktok,
  double? ads,
  double? google,
  double? sales,
}) =>
    KaiGrowthDay(
      date: DateTime.parse('${date}T00:00:00Z'),
      values: {
        KaiGrowthPlatform.instagram: instagram,
        KaiGrowthPlatform.tiktok: tiktok,
        KaiGrowthPlatform.ads: ads,
        KaiGrowthPlatform.google: google,
        KaiGrowthPlatform.sales: sales,
      },
    );

KaiGrowthSnapshot _snapshot({int days = 3}) =>
    KaiGrowthTrackerService.buildSnapshot(
      [
        _day(
          '2026-08-01',
          instagram: 100,
          tiktok: 10,
          ads: 40,
          google: 20,
          sales: 1000,
        ),
        _day(
          '2026-08-02',
          instagram: 200,
          tiktok: 20,
          ads: 80,
          google: 40,
          sales: 2000,
        ),
        _day(
          '2026-08-03',
          instagram: 300,
          tiktok: 30,
          ads: 120,
          google: 60,
          sales: 3000,
        ),
      ],
      days: days,
      loadedAt: DateTime.utc(2026, 8, 4),
    );

void main() {
  group('growth data contract', () {
    test('indexes every channel and sales against its own mean', () {
      final snapshot = _snapshot();

      expect(snapshot.series, hasLength(5));
      for (final line in snapshot.series) {
        expect(line.indexedValues, [50, 100, 150]);
      }
      expect(
        snapshot.series
            .singleWhere(
              (line) => line.platform == KaiGrowthPlatform.instagram,
            )
            .mean,
        200,
      );
      expect(
        snapshot.series
            .singleWhere(
              (line) => line.platform == KaiGrowthPlatform.sales,
            )
            .mean,
        2000,
      );
    });

    test('keeps missing days as gaps and never invents zero', () {
      final snapshot = KaiGrowthTrackerService.buildSnapshot(
        [
          _day('2026-08-01', instagram: 100, sales: 1000),
          _day('2026-08-03', instagram: 300, sales: 3000),
        ],
        days: 3,
      );

      final instagram = snapshot.series.singleWhere(
        (line) => line.platform == KaiGrowthPlatform.instagram,
      );
      final sales = snapshot.series.singleWhere(
        (line) => line.platform == KaiGrowthPlatform.sales,
      );
      expect(instagram.rawValues, [100, null, 300]);
      expect(instagram.indexedValues, [50, null, 150]);
      expect(sales.rawValues, [1000, null, 3000]);
    });

    test('parses the governed Firestore metrics without cross-channel totals',
        () {
      final day = KaiGrowthTrackerService.parseFirestoreDay({
        'name':
            'projects/x/databases/(default)/documents/reach_daily/2026-08-03',
        'fields': {
          'instagram': {
            'mapValue': {
              'fields': {
                'reach': {'integerValue': '240'},
              },
            },
          },
          'tiktok': {
            'mapValue': {
              'fields': {
                'views': {'doubleValue': 72.5},
              },
            },
          },
          'google': {
            'mapValue': {
              'fields': {
                'impressionsMaps': {'integerValue': '20'},
                'impressionsSearch': {'integerValue': '30'},
              },
            },
          },
        },
      });

      expect(day, isNotNull);
      expect(day!.values[KaiGrowthPlatform.instagram], 240);
      expect(day.values[KaiGrowthPlatform.tiktok], 72.5);
      expect(day.values[KaiGrowthPlatform.google], 50);
      expect(day.values[KaiGrowthPlatform.ads], isNull);
    });
  });

  testWidgets('card shows one combined graph and opens detail', (tester) async {
    final requested = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: KaiGrowthTrackerCard(
              loader: (days) async {
                requested.add(days);
                return _snapshot(days: 3);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, [28]);
    expect(find.byKey(const Key('growth-compact-chart')), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('Meta Ads'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kai-growth-tracker-card')));
    await tester.pumpAndSettle();

    expect(find.text('Growth detail'), findsOneWidget);
    expect(find.byKey(const Key('growth-detail-chart')), findsOneWidget);
    expect(find.textContaining('BD 3000.000'), findsOneWidget);
  });

  test('desktop right rails both include the Growth card', () {
    final source =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    expect('KaiGrowthTrackerCard'.allMatches(source), hasLength(2));
  });
}
