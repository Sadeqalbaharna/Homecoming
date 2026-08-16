import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_fitness_tracker_card.dart';
import 'package:homecoming_app/services/core/kai_whoop_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('version 1 daily record migrates without invented measurements', () {
    final value = KaiFitnessSnapshot.fromJson({
      'version': 1,
      'steps': 2500,
      'waterGlasses': 4,
      'sleepHours': 7.5,
      'workoutDone': true
    });
    expect(value?.steps, 2500);
    expect(value?.measurements, isEmpty);
    expect(value?.goals, isEmpty);
  });

  test('measurements and dated goals round-trip exactly', () {
    const original = KaiFitnessSnapshot(
      measurements: [
        KaiBodyMeasurement(
            date: '2026-08-11', weight: 80, waist: 90, rhr: 58, leanMass: 62)
      ],
      goals: [
        KaiFitnessGoal(
            metric: KaiBodyMetric.weight, target: 75, targetDate: '2026-12-31')
      ],
    );
    final restored =
        KaiFitnessSnapshot.fromJson(jsonDecode(jsonEncode(original.toJson())))!;
    expect(restored.latest?.weight, 80);
    expect(restored.latest?.waist, 90);
    expect(restored.latest?.rhr, 58);
    expect(restored.latest?.leanMass, 62);
    expect(restored.goalFor(KaiBodyMetric.weight)?.target, 75);
    expect(restored.goalFor(KaiBodyMetric.weight)?.targetDate, '2026-12-31');
  });

  test(
      'WHOOP authorization is read-only, offline, and uses the registered callback',
      () {
    final uri = KaiWhoopService()
        .authorizationUri(clientId: 'desktop-client', state: 'Ab12Cd34');
    expect(uri.scheme, 'https');
    expect(uri.host, 'api.prod.whoop.com');
    expect(uri.queryParameters['redirect_uri'], kaiWhoopRedirectUri);
    expect(uri.queryParameters['state'], 'Ab12Cd34');
    expect(uri.queryParameters['scope'], contains('offline'));
    expect(uri.queryParameters['scope'], contains('read:body_measurement'));
    expect(uri.queryParameters['scope'], contains('read:recovery'));
    expect(uri.queryParameters['scope'], isNot(contains('write')));
    expect(uri.toString(), isNot(contains('secret')));
  });

  test('WHOOP browser handoff never observes a detached process exit code', () {
    final source =
        File('lib/services/core/kai_whoop_service.dart').readAsStringSync();
    expect(source, contains('mode: ProcessStartMode.detached'));
    expect(source, isNot(contains('launch.exitCode')));
    expect(source, contains("'rundll32.exe'"));
    expect(source, contains("'url.dll,FileProtocolHandler'"));
    expect(source, isNot(contains("Process.start('explorer.exe'")));
  });

  test('WHOOP parser maps health fields without inventing absent values', () {
    final value = KaiWhoopService.parseHealthSnapshot(
      syncedAt: DateTime.utc(2026, 8, 12, 8),
      body: {'weight_kilogram': 82.4},
      recoveryCollection: {
        'records': [
          {
            'score': {
              'recovery_score': 71,
              'resting_heart_rate': 52,
              'hrv_rmssd_milli': 48.5
            }
          }
        ]
      },
      cycleCollection: {
        'records': [
          {
            'score': {'strain': 10.2}
          }
        ]
      },
      sleepCollection: {
        'records': [
          {
            'score': {
              'sleep_performance_percentage': 88,
              'stage_summary': {
                'total_light_sleep_time_milli': 14400000,
                'total_slow_wave_sleep_time_milli': 5400000,
                'total_rem_sleep_time_milli': 5400000,
              }
            }
          }
        ]
      },
      workoutCollection: {
        'records': [
          {'id': 'workout'}
        ]
      },
    );
    expect(value.weightKg, 82.4);
    expect(value.restingHeartRate, 52);
    expect(value.hrvMs, 48.5);
    expect(value.recoveryScore, 71);
    expect(value.dayStrain, 10.2);
    expect(value.sleepHours, 7);
    expect(value.sleepPerformance, 88);
    expect(value.workoutToday, isTrue);
  });

  test('WHOOP snapshot and source provenance round-trip without tokens', () {
    const measurement = KaiBodyMeasurement(
        date: '2026-08-12', weight: 82, rhr: 52, source: 'whoop');
    final original = KaiFitnessSnapshot(
      measurements: const [measurement],
      whoop: KaiWhoopHealthSnapshot(
          syncedAt: DateTime.utc(2026, 8, 12), recoveryScore: 70),
    );
    final encoded = jsonEncode(original.toJson());
    final restored = KaiFitnessSnapshot.fromJson(jsonDecode(encoded))!;
    expect(restored.measurements.single.source, 'whoop');
    expect(restored.whoop?.recoveryScore, 70);
    expect(encoded, isNot(contains('access_token')));
    expect(encoded, isNot(contains('client_secret')));
  });

  testWidgets('card exposes all metrics graph and dedicated edit page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(455, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            backgroundColor: Color(0xFF070B12),
            body: Padding(
                padding: EdgeInsets.all(8), child: KaiFitnessTrackerCard()))));
    await tester.pumpAndSettle();
    expect(find.text('PROJECT LIONHEART'), findsOneWidget);
    expect(find.text('FITNESS'), findsNothing);
    expect(find.byKey(const Key('fitness-history-chart')), findsOneWidget);
    for (final metric in KaiBodyMetric.values) {
      expect(find.byKey(Key('fitness-metric-${metric.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('fitness-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Project Lionheart'), findsOneWidget);
    expect(find.text('Fitness tracker'), findsNothing);
    expect(find.text('WHOOP CONNECTION'), findsOneWidget);
    expect(find.byKey(const Key('fitness-whoop-redirect')), findsOneWidget);
    expect(
        find.byKey(const Key('fitness-whoop-client-secret')), findsOneWidget);
    expect(
        find.text('ADD BODY MEASUREMENT', skipOffstage: false), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('fitness-edit-scroll')), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('TARGET GOALS + DATES'), findsOneWidget);
    expect(find.byKey(const Key('fitness-goal-rhr'), skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const Key('fitness-goal-leanMass'), skipOffstage: false),
        findsOneWidget);
    await tester.drag(
        find.byKey(const Key('fitness-edit-scroll')), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(
        find.text('MEASUREMENT HISTORY', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
