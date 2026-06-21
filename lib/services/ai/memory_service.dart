// Long-term memory: embedding-based retrieval backed by Firebase RTDB.
// Stores conversation summaries as shards; queries by cosine similarity.

import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/firebase_service.dart';
import 'ai_config.dart';

/// A single memory result from a similarity search.
class MemoryResult {
  final String id;
  final String summary;
  final double similarity;
  final String timestamp;
  final String shardId;
  final String shardRef;

  const MemoryResult({
    required this.id,
    required this.summary,
    required this.similarity,
    required this.timestamp,
    required this.shardId,
    required this.shardRef,
  });
}

/// Result set returned from [MemoryService.queryMemory].
class MemoryQueryResult {
  final List<MemoryResult> results;
  final String query;

  const MemoryQueryResult({required this.results, required this.query});

  /// Format results as a context block for the system prompt.
  String toContextString() {
    if (results.isEmpty) return '';
    final buf = StringBuffer('\n\n=== Relevant Memories ===\n');
    for (final r in results) {
      final pct = (r.similarity * 100).toStringAsFixed(0);
      buf.writeln('• [$pct% match] ${r.summary}');
    }
    return buf.toString();
  }
}

class MemoryService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // ── Public API ────────────────────────────────────────────────────────────

  /// Query long-term memory for [query], returning up to [limit] results.
  static Future<MemoryQueryResult?> queryMemory({
    required String personaId,
    required String query,
    int limit = 5,
  }) async {
    try {
      // Get embedding for the query
      final queryEmbedding = await _getEmbedding(query);
      if (queryEmbedding == null) return null;

      // Load all memory shards from Firebase / local cache
      final shards = await _loadShards(personaId);
      if (shards.isEmpty) return MemoryQueryResult(results: [], query: query);

      // Score each shard
      final scored = <MemoryResult>[];
      for (final shard in shards) {
        final embedding = shard['embedding'];
        if (embedding == null) continue;
        final vec = List<double>.from(embedding as List);
        final sim = _cosineSimilarity(queryEmbedding, vec);
        scored.add(MemoryResult(
          id: shard['id']?.toString() ?? '',
          summary: shard['summary']?.toString() ?? '',
          similarity: sim,
          timestamp: shard['timestamp']?.toString() ?? '',
          shardId: shard['shardId']?.toString() ?? '',
          shardRef: shard['shardRef']?.toString() ?? '',
        ));
      }

      // Sort by similarity descending, take top [limit]
      scored.sort((a, b) => b.similarity.compareTo(a.similarity));
      return MemoryQueryResult(
        results: scored.take(limit).toList(),
        query: query,
      );
    } catch (e) {
      print('❌ [MemoryService] queryMemory failed: $e');
      return null;
    }
  }

  /// Pin a memory shard to "facts" — it will always be included in context.
  static Future<bool> pinMemoryToFacts({
    required String personaId,
    required String memoryId,
    required String summary,
    required String shardRef,
  }) async {
    try {
      if (!FirebaseService.isAvailable) return false;
      await FirebaseService.writeData(
        path: 'personas/$personaId/facts/$memoryId',
        data: {
          'summary': summary,
          'shardRef': shardRef,
          'pinnedAt': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      print('❌ [MemoryService] pinMemoryToFacts failed: $e');
      return false;
    }
  }

  /// Mark a memory shard as dismissed — it won't surface in future queries.
  static Future<bool> dismissMemory({
    required String personaId,
    required String memoryId,
    required String shardRef,
  }) async {
    try {
      if (!FirebaseService.isAvailable) return false;
      await FirebaseService.writeData(
        path: 'personas/$personaId/dismissed/$memoryId',
        data: {
          'shardRef': shardRef,
          'dismissedAt': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      print('❌ [MemoryService] dismissMemory failed: $e');
      return false;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static Future<List<double>?> _getEmbedding(String text) async {
    try {
      final apiKey = await AIConfig.getOpenAIKey();
      if (apiKey.isEmpty) return null;

      final response = await _dio.post(
        'https://api.openai.com/v1/embeddings',
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'text-embedding-3-small',
          'input': text.length > 8000 ? text.substring(0, 8000) : text,
        },
      );
      final data = response.data['data'] as List;
      return List<double>.from(data[0]['embedding'] as List);
    } catch (e) {
      print('⚠️ [MemoryService] Embedding failed: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _loadShards(String personaId) async {
    // Try Firebase first
    if (FirebaseService.isAvailable) {
      try {
        final data = await FirebaseService.readData('personas/$personaId/memory/shards');
        if (data != null && data is Map) {
          return data.entries.map((e) {
            final shard = Map<String, dynamic>.from(e.value as Map);
            shard['id'] = e.key;
            return shard;
          }).toList();
        }
      } catch (e) {
        print('⚠️ [MemoryService] Firebase shard load failed: $e');
      }
    }

    // Fall back to local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('memory_shards_$personaId');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (e) {
      print('⚠️ [MemoryService] Local shard load failed: $e');
    }
    return [];
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0.0 : dot / denom;
  }
}
