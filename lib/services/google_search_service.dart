/// Google Custom Search Service
/// Provides web search capabilities using Google Custom Search JSON API
/// Ported from Python backend (server.py) to pure Flutter/Dart

import 'package:dio/dio.dart';

/// Search result from Google Custom Search
class SearchResult {
  final String title;
  final String link;
  final String displayLink;
  final String snippet;
  final String publishedAt;

  SearchResult({
    required this.title,
    required this.link,
    required this.displayLink,
    required this.snippet,
    required this.publishedAt,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    // Extract published time from pagemap metatags
    String publishedAt = '';
    try {
      final pagemap = json['pagemap'] as Map<String, dynamic>?;
      final metatags = pagemap?['metatags'] as List?;
      if (metatags != null && metatags.isNotEmpty) {
        final meta = metatags[0] as Map<String, dynamic>;
        // Try various date fields
        for (final key in [
          'og:updated_time',
          'article:modified_time',
          'article:published_time',
          'pubdate',
          'date',
          'og:pubdate'
        ]) {
          if (meta.containsKey(key) && meta[key] != null) {
            publishedAt = meta[key].toString();
            break;
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }

    return SearchResult(
      title: json['title'] as String? ?? '',
      link: json['link'] as String? ?? '',
      displayLink: json['displayLink'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      publishedAt: publishedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'link': link,
        'displayLink': displayLink,
        'snippet': snippet,
        'publishedAt': publishedAt,
      };
}

/// Diagnostic information about the search request
class SearchDiagnostics {
  final bool ok;
  final int? statusCode;
  final String? error;
  final String? url;

  SearchDiagnostics({
    required this.ok,
    this.statusCode,
    this.error,
    this.url,
  });

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'status': statusCode,
        'error': error,
        'url': url,
      };
}

/// Search response containing results and diagnostics
class SearchResponse {
  final List<SearchResult> results;
  final SearchDiagnostics diagnostics;

  SearchResponse({
    required this.results,
    required this.diagnostics,
  });

  bool get hasResults => results.isNotEmpty;
  bool get isSuccess => diagnostics.ok;
  String? get error => diagnostics.error;
}

/// Google Custom Search Service
class GoogleSearchService {
  final Dio _dio = Dio();

  /// Normalize date restrict parameter
  /// Converts: hN → d1, ensures valid format (dN/wN/mN/yN)
  String? _normalizeDateRestrict(String? value) {
    if (value == null || value.isEmpty) return null;

    final v = value.trim().toLowerCase();

    // Convert hours to days (API doesn't support hours)
    if (v.startsWith('h')) return 'd1';

    // Validate format: d/w/m/y followed by digits
    if (v.length >= 2) {
      final prefix = v[0];
      final suffix = v.substring(1);

      if (['d', 'w', 'm', 'y'].contains(prefix) && _isNumeric(suffix)) {
        final num = int.tryParse(suffix) ?? 1;
        return '$prefix${num.clamp(1, 9999)}';
      }
    }

    return null;
  }

  bool _isNumeric(String str) {
    return int.tryParse(str) != null;
  }

  /// Perform Google Custom Search
  /// 
  /// [apiKey] - Google API Key
  /// [cseId] - Custom Search Engine ID
  /// [query] - Search query
  /// [num] - Number of results (1-10, default: 5)
  /// [dateRestrict] - Date restriction (d1, w1, m1, y1, etc.)
  /// [lang] - Language (default: en)
  /// [gl] - Geographic location (default: us)
  /// [newsBias] - Apply news site bias for recent info
  /// 
  /// Returns [SearchResponse] with results and diagnostics
  Future<SearchResponse> search({
    required String apiKey,
    required String cseId,
    required String query,
    int num = 5,
    String dateRestrict = 'd1',
    String lang = 'en',
    String gl = 'us',
    bool newsBias = false,
  }) async {
    print('🔍 [GOOGLE SEARCH] Starting search...');
    print('🔍 [GOOGLE SEARCH] Query: "$query"');
    print('🔍 [GOOGLE SEARCH] Num results: $num');
    print('🔍 [GOOGLE SEARCH] Date restrict: $dateRestrict');
    print('🔍 [GOOGLE SEARCH] News bias: $newsBias');

    // Validate API credentials
    if (apiKey.isEmpty || cseId.isEmpty) {
      print('❌ [GOOGLE SEARCH] Missing API credentials');
      return SearchResponse(
        results: [],
        diagnostics: SearchDiagnostics(
          ok: false,
          error: 'GOOGLE_API_KEY or GOOGLE_CSE_ID missing',
        ),
      );
    }

    // Apply news bias (search within trusted news sites)
    String searchQuery = query;
    if (newsBias) {
      searchQuery = '$query (site:news.google.com OR site:reuters.com OR '
          'site:apnews.com OR site:bbc.com OR site:cnn.com OR '
          'site:aljazeera.com OR site:theguardian.com)';
      print('🔍 [GOOGLE SEARCH] News query: "$searchQuery"');
    }

    // Build query parameters
    final params = {
      'key': apiKey,
      'cx': cseId,
      'q': searchQuery,
      'num': num.clamp(1, 10).toString(),
      'hl': lang,
      'gl': gl,
      'safe': 'off',
    };

    // Add date restriction if valid
    final normalizedDate = _normalizeDateRestrict(dateRestrict);
    if (normalizedDate != null) {
      params['dateRestrict'] = normalizedDate;
    }

    // Construct URL
    const baseUrl = 'https://www.googleapis.com/customsearch/v1';

    try {
      print('🔍 [GOOGLE SEARCH] Making API request...');

      final response = await _dio.get(
        baseUrl,
        queryParameters: params,
        options: Options(
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      print('🔍 [GOOGLE SEARCH] Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? (response.data['error']?['message'] ?? 'HTTP ${response.statusCode}')
            : 'HTTP ${response.statusCode}';

        print('❌ [GOOGLE SEARCH] Error: $errorMsg');

        return SearchResponse(
          results: [],
          diagnostics: SearchDiagnostics(
            ok: false,
            statusCode: response.statusCode,
            error: errorMsg,
            url: response.realUri.toString(),
          ),
        );
      }

      final data = response.data as Map<String, dynamic>;

      // Check for API error in response
      if (data.containsKey('error')) {
        final errorMsg = data['error']['message'] ?? 'Unknown API error';
        print('❌ [GOOGLE SEARCH] API error: $errorMsg');

        return SearchResponse(
          results: [],
          diagnostics: SearchDiagnostics(
            ok: false,
            statusCode: response.statusCode,
            error: errorMsg,
            url: response.realUri.toString(),
          ),
        );
      }

      // Parse results
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final results = items.take(num).map((item) => SearchResult.fromJson(item)).toList();

      print('✅ [GOOGLE SEARCH] Found ${results.length} results');

      if (results.isEmpty) {
        print('⚠️ [GOOGLE SEARCH] No items returned (engine restrictions or empty results)');
      }

      return SearchResponse(
        results: results,
        diagnostics: SearchDiagnostics(
          ok: true,
          statusCode: response.statusCode,
          error: results.isEmpty ? 'No items returned (engine restrictions or empty results)' : null,
          url: response.realUri.toString(),
        ),
      );
    } on DioException catch (e) {
      print('❌ [GOOGLE SEARCH] Dio error: ${e.message}');

      return SearchResponse(
        results: [],
        diagnostics: SearchDiagnostics(
          ok: false,
          statusCode: e.response?.statusCode,
          error: 'Exception: ${e.message}',
          url: e.requestOptions.uri.toString(),
        ),
      );
    } catch (e) {
      print('❌ [GOOGLE SEARCH] Unexpected error: $e');

      return SearchResponse(
        results: [],
        diagnostics: SearchDiagnostics(
          ok: false,
          error: 'Exception: $e',
        ),
      );
    }
  }

  /// Determine if a query should trigger web search
  /// Based on content analysis (news, time-sensitive info, etc.)
  /// 
  /// Returns true if search should be performed
  static bool shouldSearch(String userText) {
    final text = userText.trim();
    if (text.isEmpty) return false;

    final lower = text.toLowerCase();

    // Don't search for time/weather (handled natively)
    if (_isTimeQuery(lower) || _isWeatherQuery(lower)) {
      return false;
    }

    // Explicit search intent
    if (lower.contains('search') || _hasUrl(text)) {
      return true;
    }

    // News/current events
    if (_isNewsQuery(lower)) {
      return true;
    }

    // Year mentions (historical queries)
    if (_hasYearMention(text)) {
      return true;
    }

    // Long questions (likely need context)
    if (text.contains('?') && text.split(' ').length > 10) {
      return true;
    }

    // Short news triggers
    if (['news', 'headlines', 'top news'].contains(lower)) {
      return true;
    }

    return false;
  }

  static bool _isTimeQuery(String text) {
    return RegExp(r'\b(time|current time|what time is it|time in)\b', caseSensitive: false)
        .hasMatch(text);
  }

  static bool _isWeatherQuery(String text) {
    return RegExp(r'\b(weather|forecast|temperature|rain|wind|humidity|uv index)\b',
            caseSensitive: false)
        .hasMatch(text);
  }

  static bool _hasUrl(String text) {
    return RegExp(r'https?://|www\.', caseSensitive: false).hasMatch(text);
  }

  static bool _isNewsQuery(String text) {
    return RegExp(
      r'\b(latest|today|tonight|now|right\s*now|breaking|this week|this month|recent|update|'
      r'news|headlines|top stories|trending|'
      r'who won|final score|live score|score|results|fixture|match|game|kickoff|tipoff|'
      r'release date|when is|schedule|'
      r'earnings|stock|share price|ipo|crypto|bitcoin|ethereum|exchange rate|'
      r'traffic|queue times|flight status|'
      r'covid|inflation|rate|mortgage|fed|election|poll|'
      r'nba|nfl|mlb|nhl|epl|uefa|f1|formula 1|tennis|golf)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _hasYearMention(String text) {
    return RegExp(r'\b(19\d{2}|20[0-5]\d)\b').hasMatch(text);
  }

  /// Build web context for AI prompt from search results
  /// Formats results as numbered citations
  static String buildWebContext(List<SearchResult> results) {
    if (results.isEmpty) return '';

    final lines = <String>[];
    for (var i = 0; i < results.length && i < 5; i++) {
      final result = results[i];
      final title = result.title.length > 160 ? '${result.title.substring(0, 160)}...' : result.title;
      final snippet =
          result.snippet.length > 300 ? '${result.snippet.substring(0, 300)}...' : result.snippet;

      lines.add('[${i + 1}] $title\n${result.link}\n— $snippet');
    }

    return 'Use the following web findings **only if helpful**. '
        'Cite sources inline as [#] when stating specific facts.\n\n${lines.join('\n\n')}';
  }

  /// Format search results as a headline list
  /// Used for "news" or "headlines" queries
  static String formatAsHeadlines(List<SearchResult> results) {
    if (results.isEmpty) return 'No headlines found.';

    final lines = <String>[];
    for (var i = 0; i < results.length && i < 5; i++) {
      final result = results[i];
      final title = result.title.trim();
      final domain = result.displayLink.trim();

      if (title.isNotEmpty) {
        lines.add('${i + 1}. $title${domain.isNotEmpty ? ' — $domain' : ''}');
      }
    }

    return lines.isEmpty ? 'No headlines found.' : 'Here are some current headlines:\n${lines.join('\n')}';
  }
}
