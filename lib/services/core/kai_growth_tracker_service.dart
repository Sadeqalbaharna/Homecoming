import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
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
  });

  final List<DateTime> dates;
  final List<KaiGrowthSeries> series;
  final DateTime loadedAt;

  bool get hasChartData => series.isNotEmpty;
}

typedef KaiGrowthTokenProvider = Future<String?> Function();

/// Read-only adapter for Hoard's governed `reach_daily` snapshots.
///
/// It never writes, imports, refreshes platform tokens, or triggers a sync.
/// Missing metrics remain null: absence is not silently turned into zero.
class KaiGrowthTrackerService {
  KaiGrowthTrackerService({
    http.Client? client,
    KaiGrowthTokenProvider? tokenProvider,
    this.projectId = 'kingdom-ac44f',
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider ?? _defaultToken;

  final http.Client _client;
  final KaiGrowthTokenProvider _tokenProvider;
  final String projectId;

  static Future<String?> _defaultToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  Future<KaiGrowthSnapshot> load({int days = 28}) async {
    final safeDays = days.clamp(2, 120);
    final token = await _tokenProvider();
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/'
      'databases/(default)/documents/reach_daily',
    ).replace(queryParameters: const {'pageSize': '300'});
    final response = await _client
        .get(
          uri,
          headers: token == null || token.isEmpty
              ? const {}
              : {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 10));

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
    if (documents is! List) {
      return buildSnapshot(const [], days: safeDays);
    }
    final parsed = <KaiGrowthDay>[];
    for (final raw in documents) {
      final day = parseFirestoreDay(raw);
      if (day != null) parsed.add(day);
    }
    final sales = await _loadSales(token);
    if (sales.isNotEmpty) {
      final merged = <String, KaiGrowthDay>{
        for (final row in parsed) _dateKey(row.date): row,
      };
      for (final entry in sales.entries) {
        final existing = merged[entry.key];
        final date = DateTime.tryParse(entry.key);
        if (date == null) continue;
        merged[entry.key] = KaiGrowthDay(
          date: DateTime.utc(date.year, date.month, date.day),
          values: {
            ...?existing?.values,
            KaiGrowthPlatform.sales: entry.value,
          },
        );
      }
      parsed
        ..clear()
        ..addAll(merged.values);
    }
    return buildSnapshot(parsed, days: safeDays);
  }

  Future<Map<String, double>> _loadSales(String? token) async {
    if (token == null || token.isEmpty) return const {};
    final uid = _uidFromToken(token);
    if (uid == null) return const {};
    final headers = {'Authorization': 'Bearer $token'};
    final userUri = _documentUri('users/$uid');
    final userResponse = await _client
        .get(userUri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (userResponse.statusCode != 200) return const {};
    final user = jsonDecode(userResponse.body);
    final fields = user is Map ? user['fields'] : null;
    final org = fields is Map ? _stringValue(fields['org']) : null;
    if (org == null || org.isEmpty) return const {};

    // Owners use the governed default venue. If a future multi-venue selector
    // is introduced, it should supply that route explicitly rather than merge
    // revenue from different venues.
    final uri = _collectionUri('orgs/$org/venues/main/salesLines');
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const {};
    final body = jsonDecode(response.body);
    final documents = body is Map ? body['documents'] : null;
    if (documents is! List) return const {};
    final totals = <String, double>{};
    for (final document in documents) {
      if (document is! Map || document['fields'] is! Map) continue;
      final row = document['fields'] as Map;
      final date = _stringValue(row['date']);
      final revenue = _numberValue(row['revenue']);
      if (date == null || revenue == null || !revenue.isFinite) continue;
      totals[date] = (totals[date] ?? 0) + revenue;
    }
    return totals;
  }

  Uri _documentUri(String path) => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/'
        'databases/(default)/documents/$path',
      );

  Uri _collectionUri(String path) =>
      _documentUri(path).replace(queryParameters: const {'pageSize': '300'});

  static String? _uidFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final body = jsonDecode(payload);
      if (body is! Map) return null;
      final uid = body['user_id'] ?? body['sub'];
      return uid is String && uid.isNotEmpty ? uid : null;
    } catch (_) {
      return null;
    }
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
  }) {
    final sorted = input.toList()..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) {
      return KaiGrowthSnapshot(
        dates: const [],
        series: const [],
        loadedAt: loadedAt ?? DateTime.now().toUtc(),
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
