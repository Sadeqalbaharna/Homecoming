import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_growth_tracker_service.dart';
import 'package:homecoming_app/widgets/kai_growth_tracker_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    test('parses only explicit Tavern ledger sales from the synced venue blob',
        () {
      final rows = KaiGrowthTrackerService.parseTavernBook(jsonEncode({
        'ledger': {
          'days': {
            '2026-08-01': {'sales': 1200},
            '2026-08-02': {'sales': 0},
            '2026-08-03': {'sales': 1800},
            'bad-date': {'sales': 9999},
          },
        },
      }));

      expect(rows, hasLength(2));
      expect(
          rows.map((row) => row.values[KaiGrowthPlatform.sales]), [1200, 1800]);
      expect(
          rows.every((row) => row.values[KaiGrowthPlatform.instagram] == null),
          isTrue);
    });

    test('loads venue-scoped Hoard sales reports through the Google session',
        () async {
      late http.Request request;
      final service = KaiGrowthTrackerService(
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode({
              'documents': [
                {
                  'fields': {
                    'date': {'stringValue': '2026-08-01'},
                    'revenue': {'doubleValue': 1200},
                  },
                },
                {
                  'fields': {
                    'date': {'stringValue': '2026-08-03'},
                    'revenue': {'doubleValue': 1800},
                  },
                },
              ],
            }),
            200,
          );
        }),
        sessionProvider: () async => const TavernGrowthSession(
          idToken: 'google-token',
          email: 'staff@example.com',
          orgId: 'org-1',
          venueId: 'venue-main',
        ),
      );

      final snapshot = await service.load(days: 3);

      expect(request.url.path,
          endsWith('/documents/orgs/org-1/venues/venue-main/salesLines'));
      expect(request.headers['Authorization'], 'Bearer google-token');
      expect(snapshot.series, hasLength(1));
      expect(snapshot.series.single.platform, KaiGrowthPlatform.sales);
      expect(snapshot.series.single.rawValues, [1200, null, 1800]);
    });

    test('merges every social tracker with venue-scoped sales by trading day',
        () async {
      final service = KaiGrowthTrackerService(
        client: MockClient((request) async {
          if (request.url.path.contains('/reach_daily')) {
            return http.Response(
              jsonEncode({
                'documents': [
                  {
                    'name': 'documents/reach_daily/2026-08-01',
                    'fields': {
                      'date': {'stringValue': '2026-08-01'},
                      'instagram': {
                        'mapValue': {
                          'fields': {
                            'reach': {'integerValue': '100'},
                          },
                        },
                      },
                    },
                  },
                  {
                    'name': 'documents/reach_daily/2026-08-02',
                    'fields': {
                      'date': {'stringValue': '2026-08-02'},
                      'instagram': {
                        'mapValue': {
                          'fields': {
                            'reach': {'integerValue': '200'},
                          },
                        },
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'documents': [
                {
                  'fields': {
                    'date': {'stringValue': '2026-08-01'},
                    'revenue': {'doubleValue': 900},
                  },
                },
                {
                  'fields': {
                    'date': {'stringValue': '2026-08-02'},
                    'revenue': {'doubleValue': 1100},
                  },
                },
              ],
            }),
            200,
          );
        }),
        tokenProvider: () async => 'social-token',
        sessionProvider: () async => const TavernGrowthSession(
          idToken: 'sales-token',
          email: 'owner@example.com',
          orgId: 'org-1',
          venueId: 'main',
        ),
      );

      final snapshot = await service.load(days: 2);

      expect(snapshot.socialConnected, isTrue);
      expect(snapshot.salesConnected, isTrue);
      expect(
        snapshot.series.map((series) => series.platform),
        [KaiGrowthPlatform.instagram, KaiGrowthPlatform.sales],
      );
      expect(snapshot.series.first.rawValues, [100, 200]);
      expect(snapshot.series.last.rawValues, [900, 1100]);
    });
  });

  group('Tavern HTTPS identity bridge', () {
    test('Windows Google sign-in uses a one-use loopback browser handoff', () {
      final source = File('lib/services/core/kai_growth_tracker_service.dart')
          .readAsStringSync();

      expect(
          source, contains('HttpServer.bind(InternetAddress.loopbackIPv4, 0)'));
      expect(source, contains("'http://localhost:\${server.port}/'"));
      expect(source, contains("receivedState != state"));
      expect(source, contains('inMemoryPersistence'));
      expect(source, contains('signInWithPopup'));
      expect(source, contains("script-src 'nonce-\$state'"));
      expect(source, contains("connect-src 'self'"));
      expect(source, contains('https://apis.google.com'));
      expect(source, contains('script type="module" nonce="\$state"'));
      expect(source, contains("mode: ProcessStartMode.detached"));
      expect(source, isNot(contains('signInWithProvider')));
      expect(source, isNot(contains('signInWithRedirect')));
      expect(source, isNot(contains('browserSessionPersistence')));
      expect(
          source, isNot(contains("package:firebase_auth/firebase_auth.dart")));
    });

    test('signs in, verifies staff role, and retains only the session token',
        () async {
      final requests = <http.Request>[];
      final connection = TavernGrowthConnection.withClient(
        MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'identitytoolkit.googleapis.com') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body, {
              'email': 'staff@example.com',
              'password': 'one-use-password',
              'returnSecureToken': true,
            });
            return http.Response(
              jsonEncode({
                'idToken': 'tavern-id-token',
                'refreshToken': 'tavern-refresh-token',
                'localId': 'staff-uid',
                'expiresIn': '3600',
              }),
              200,
            );
          }
          expect(request.url.path, contains('/documents/users/staff-uid'));
          expect(request.headers['Authorization'], 'Bearer tavern-id-token');
          return http.Response(
            jsonEncode({
              'fields': {
                'role': {'stringValue': 'staff'},
              },
            }),
            200,
          );
        }),
      );

      await connection.connect(' staff@example.com ', 'one-use-password');

      expect(await connection.idToken(), 'tavern-id-token');
      expect(await connection.isConnected, isTrue);
      expect(requests, hasLength(2));
    });

    test('maps rejected credentials without exposing the provider response',
        () async {
      final connection = TavernGrowthConnection.withClient(
        MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'message': 'INVALID_LOGIN_CREDENTIALS'},
              }),
              400,
            )),
      );

      await expectLater(
        connection.connect('staff@example.com', 'wrong'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The Tavern email or password is incorrect.',
          ),
        ),
      );
      expect(await connection.idToken(), isNull);
    });

    test('requests a Firebase reset email without accepting a password',
        () async {
      late http.Request request;
      final connection = TavernGrowthConnection.withClient(
        MockClient((value) async {
          request = value;
          return http.Response(jsonEncode({'email': 'staff@example.com'}), 200);
        }),
      );

      await connection.sendPasswordReset(' staff@example.com ');

      expect(request.url.path, contains('/accounts:sendOobCode'));
      expect(jsonDecode(request.body), {
        'requestType': 'PASSWORD_RESET',
        'email': 'staff@example.com',
      });
      expect(request.body, isNot(contains('password')));
    });

    test('Google identity resolves the same Tavern org and venue read-only',
        () async {
      final requests = <http.Request>[];
      final connection = TavernGrowthConnection.withClient(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/documents/users/google-uid')) {
            return http.Response(
                jsonEncode({
                  'fields': {
                    'org': {'stringValue': 'org-1'},
                    'role': {'stringValue': 'owner'},
                  },
                }),
                200);
          }
          expect(request.url.path, endsWith('/documents/orgs/org-1'));
          return http.Response(
              jsonEncode({
                'fields': {
                  'members': {
                    'mapValue': {
                      'fields': {
                        'google-uid': {'stringValue': 'owner'},
                      },
                    },
                  },
                },
              }),
              200);
        }),
        googleIdentityProvider: () async => const TavernGoogleIdentity(
          uid: 'google-uid',
          email: 'staff@example.com',
          idToken: 'google-id-token',
        ),
      );

      await connection.connectWithGoogle();
      final session = await connection.cloudSession();

      expect(session?.email, 'staff@example.com');
      expect(session?.orgId, 'org-1');
      expect(session?.venueId, 'main');
      expect(requests, hasLength(2));
      expect(
          requests.every(
              (r) => r.headers['Authorization'] == 'Bearer google-id-token'),
          isTrue);
    });

    test('refuses a valid identity without staff or admin role', () async {
      final connection = TavernGrowthConnection.withClient(
        MockClient((request) async {
          if (request.url.host == 'identitytoolkit.googleapis.com') {
            return http.Response(
              jsonEncode({
                'idToken': 'customer-token',
                'refreshToken': 'customer-refresh',
                'localId': 'customer-uid',
                'expiresIn': '3600',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'fields': {
                'role': {'stringValue': 'customer'},
              },
            }),
            200,
          );
        }),
      );

      await expectLater(
        connection.connect('customer@example.com', 'valid'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'This Tavern account does not have staff access.',
          ),
        ),
      );
      expect(await connection.idToken(), isNull);
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

  testWidgets('card always lists every tracker and labels missing sources',
      (tester) async {
    final partial = KaiGrowthTrackerService.buildSnapshot(
      [
        _day('2026-08-01', instagram: 100),
        _day('2026-08-02', instagram: 200),
      ],
      days: 2,
      socialConnected: true,
      salesConnected: false,
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: KaiGrowthTrackerCard(loader: (_) async => partial),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('TikTok · no data'), findsOneWidget);
    expect(find.text('Meta Ads · no data'), findsOneWidget);
    expect(find.text('Google · no data'), findsOneWidget);
    expect(find.text('Sales · no data'), findsOneWidget);
    expect(find.text('Connect sales reports'), findsOneWidget);
  });

  testWidgets('access failure opens the real Tavern connection flow',
      (tester) async {
    var attempts = 0;
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: KaiGrowthTrackerCard(
              loader: (_) async {
                loads++;
                if (loads == 1) {
                  throw StateError(
                    'Tavern Growth access is not linked to Homecoming.',
                  );
                }
                return _snapshot();
              },
              googleConnector: () async => attempts++,
              socialConnector: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Tavern'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Connect Tavern'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('tavern-growth-connect-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('growth-connect-sales')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tavern-growth-connect-submit')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(loads, 2);
    expect(find.byKey(const Key('growth-compact-chart')), findsOneWidget);
  });

  testWidgets('failed Google sign-in stays fail closed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: KaiGrowthTrackerCard(
              loader: (_) async => throw StateError(
                'Tavern Growth access is not linked to Homecoming.',
              ),
              googleConnector: () async =>
                  throw StateError('Google sign-in was cancelled.'),
              socialConnector: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Tavern'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('growth-connect-sales')));
    await tester.pumpAndSettle();

    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('connection dialog separates Hoard sales and Tavern social',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 380,
          child: KaiGrowthTrackerCard(
            loader: (_) async => throw StateError(
              'Tavern Growth access is not linked to Homecoming.',
            ),
            googleConnector: () async {},
            socialConnector: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Tavern'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Hoard sales'), findsOneWidget);
    expect(find.text('Connect social trackers'), findsOneWidget);
    expect(find.byKey(const Key('growth-social-email')), findsOneWidget);
    expect(find.byKey(const Key('growth-social-password')), findsOneWidget);
    final password = tester.widget<TextField>(
      find.byKey(const Key('growth-social-password')),
    );
    expect(password.obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stalled Hoard sign-in never traps the connection dialog',
      (tester) async {
    final pendingGoogle = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 380,
          child: KaiGrowthTrackerCard(
            loader: (_) async => throw StateError(
              'Tavern Growth access is not linked to Homecoming.',
            ),
            googleConnector: () => pendingGoogle.future,
            socialConnector: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Tavern'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('growth-connect-sales')));
    await tester.pump();

    final cancel = tester.widget<TextButton>(
      find.byKey(const Key('growth-connect-cancel')),
    );
    expect(cancel.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('growth-connect-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tavern-growth-connect-dialog')), findsNothing);
  });

  test('desktop rightmost status rail includes one Growth card', () {
    final source =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    expect('KaiGrowthTrackerCard'.allMatches(source), hasLength(1));
    expect(
      source.indexOf('KaiGrowthTrackerCard'),
      greaterThan(source.indexOf('KaiStatusCard(')),
    );
  });
}
