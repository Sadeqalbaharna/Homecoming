// Memory Service - Query Kai's long-term memory
// Interfaces with Firebase Cloud Functions for memory retrieval

import 'package:cloud_functions/cloud_functions.dart';

/// Memory query result
class MemoryResult {
  final String id;
  final String summary;
  final double similarity;
  final String shardRef;

  MemoryResult({
    required this.id,
    required this.summary,
    required this.similarity,
    required this.shardRef,
  });

  factory MemoryResult.fromJson(Map<String, dynamic> json) {
    return MemoryResult(
      id: json['id'] as String,
      summary: json['summary'] as String,
      similarity: (json['similarity'] as num).toDouble(),
      shardRef: json['shardRef'] as String,
    );
  }
}

/// Memory query response
class MemoryQueryResponse {
  final String query;
  final List<MemoryResult> results;
  final int count;

  MemoryQueryResponse({
    required this.query,
    required this.results,
    required this.count,
  });

  factory MemoryQueryResponse.fromJson(Map<String, dynamic> json) {
    final results = (json['results'] as List)
        .map((r) => MemoryResult.fromJson(r as Map<String, dynamic>))
        .toList();

    return MemoryQueryResponse(
      query: json['query'] as String,
      results: results,
      count: json['count'] as int,
    );
  }

  /// Get formatted memory context for AI prompt
  String toContextString() {
    if (results.isEmpty) {
      return '';
    }

    final memories = results
        .where((r) => r.similarity > 0.7) // Only include relevant memories
        .map((r) => '- ${r.summary} (relevance: ${(r.similarity * 100).toStringAsFixed(0)}%)')
        .join('\n');

    if (memories.isEmpty) {
      return '';
    }

    return '''

📚 Relevant Memories:
$memories
''';
  }
}

/// Service for querying Kai's long-term memory
class MemoryService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Query memory for relevant past conversations
  /// 
  /// [personaId] - The persona to query (e.g., 'truekai')
  /// [query] - The search query (usually the user's message)
  /// [limit] - Maximum number of results to return (default: 5)
  /// 
  /// Returns a [MemoryQueryResponse] with ranked relevant memories
  static Future<MemoryQueryResponse?> queryMemory({
    required String personaId,
    required String query,
    int limit = 5,
  }) async {
    try {
      print('🔍 [MEMORY] Starting query...');
      print('🔍 [MEMORY] PersonaId: $personaId');
      print('🔍 [MEMORY] Query: "$query"');
      print('🔍 [MEMORY] Limit: $limit');
      
      final callable = _functions.httpsCallable('queryMemory');
      print('🔍 [MEMORY] Calling Cloud Function "queryMemory"...');
      
      final result = await callable.call({
        'personaId': personaId,
        'query': query,
        'limit': limit,
      });

      print('🔍 [MEMORY] Cloud Function response received');
      print('🔍 [MEMORY] Data type: ${result.data?.runtimeType}');
      print('🔍 [MEMORY] Data: ${result.data}');

      if (result.data == null) {
        print('⚠️ [MEMORY] Query returned no data (null)');
        return null;
      }

      final response = MemoryQueryResponse.fromJson(
        result.data as Map<String, dynamic>
      );

      print('✅ [MEMORY] Found ${response.results.length} memories');
      if (response.results.isNotEmpty) {
        print('✅ [MEMORY] Top match: ${response.results.first.summary}');
        print('✅ [MEMORY] Similarity: ${(response.results.first.similarity * 100).toStringAsFixed(1)}%');
        
        // Log all results
        for (var i = 0; i < response.results.length; i++) {
          final r = response.results[i];
          print('   ${i + 1}. ${r.summary} (${(r.similarity * 100).toStringAsFixed(1)}%)');
        }
      } else {
        print('⚠️ [MEMORY] No relevant memories found (empty results)');
      }

      return response;
    } catch (e, stackTrace) {
      print('❌ [MEMORY] Query error: $e');
      print('❌ [MEMORY] Stack trace: $stackTrace');
      // Don't throw - gracefully degrade to no memory context
      return null;
    }
  }

  /// Get memory facts for a persona
  /// 
  /// Returns extracted facts from conversation history
  static Future<List<String>> getMemoryFacts({
    required String personaId,
    int limit = 10,
  }) async {
    try {
      final callable = _functions.httpsCallable('getMemoryFacts');
      final result = await callable.call({
        'personaId': personaId,
        'limit': limit,
      });

      if (result.data == null) return [];

      final facts = (result.data['facts'] as List?)
          ?.map((f) => f.toString())
          .toList() ?? [];

      return facts;
    } catch (e) {
      print('❌ Memory facts error: $e');
      return [];
    }
  }

  /// Get conversation summary for a time range
  /// 
  /// Useful for showing "what we talked about today/this week"
  static Future<String?> getSummary({
    required String personaId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final callable = _functions.httpsCallable('getSummary');
      final result = await callable.call({
        'personaId': personaId,
        'startDate': startDate?.millisecondsSinceEpoch,
        'endDate': endDate?.millisecondsSinceEpoch,
      });

      return result.data?['summary'] as String?;
    } catch (e) {
      print('❌ Summary error: $e');
      return null;
    }
  }
}
