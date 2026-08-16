import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

enum KaiGrowthPlatform { instagram, tiktok, ads, google, sales }

extension KaiGrowthPlatformLabel on KaiGrowthPlatform {
  String get label => switch (this) {
        KaiGrowthPlatform.instagram => 'Instagram',
        KaiGrowthPlatform.tiktok => 'TikTok',
        KaiGrowthPlatform.ads => 'Meta Ads',
        KaiGrowthPlatform.google => 'Google',
        KaiGrowthPlatform.sales => 'Sales',
      };

  String get unit => switch (this) {
        KaiGrowthPlatform.instagram => 'people reached',
        KaiGrowthPlatform.tiktok => 'video views',
        KaiGrowthPlatform.ads => 'people reached',
        KaiGrowthPlatform.google => 'searches & map views',
        KaiGrowthPlatform.sales => 'BHD revenue',
      };
}

class KaiGrowthDay {
  const KaiGrowthDay({required this.date, required this.values});

  final DateTime date;
  final Map<KaiGrowthPlatform, double?> values;
}

class KaiGrowthSeries {
  const KaiGrowthSeries({
    required this.platform,
    required this.rawValues,
    required this.indexedValues,
    required this.mean,
    required this.reportedDays,
  });

  final KaiGrowthPlatform platform;
  final List<double?> rawValues;
  final List<double?> indexedValues;
  final double mean;
  final int reportedDays;

  double? get latest {
    for (var i = rawValues.length - 1; i >= 0; i--) {
      if (rawValues[i] != null) return rawValues[i];
    }
    return null;
  }
}

class KaiGrowthSnapshot {
  const KaiGrowthSnapshot({
    required this.dates,
    required this.series,
    required this.loadedAt,
    this.socialConnected = false,
    this.salesConnected = false,
  });

  final List<DateTime> dates;
  final List<KaiGrowthSeries> series;
  final DateTime loadedAt;
  final bool socialConnected;
  final bool salesConnected;

  bool get hasChartData => series.isNotEmpty;
}

typedef KaiGrowthTokenProvider = Future<String?> Function();

class TavernGoogleIdentity {
  const TavernGoogleIdentity({
    required this.uid,
    required this.email,
    required this.idToken,
    this.refresh,
  });

  final String uid;
  final String email;
  final String idToken;
  final Future<String?> Function()? refresh;
}

class TavernGrowthSession {
  const TavernGrowthSession({
    required this.idToken,
    required this.email,
    required this.orgId,
    required this.venueId,
  });

  final String idToken;
  final String email;
  final String orgId;
  final String venueId;
}

typedef TavernGoogleIdentityProvider = Future<TavernGoogleIdentity> Function();

/// One in-memory Tavern staff session for read-only Growth data.
///
/// Google authentication happens in the user's normal browser. The resulting
/// Firebase ID token returns over a one-use loopback callback; Homecoming never
/// asks for, receives, stores, or logs a Google password or refresh token.
class TavernGrowthConnection {
  TavernGrowthConnection._({http.Client? client})
      : _client = client ?? http.Client(),
        _googleIdentityProvider = null;

  TavernGrowthConnection.withClient(
    http.Client client, {
    TavernGoogleIdentityProvider? googleIdentityProvider,
  })  : _client = client,
        _googleIdentityProvider = googleIdentityProvider;

  static final instance = TavernGrowthConnection._();
  static const _apiKey = 'AIzaSyB5K8_jbh-95R78mz8mp2YunY7wHnIbxWk';
  static const _projectId = 'kingdom-ac44f';
  static const _cloudProjectId = 'hoard-ac666';
  static const _cloudApiKey = 'AIzaSyCAkQDVYaKwdMSjSD_3UuxgKMe_kp1Jw3A';
  static const _cloudAppId = '1:783911286552:web:97306fc1d397312b4e106d';

  final http.Client _client;
  final TavernGoogleIdentityProvider? _googleIdentityProvider;
  String? _idToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  Future<String?> Function()? _googleTokenRefresh;
  TavernGrowthSession? _cloudSession;

  Future<TavernGrowthSession?> cloudSession() async {
    final current = _cloudSession;
    if (current == null) return null;
    final refreshed = await _googleTokenRefresh?.call();
    if (refreshed == null || refreshed.isEmpty) return current;
    final next = TavernGrowthSession(
      idToken: refreshed,
      email: current.email,
      orgId: current.orgId,
      venueId: current.venueId,
    );
    _cloudSession = next;
    return next;
  }

  Future<void> connectWithGoogle() async {
    try {
      final identity =
          await (_googleIdentityProvider ?? _nativeGoogleIdentity)();
      final headers = {'Authorization': 'Bearer ${identity.idToken}'};
      final userResponse = await _client
          .get(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/$_cloudProjectId/'
              'databases/(default)/documents/users/${identity.uid}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (userResponse.statusCode == 404) {
        throw StateError(
          'Open Tavern Console with Google once so it can create your venue membership.',
        );
      }
      final userBody = _jsonObject(userResponse.body);
      final userFields = userBody['fields'];
      final orgId =
          userFields is Map ? _firestoreString(userFields['org']) : null;
      if (userResponse.statusCode != 200 || orgId == null) {
        throw StateError('This Google account does not have Tavern access.');
      }

      final orgResponse = await _client
          .get(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/$_cloudProjectId/'
              'databases/(default)/documents/orgs/$orgId',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      final orgBody = _jsonObject(orgResponse.body);
      final orgFields = orgBody['fields'];
      final members = orgFields is Map
          ? _firestoreStringMap(orgFields['members'])
          : const <String, String>{};
      final role = members[identity.uid];
      if (orgResponse.statusCode != 200 ||
          !const {'owner', 'manager', 'staff'}.contains(role)) {
        throw StateError(
          'This Google account is not a member of the Hoard workspace.',
        );
      }
      final venueId = role == 'owner'
          ? 'main'
          : await _assignedVenue(
              orgId: orgId,
              uid: identity.uid,
              idToken: identity.idToken,
            );
      if (venueId == null) {
        throw StateError('No Tavern venue is attached to this Google account.');
      }

      _googleTokenRefresh = identity.refresh;
      _cloudSession = TavernGrowthSession(
        idToken: identity.idToken,
        email: identity.email,
        orgId: orgId,
        venueId: venueId,
      );
    } on StateError {
      rethrow;
    } on TimeoutException {
      throw StateError('Tavern Google sign-in timed out. Try again.');
    } catch (_) {
      throw StateError('Google sign-in could not connect to Tavern.');
    }
  }

  Future<String?> _assignedVenue({
    required String orgId,
    required String uid,
    required String idToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse(
            'https://firestore.googleapis.com/v1/projects/$_cloudProjectId/'
            'databases/(default)/documents/orgs/${Uri.encodeComponent(orgId)}:runQuery',
          ),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': 'venues'},
              ],
              'where': {
                'fieldFilter': {
                  'field': {'fieldPath': 'memberUids'},
                  'op': 'ARRAY_CONTAINS',
                  'value': {'stringValue': uid},
                },
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return null;
    final ids = <String>[];
    for (final row in decoded) {
      if (row is! Map || row['document'] is! Map) continue;
      final name = (row['document'] as Map)['name']?.toString() ?? '';
      final id = name.split('/').last;
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.contains('main')) return 'main';
    ids.sort();
    return ids.isEmpty ? null : ids.first;
  }

  Future<TavernGoogleIdentity> _nativeGoogleIdentity() async {
    if (!Platform.isWindows) {
      throw StateError(
        'Tavern browser sign-in is currently available on Windows desktop.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stateBytes =
        List<int>.generate(24, (_) => Random.secure().nextInt(256));
    final state = base64Url.encode(stateBytes).replaceAll('=', '');
    final result = Completer<TavernGoogleIdentity>();

    late final StreamSubscription<HttpRequest> subscription;
    subscription = server.listen((request) async {
      try {
        if (!request.connectionInfo!.remoteAddress.isLoopback) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        if (request.method == 'GET' && request.uri.path == '/') {
          request.response.headers.contentType = ContentType.html;
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'no-store, max-age=0',
          );
          request.response.headers.set(
            'Content-Security-Policy',
            "default-src 'none'; script-src 'nonce-$state' https://www.gstatic.com "
                "https://apis.google.com; "
                "connect-src 'self' https://*.googleapis.com https://*.firebaseio.com "
                "https://*.firebaseapp.com; frame-src https://accounts.google.com "
                "https://*.firebaseapp.com; img-src data: https://*.googleusercontent.com; "
                "style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
          );
          request.response.write(_browserAuthPage(state));
          await request.response.close();
          return;
        }
        if (request.method == 'POST' && request.uri.path == '/complete') {
          final declaredLength = request.contentLength;
          if (declaredLength > 65536) {
            request.response.statusCode = HttpStatus.requestEntityTooLarge;
            await request.response.close();
            return;
          }
          final raw = await utf8.decoder.bind(request).join();
          final body = _jsonObject(raw);
          final receivedState = body['state'];
          final uid = body['uid'];
          final email = body['email'];
          final idToken = body['idToken'];
          if (receivedState != state ||
              uid is! String ||
              uid.isEmpty ||
              uid.length > 160 ||
              email is! String ||
              email.length > 320 ||
              idToken is! String ||
              idToken.isEmpty ||
              idToken.length > 16384) {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true}');
          await request.response.close();
          if (!result.isCompleted) {
            result.complete(TavernGoogleIdentity(
              uid: uid,
              email: email,
              idToken: idToken,
            ));
          }
          return;
        }
        if (request.method == 'POST' && request.uri.path == '/cancel') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          if (!result.isCompleted) {
            result.completeError(StateError('Google sign-in was cancelled.'));
          }
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        } catch (_) {}
        if (!result.isCompleted) {
          result.completeError(
              StateError('Google sign-in could not connect to Tavern.'));
        }
      }
    });

    try {
      final uri = Uri.parse('http://localhost:${server.port}/');
      await Process.start(
        'explorer.exe',
        [uri.toString()],
        mode: ProcessStartMode.detached,
      );
      return await result.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw StateError('Tavern Google sign-in timed out. Try again.');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  static String _browserAuthPage(String state) {
    final encodedState = jsonEncode(state);
    return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connect Hoard sales to Homecoming</title>
<style>body{margin:0;background:#06141b;color:#e8f7fa;font:16px system-ui;display:grid;min-height:100vh;place-items:center}.card{width:min(520px,calc(100% - 40px));border:1px solid #21cfe6;border-radius:22px;padding:30px;background:#081c24;box-shadow:0 20px 80px #0008}h1{margin:0 0 12px}.muted{color:#a8bdc4;line-height:1.5}.safe{border:1px solid #1c725f;border-radius:14px;padding:14px;margin:22px 0;color:#bfe9dc}button{border:0;border-radius:999px;padding:13px 20px;font-weight:700;cursor:pointer}#google{background:#c9afff;color:#25184a}#cancel{background:transparent;color:#c9afff}.error{color:#ff806d;min-height:24px}</style></head>
<body><main class="card"><h1>Connect Hoard sales</h1><p class="muted">Use the same Google account as Hoard.</p><div class="safe">Read-only access to your assigned venue's sales reports. Homecoming never receives your Google password.</div><p id="status" class="error"></p><button id="cancel">Cancel</button> <button id="google">Continue with Google</button></main>
<script type="module" nonce="$state">
import{initializeApp}from'https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js';
import{getAuth,GoogleAuthProvider,inMemoryPersistence,signInWithPopup,setPersistence,signOut}from'https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js';
const state=$encodedState;const app=initializeApp({apiKey:'$_cloudApiKey',authDomain:'hoard-ac666.firebaseapp.com',projectId:'$_cloudProjectId',storageBucket:'hoard-ac666.firebasestorage.app',appId:'$_cloudAppId'});const auth=getAuth(app);await setPersistence(auth,inMemoryPersistence);
const post=async(path,body={})=>fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
const status=document.querySelector('#status');const describe=error=>String(error?.code??error?.message??error??'unknown').slice(0,160);const complete=async credential=>{const idToken=await credential.user.getIdToken(true);await post('/complete',{state,uid:credential.user.uid,email:credential.user.email??'',idToken});await signOut(auth);document.querySelector('main').innerHTML='<h1>Connected</h1><p class="muted">Return to Homecoming. You may close this tab.</p>'};
document.querySelector('#cancel').onclick=async()=>{await post('/cancel');window.close()};
document.querySelector('#google')?.addEventListener('click',async()=>{status.textContent='Opening Google…';try{const credential=await signInWithPopup(auth,new GoogleAuthProvider());await complete(credential)}catch(error){status.textContent='Google sign-in failed ('+describe(error)+'). You can close this tab and try again.'}});
</script></body></html>''';
  }

  static String? _firestoreString(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['stringValue'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Map<String, String> _firestoreStringMap(Object? raw) {
    if (raw is! Map || raw['mapValue'] is! Map) return const {};
    final fields = (raw['mapValue'] as Map)['fields'];
    if (fields is! Map) return const {};
    final values = <String, String>{};
    for (final entry in fields.entries) {
      final value = _firestoreString(entry.value);
      if (value != null) values[entry.key.toString()] = value;
    }
    return values;
  }

  Future<String?> idToken() async {
    final token = _idToken;
    if (token == null) return null;
    final expiry = _expiresAt;
    if (expiry == null ||
        DateTime.now().toUtc().isBefore(
              expiry.subtract(const Duration(minutes: 2)),
            )) {
      return token;
    }
    return _refresh();
  }

  Future<bool> get isConnected async => await idToken() != null;

  /// Requests Firebase's standard password-reset email for the Tavern staff
  /// account. The password is never readable or returned to Homecoming.
  Future<void> sendPasswordReset(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw StateError('Enter your Tavern staff email first.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/'
              'accounts:sendOobCode?key=$_apiKey',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requestType': 'PASSWORD_RESET',
              'email': cleanEmail,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        final body = _jsonObject(response.body);
        final providerError = body['error'];
        final code = providerError is Map
            ? providerError['message']?.toString() ?? ''
            : '';
        if (code.split(' : ').first == 'TOO_MANY_ATTEMPTS_TRY_LATER') {
          throw StateError(
            'Tavern temporarily refused more reset attempts. Try again later.',
          );
        }
        throw StateError(
          'Tavern could not send a password reset email. Check the address.',
        );
      }
    } on StateError {
      rethrow;
    } on http.ClientException {
      throw StateError(
        'Homecoming could not reach Tavern password reset. Check your connection.',
      );
    } on TimeoutException {
      throw StateError('Tavern password reset timed out. Try again.');
    } catch (_) {
      throw StateError('Tavern password reset could not be requested.');
    }
  }

  Future<void> connect(String email, String password) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw StateError('Enter your Tavern staff email and password.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/'
              'accounts:signInWithPassword?key=$_apiKey',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': cleanEmail,
              'password': password,
              'returnSecureToken': true,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final body = _jsonObject(response.body);
      if (response.statusCode != 200) {
        throw StateError(_friendlyIdentityError(body));
      }
      final token = body['idToken']?.toString();
      final refresh = body['refreshToken']?.toString();
      final uid = body['localId']?.toString();
      final expiresIn = int.tryParse(body['expiresIn']?.toString() ?? '');
      if (token == null ||
          token.isEmpty ||
          refresh == null ||
          refresh.isEmpty ||
          uid == null ||
          uid.isEmpty ||
          expiresIn == null) {
        throw StateError('Tavern sign-in returned an incomplete session.');
      }

      final roleResponse = await _client.get(
        Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$_projectId/'
          'databases/(default)/documents/users/$uid',
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      final roleBody = _jsonObject(roleResponse.body);
      final fields = roleBody['fields'];
      final roleField = fields is Map ? fields['role'] : null;
      final role =
          roleField is Map ? roleField['stringValue']?.toString() : null;
      if (roleResponse.statusCode != 200 ||
          (role != 'staff' && role != 'admin')) {
        _clearSession();
        throw StateError('This Tavern account does not have staff access.');
      }

      _idToken = token;
      _refreshToken = refresh;
      _expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    } on StateError {
      rethrow;
    } on http.ClientException {
      throw StateError(
        'Homecoming could not reach Tavern sign-in. Check your connection.',
      );
    } on TimeoutException {
      throw StateError('Tavern sign-in timed out. Try again.');
    } catch (_) {
      throw StateError('Tavern sign-in failed before access was granted.');
    }
  }

  Future<String?> _refresh() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) {
      _clearSession();
      return null;
    }
    try {
      final response = await _client.post(
        Uri.parse(
          'https://securetoken.googleapis.com/v1/token?key=$_apiKey',
        ),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
        },
      ).timeout(const Duration(seconds: 10));
      final body = _jsonObject(response.body);
      if (response.statusCode != 200) {
        _clearSession();
        return null;
      }
      final token = body['id_token']?.toString();
      final nextRefresh = body['refresh_token']?.toString();
      final expiresIn = int.tryParse(body['expires_in']?.toString() ?? '');
      if (token == null || token.isEmpty || expiresIn == null) {
        _clearSession();
        return null;
      }
      _idToken = token;
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        _refreshToken = nextRefresh;
      }
      _expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
      return token;
    } catch (_) {
      _clearSession();
      return null;
    }
  }

  static Map<String, dynamic> _jsonObject(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _friendlyIdentityError(Map<String, dynamic> body) {
    final error = body['error'];
    final code = error is Map ? error['message']?.toString() ?? '' : '';
    return switch (code.split(' : ').first) {
      'INVALID_LOGIN_CREDENTIALS' ||
      'EMAIL_NOT_FOUND' ||
      'INVALID_PASSWORD' =>
        'The Tavern email or password is incorrect.',
      'USER_DISABLED' => 'This Tavern account is disabled.',
      'TOO_MANY_ATTEMPTS_TRY_LATER' =>
        'Tavern temporarily refused more sign-in attempts. Try again later.',
      _ => 'Tavern sign-in was refused. Please try again.',
    };
  }

  void _clearSession() {
    _idToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _googleTokenRefresh = null;
    _cloudSession = null;
  }

  Future<void> disconnect() async => _clearSession();
}

/// Read-only adapter for Hoard's governed `reach_daily` snapshots.
///
/// It never writes, imports, refreshes platform tokens, or triggers a sync.
/// Missing metrics remain null: absence is not silently turned into zero.
class KaiGrowthTrackerService {
  KaiGrowthTrackerService({
    http.Client? client,
    KaiGrowthTokenProvider? tokenProvider,
    Future<TavernGrowthSession?> Function()? sessionProvider,
    this.socialProjectId = 'kingdom-ac44f',
    this.salesProjectId = 'hoard-ac666',
  })  : _client = client ?? http.Client(),
        _tokenProvider =
            tokenProvider ?? TavernGrowthConnection.instance.idToken,
        _sessionProvider =
            sessionProvider ?? TavernGrowthConnection.instance.cloudSession;

  final http.Client _client;
  final KaiGrowthTokenProvider _tokenProvider;
  final Future<TavernGrowthSession?> Function() _sessionProvider;
  final String socialProjectId;
  final String salesProjectId;

  Future<KaiGrowthSnapshot> load({int days = 28}) async {
    final safeDays = days.clamp(2, 120);
    final results = await Future.wait([
      _tokenProvider(),
      _sessionProvider(),
    ]);
    final socialToken = results[0] as String?;
    final salesSession = results[1] as TavernGrowthSession?;
    if (socialToken == null && salesSession == null) {
      throw StateError('Tavern Growth access is not linked to Homecoming.');
    }

    final socialRows = socialToken == null
        ? const <KaiGrowthDay>[]
        : await _loadReachDays(socialToken);
    final salesRows = salesSession == null
        ? const <KaiGrowthDay>[]
        : await _loadSalesReportDays(salesSession);
    return buildSnapshot(
      _mergeDays([...socialRows, ...salesRows]),
      days: safeDays,
      socialConnected: socialToken != null,
      salesConnected: salesSession != null,
    );
  }

  Future<List<KaiGrowthDay>> _loadReachDays(String token) async {
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$socialProjectId/'
      'databases/(default)/documents/reach_daily',
    ).replace(queryParameters: const {'pageSize': '300'});
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError('Tavern Growth access is not linked to Homecoming.');
    }
    if (response.statusCode != 200) {
      throw StateError('Growth data is unavailable (${response.statusCode}).');
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Growth response was not an object.');
    }
    final documents = body['documents'];
    if (documents is! List) return const [];
    final parsed = <KaiGrowthDay>[];
    for (final raw in documents) {
      final day = parseFirestoreDay(raw);
      if (day != null) parsed.add(day);
    }
    return parsed;
  }

  Future<List<KaiGrowthDay>> _loadSalesReportDays(
    TavernGrowthSession session,
  ) async {
    final org = Uri.encodeComponent(session.orgId);
    final venue = Uri.encodeComponent(session.venueId);
    final base = 'https://firestore.googleapis.com/v1/projects/$salesProjectId/'
        'databases/(default)/documents/orgs/$org/venues/$venue/salesLines';
    final totals = <String, double>{};
    var pageToken = '';
    for (var page = 0; page < 8; page++) {
      final uri = Uri.parse(base).replace(queryParameters: {
        'pageSize': '300',
        if (pageToken.isNotEmpty) 'pageToken': pageToken,
      });
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer ${session.idToken}'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError(
            'Hoard sales-report access is not linked to Homecoming.');
      }
      if (response.statusCode != 200) {
        throw StateError(
          'Hoard sales reports are unavailable (${response.statusCode}).',
        );
      }
      final body = jsonDecode(response.body);
      final documents = body is Map ? body['documents'] : null;
      if (documents is List) {
        for (final document in documents) {
          if (document is! Map || document['fields'] is! Map) continue;
          final fields = document['fields'] as Map;
          final date = _stringValue(fields['date']);
          final revenue = _numberValue(fields['revenue']);
          if (date == null ||
              DateTime.tryParse(date) == null ||
              revenue == null ||
              !revenue.isFinite) {
            continue;
          }
          totals[date] = (totals[date] ?? 0) + revenue;
        }
      }
      pageToken = body is Map ? body['nextPageToken']?.toString() ?? '' : '';
      if (pageToken.isEmpty) break;
    }
    return [
      for (final entry in totals.entries)
        if (DateTime.tryParse(entry.key) case final DateTime date)
          KaiGrowthDay(
            date: DateTime.utc(date.year, date.month, date.day),
            values: {
              KaiGrowthPlatform.instagram: null,
              KaiGrowthPlatform.tiktok: null,
              KaiGrowthPlatform.ads: null,
              KaiGrowthPlatform.google: null,
              KaiGrowthPlatform.sales: entry.value,
            },
          ),
    ];
  }

  static List<KaiGrowthDay> _mergeDays(Iterable<KaiGrowthDay> rows) {
    final merged = <String, KaiGrowthDay>{};
    for (final row in rows) {
      final key = _dateKey(row.date);
      final existing = merged[key];
      final values = <KaiGrowthPlatform, double?>{...?existing?.values};
      for (final entry in row.values.entries) {
        if (entry.value != null || !values.containsKey(entry.key)) {
          values[entry.key] = entry.value;
        }
      }
      merged[key] = KaiGrowthDay(
        date: row.date,
        values: values,
      );
    }
    return merged.values.toList();
  }

  /// Parses the exact cloud blob used by the current Tavern Console. Only
  /// explicit positive daily sales become chart points; missing/default zeros
  /// stay absent rather than being presented as real revenue.
  static List<KaiGrowthDay> parseTavernBook(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map) return const [];
    final ledger = decoded['ledger'];
    final days = ledger is Map ? ledger['days'] : null;
    if (days is! Map) return const [];
    final parsed = <KaiGrowthDay>[];
    for (final entry in days.entries) {
      final date = DateTime.tryParse(entry.key.toString());
      final record = entry.value;
      if (date == null || record is! Map) continue;
      final rawSales = record['sales'];
      final sales = rawSales is num
          ? rawSales.toDouble()
          : double.tryParse(rawSales?.toString() ?? '');
      if (sales == null || !sales.isFinite || sales <= 0) continue;
      parsed.add(KaiGrowthDay(
        date: DateTime.utc(date.year, date.month, date.day),
        values: {
          KaiGrowthPlatform.instagram: null,
          KaiGrowthPlatform.tiktok: null,
          KaiGrowthPlatform.ads: null,
          KaiGrowthPlatform.google: null,
          KaiGrowthPlatform.sales: sales,
        },
      ));
    }
    return parsed;
  }

  static KaiGrowthDay? parseFirestoreDay(Object? raw) {
    if (raw is! Map) return null;
    final fields = raw['fields'];
    if (fields is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final dateText = _stringValue(fields['date']) ?? name.split('/').last;
    final date = DateTime.tryParse(dateText);
    if (date == null || dateText.length < 10) return null;

    final instagram = _metric(fields['instagram'], 'reach');
    final tiktok = _metric(fields['tiktok'], 'views');
    final ads = _metric(fields['ads'], 'reach');
    final googleDirect = _metric(fields['google'], 'impressions');
    final maps = _metric(fields['google'], 'impressionsMaps');
    final search = _metric(fields['google'], 'impressionsSearch');
    final google = googleDirect ?? _sumPresent(maps, search);

    return KaiGrowthDay(
      date: DateTime.utc(date.year, date.month, date.day),
      values: {
        KaiGrowthPlatform.instagram: instagram,
        KaiGrowthPlatform.tiktok: tiktok,
        KaiGrowthPlatform.ads: ads,
        KaiGrowthPlatform.google: google,
        KaiGrowthPlatform.sales: null,
      },
    );
  }

  static KaiGrowthSnapshot buildSnapshot(
    Iterable<KaiGrowthDay> input, {
    int days = 28,
    DateTime? loadedAt,
    bool socialConnected = false,
    bool salesConnected = false,
  }) {
    final sorted = input.toList()..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) {
      return KaiGrowthSnapshot(
        dates: const [],
        series: const [],
        loadedAt: loadedAt ?? DateTime.now().toUtc(),
        socialConnected: socialConnected,
        salesConnected: salesConnected,
      );
    }

    final safeDays = days.clamp(2, 120);
    final byDay = <String, KaiGrowthDay>{
      for (final row in sorted) _dateKey(row.date): row,
    };
    final end = sorted.last.date;
    final dates = List<DateTime>.generate(
      safeDays,
      (index) => end.subtract(Duration(days: safeDays - index - 1)),
    );
    final series = <KaiGrowthSeries>[];

    for (final platform in KaiGrowthPlatform.values) {
      final raw = dates
          .map((date) => byDay[_dateKey(date)]?.values[platform])
          .toList(growable: false);
      final real =
          raw.whereType<double>().where((value) => value.isFinite).toList();
      if (real.length < 2) continue;
      final mean = real.reduce((a, b) => a + b) / real.length;
      if (!(mean > 0)) continue;
      series.add(
        KaiGrowthSeries(
          platform: platform,
          rawValues: raw,
          indexedValues: raw
              .map((value) => value == null ? null : (value / mean) * 100)
              .toList(growable: false),
          mean: mean,
          reportedDays: real.length,
        ),
      );
    }

    return KaiGrowthSnapshot(
      dates: dates,
      series: series,
      loadedAt: loadedAt ?? DateTime.now().toUtc(),
      socialConnected: socialConnected,
      salesConnected: salesConnected,
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _stringValue(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['stringValue'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static double? _metric(Object? rawMap, String key) {
    if (rawMap is! Map) return null;
    final mapValue = rawMap['mapValue'];
    if (mapValue is! Map) return null;
    final fields = mapValue['fields'];
    if (fields is! Map) return null;
    return _numberValue(fields[key]);
  }

  static double? _numberValue(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['doubleValue'] ?? raw['integerValue'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static double? _sumPresent(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0) + (b ?? 0);
  }
}
