import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const kaiWhoopRedirectUri = 'homecoming://whoop/oauth';
const kaiWhoopScopes = <String>[
  'offline',
  'read:body_measurement',
  'read:recovery',
  'read:cycles',
  'read:sleep',
  'read:workout',
];

class KaiWhoopHealthSnapshot {
  const KaiWhoopHealthSnapshot({
    required this.syncedAt,
    this.weightKg,
    this.restingHeartRate,
    this.hrvMs,
    this.recoveryScore,
    this.dayStrain,
    this.sleepHours,
    this.sleepPerformance,
    this.workoutToday = false,
  });

  final DateTime syncedAt;
  final double? weightKg;
  final double? restingHeartRate;
  final double? hrvMs;
  final double? recoveryScore;
  final double? dayStrain;
  final double? sleepHours;
  final double? sleepPerformance;
  final bool workoutToday;

  Map<String, Object?> toJson() => {
        'syncedAt': syncedAt.toUtc().toIso8601String(),
        'weightKg': weightKg,
        'restingHeartRate': restingHeartRate,
        'hrvMs': hrvMs,
        'recoveryScore': recoveryScore,
        'dayStrain': dayStrain,
        'sleepHours': sleepHours,
        'sleepPerformance': sleepPerformance,
        'workoutToday': workoutToday,
      };

  static KaiWhoopHealthSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final syncedAt = DateTime.tryParse(raw['syncedAt']?.toString() ?? '');
    if (syncedAt == null) return null;
    double? number(Object? value) => value is num ? value.toDouble() : null;
    return KaiWhoopHealthSnapshot(
      syncedAt: syncedAt,
      weightKg: number(raw['weightKg']),
      restingHeartRate: number(raw['restingHeartRate']),
      hrvMs: number(raw['hrvMs']),
      recoveryScore: number(raw['recoveryScore']),
      dayStrain: number(raw['dayStrain']),
      sleepHours: number(raw['sleepHours']),
      sleepPerformance: number(raw['sleepPerformance']),
      workoutToday: raw['workoutToday'] == true,
    );
  }
}

class KaiWhoopConnectionStatus {
  const KaiWhoopConnectionStatus({
    required this.configured,
    required this.connected,
  });
  final bool configured;
  final bool connected;
}

class KaiWhoopException implements Exception {
  const KaiWhoopException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Read-only WHOOP OAuth and sync seam for the personal desktop Fitness card.
/// Secrets/tokens never enter SharedPreferences, Firebase, logs, or UI state.
class KaiWhoopService {
  KaiWhoopService({
    FlutterSecureStorage? secureStorage,
    http.Client? client,
    Random? random,
  })  : _storage = secureStorage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client(),
        _random = random ?? Random.secure();

  static final instance = KaiWhoopService();
  static const _base = 'https://api.prod.whoop.com/developer';
  static const _auth = 'https://api.prod.whoop.com/oauth/oauth2/auth';
  static const _token = 'https://api.prod.whoop.com/oauth/oauth2/token';
  static const _clientIdKey = 'kai_whoop_client_id';
  static const _clientSecretKey = 'kai_whoop_client_secret';
  static const _accessTokenKey = 'kai_whoop_access_token';
  static const _refreshTokenKey = 'kai_whoop_refresh_token';
  static const _expiresAtKey = 'kai_whoop_expires_at';

  final FlutterSecureStorage _storage;
  final http.Client _client;
  final Random _random;
  Future<String>? _refreshInFlight;

  Future<KaiWhoopConnectionStatus> status() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _clientIdKey),
        _storage.read(key: _clientSecretKey),
        _storage.read(key: _refreshTokenKey),
      ]);
      return KaiWhoopConnectionStatus(
        configured:
            values[0]?.isNotEmpty == true && values[1]?.isNotEmpty == true,
        connected: values[2]?.isNotEmpty == true,
      );
    } catch (_) {
      return const KaiWhoopConnectionStatus(
          configured: false, connected: false);
    }
  }

  String createState() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(8, (_) => alphabet[_random.nextInt(alphabet.length)])
        .join();
  }

  Uri authorizationUri({required String clientId, required String state}) {
    if (state.length != 8) {
      throw const KaiWhoopException(
          'WHOOP authorization state must be exactly 8 characters.');
    }
    return Uri.parse(_auth).replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': kaiWhoopRedirectUri,
      'scope': kaiWhoopScopes.join(' '),
      'state': state,
    });
  }

  Future<void> connect({String? clientId, String? clientSecret}) async {
    final savedId = (clientId?.trim().isNotEmpty == true)
        ? clientId!.trim()
        : await _storage.read(key: _clientIdKey);
    final savedSecret = (clientSecret?.trim().isNotEmpty == true)
        ? clientSecret!.trim()
        : await _storage.read(key: _clientSecretKey);
    if (savedId == null ||
        savedId.isEmpty ||
        savedSecret == null ||
        savedSecret.isEmpty) {
      throw const KaiWhoopException(
          'Enter the Client ID and Client Secret from your WHOOP developer app.');
    }
    await _storage.write(key: _clientIdKey, value: savedId);
    await _storage.write(key: _clientSecretKey, value: savedSecret);

    final state = createState();
    final callbackFile = _callbackFile();
    if (await callbackFile.exists()) await callbackFile.delete();
    final uri = authorizationUri(clientId: savedId, state: state);
    if (!Platform.isWindows) {
      throw const KaiWhoopException(
          'WHOOP connection is currently available on Desktop Homecoming for Windows.');
    }
    // Use Windows' URL protocol handler. Launching explorer.exe directly can
    // interpret an https URL as a filesystem location and open Documents.
    // A detached process deliberately has no observable exitCode in Dart;
    // spawn failures are surfaced directly by Process.start.
    await Process.start(
        'rundll32.exe', ['url.dll,FileProtocolHandler', uri.toString()],
        mode: ProcessStartMode.detached);
    final callback = await _waitForCallback(callbackFile);
    if (callback.queryParameters['state'] != state) {
      throw const KaiWhoopException(
          'WHOOP returned an invalid security state. Nothing was connected.');
    }
    final oauthError = callback.queryParameters['error'];
    if (oauthError != null) {
      throw KaiWhoopException(
          'WHOOP authorization was not completed ($oauthError).');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const KaiWhoopException(
          'WHOOP did not return an authorization code.');
    }
    final response = await _client.post(Uri.parse(_token), body: {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': savedId,
      'client_secret': savedSecret,
      'redirect_uri': kaiWhoopRedirectUri,
    });
    await _storeTokenResponse(response);
  }

  Future<KaiWhoopHealthSnapshot> sync() async {
    final token = await _validAccessToken();
    final headers = {'Authorization': 'Bearer $token'};
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final end =
        DateTime(now.year, now.month, now.day + 1).toUtc().toIso8601String();

    final body = await _getJson('/v2/user/measurement/body', headers);
    final recovery = await _getJson('/v2/recovery?limit=1', headers);
    final cycle = await _getJson('/v2/cycle?limit=1', headers);
    final sleep = await _getJson('/v2/activity/sleep?limit=1', headers);
    final workout = await _getJson(
        '/v2/activity/workout?limit=1&start=${Uri.encodeQueryComponent(start)}&end=${Uri.encodeQueryComponent(end)}',
        headers);
    return parseHealthSnapshot(
      syncedAt: now,
      body: body,
      recoveryCollection: recovery,
      cycleCollection: cycle,
      sleepCollection: sleep,
      workoutCollection: workout,
    );
  }

  static KaiWhoopHealthSnapshot parseHealthSnapshot({
    required DateTime syncedAt,
    required Object? body,
    required Object? recoveryCollection,
    required Object? cycleCollection,
    required Object? sleepCollection,
    required Object? workoutCollection,
  }) {
    Map? first(Object? collection) {
      if (collection is! Map || collection['records'] is! List) return null;
      final records = collection['records'] as List;
      return records.isNotEmpty && records.first is Map
          ? records.first as Map
          : null;
    }

    double? number(Object? value) => value is num ? value.toDouble() : null;
    final bodyMap = body is Map ? body : const {};
    final recovery = first(recoveryCollection);
    final recoveryScore =
        recovery?['score'] is Map ? recovery!['score'] as Map : null;
    final cycle = first(cycleCollection);
    final cycleScore = cycle?['score'] is Map ? cycle!['score'] as Map : null;
    final sleep = first(sleepCollection);
    final sleepScore = sleep?['score'] is Map ? sleep!['score'] as Map : null;
    final stages = sleepScore?['stage_summary'] is Map
        ? sleepScore!['stage_summary'] as Map
        : null;
    final asleepMillis = [
      stages?['total_light_sleep_time_milli'],
      stages?['total_slow_wave_sleep_time_milli'],
      stages?['total_rem_sleep_time_milli'],
    ].whereType<num>().fold<double>(0, (sum, item) => sum + item.toDouble());
    return KaiWhoopHealthSnapshot(
      syncedAt: syncedAt,
      weightKg: number(bodyMap['weight_kilogram']),
      restingHeartRate: number(recoveryScore?['resting_heart_rate']),
      hrvMs: number(recoveryScore?['hrv_rmssd_milli']),
      recoveryScore: number(recoveryScore?['recovery_score']),
      dayStrain: number(cycleScore?['strain']),
      sleepHours: asleepMillis > 0 ? asleepMillis / 3600000 : null,
      sleepPerformance: number(sleepScore?['sleep_performance_percentage']),
      workoutToday: first(workoutCollection) != null,
    );
  }

  Future<void> disconnect() async {
    final access = await _storage.read(key: _accessTokenKey);
    if (access != null && access.isNotEmpty) {
      final response = await _client.delete(
        Uri.parse('$_base/v2/user/access'),
        headers: {'Authorization': 'Bearer $access'},
      );
      if (response.statusCode != 204 && response.statusCode != 401) {
        throw KaiWhoopException(
            'WHOOP could not revoke access (${response.statusCode}).');
      }
    }
    await _clearTokens();
  }

  Future<void> forgetAppCredentials() async {
    await _clearTokens();
    await _storage.delete(key: _clientIdKey);
    await _storage.delete(key: _clientSecretKey);
  }

  Future<Object?> _getJson(String path, Map<String, String> headers) async {
    final response =
        await _client.get(Uri.parse('$_base$path'), headers: headers);
    if (response.statusCode == 401) {
      final fresh = await _refreshAccessToken();
      final retry = await _client.get(Uri.parse('$_base$path'),
          headers: {'Authorization': 'Bearer $fresh'});
      return _decodeResponse(retry);
    }
    return _decodeResponse(response);
  }

  Object? _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KaiWhoopException('WHOOP sync failed (${response.statusCode}).');
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw const KaiWhoopException('WHOOP returned unreadable data.');
    }
  }

  Future<String> _validAccessToken() async {
    final access = await _storage.read(key: _accessTokenKey);
    final expiry =
        DateTime.tryParse(await _storage.read(key: _expiresAtKey) ?? '');
    if (access != null &&
        access.isNotEmpty &&
        expiry != null &&
        expiry
            .isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)))) {
      return access;
    }
    return _refreshAccessToken();
  }

  Future<String> _refreshAccessToken() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    return operation.whenComplete(() => _refreshInFlight = null);
  }

  Future<String> _performRefresh() async {
    final values = await Future.wait([
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _clientIdKey),
      _storage.read(key: _clientSecretKey),
    ]);
    if (values.any((value) => value == null || value.isEmpty)) {
      throw const KaiWhoopException('WHOOP is not connected.');
    }
    final response = await _client.post(Uri.parse(_token), body: {
      'grant_type': 'refresh_token',
      'refresh_token': values[0]!,
      'client_id': values[1]!,
      'client_secret': values[2]!,
      'scope': 'offline',
    });
    return _storeTokenResponse(response);
  }

  Future<String> _storeTokenResponse(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KaiWhoopException(
          'WHOOP token exchange failed (${response.statusCode}).');
    }
    final raw = jsonDecode(response.body);
    if (raw is! Map ||
        raw['access_token'] is! String ||
        raw['refresh_token'] is! String) {
      throw const KaiWhoopException('WHOOP returned an incomplete token set.');
    }
    final access = raw['access_token'] as String;
    final refresh = raw['refresh_token'] as String;
    final expiresIn = (raw['expires_in'] as num?)?.toInt() ?? 3600;
    await _storage.write(key: _accessTokenKey, value: access);
    await _storage.write(key: _refreshTokenKey, value: refresh);
    await _storage.write(
        key: _expiresAtKey,
        value: DateTime.now()
            .toUtc()
            .add(Duration(seconds: expiresIn))
            .toIso8601String());
    return access;
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
  }

  File _callbackFile() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      throw const KaiWhoopException(
          'Windows local application storage is unavailable.');
    }
    return File(
        '$local${Platform.pathSeparator}Homecoming${Platform.pathSeparator}whoop_oauth_callback.txt');
  }

  Future<Uri> _waitForCallback(File file) async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (await file.exists()) {
        final raw = (await file.readAsString()).trim();
        await file.delete();
        final uri = Uri.tryParse(raw);
        if (uri != null &&
            uri.scheme == 'homecoming' &&
            uri.host == 'whoop' &&
            uri.path == '/oauth') {
          return uri;
        }
        throw const KaiWhoopException(
            'Homecoming received an invalid WHOOP callback.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const KaiWhoopException(
        'WHOOP connection timed out. You can safely try again.');
  }
}
