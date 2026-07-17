// Memory Golden Test Runner
// Executes golden test set and reports results

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/memory_service.dart';
import 'memory_golden_data.dart';

/// Run all golden tests and return results
Future<List<MemoryTestResult>> runGoldenTests({
  required String personaId,
  String version = 'unknown',
  MemoryEmbeddingProvider? embeddingProvider,
  MemoryShardLoader? shardLoader,
  MemoryQuerySideEffects sideEffects = MemoryQuerySideEffects.enabled,
}) async {
  final results = <MemoryTestResult>[];
  
  print('\n🧪 Running Memory Golden Tests (v$version)...\n');
  
  for (final test in goldenTests) {
    try {
      // Query memory service
      final response = await MemoryService.queryMemory(
        personaId: personaId,
        query: test.query,
        limit: 5,
        embeddingProvider: embeddingProvider,
        shardLoader: shardLoader,
        sideEffects: sideEffects,
      );
      
      // Check if we got results
      if (response == null || response.results.isEmpty) {
        // For negative cases (no expected keywords), this is a pass
        if (test.expectedKeywords.isEmpty) {
          results.add(MemoryTestResult(
            test: test,
            passed: true,
            actualSimilarity: 0.0,
            foundKeywords: [],
          ));
          continue;
        }
        
        // For positive cases, this is a fail
        results.add(MemoryTestResult(
          test: test,
          passed: false,
          actualSimilarity: 0.0,
          foundKeywords: [],
          errorMessage: 'No memories returned',
        ));
        continue;
      }
      
      // Get top result
      final topResult = response.results.first;
      final similarity = topResult.similarity;
      
      // Check if similarity meets minimum
      if (similarity < test.minSimilarity) {
        results.add(MemoryTestResult(
          test: test,
          passed: false,
          actualSimilarity: similarity,
          foundKeywords: [],
          errorMessage: 'Similarity ${(similarity * 100).toStringAsFixed(1)}% < ${(test.minSimilarity * 100).toStringAsFixed(0)}%',
        ));
        continue;
      }
      
      // Check for expected keywords in summary
      final summary = topResult.summary.toLowerCase();
      final foundKeywords = test.expectedKeywords
          .where((keyword) => summary.contains(keyword.toLowerCase()))
          .toList();
      
      // For negative tests, finding keywords is a failure
      if (test.expectedKeywords.isEmpty) {
        results.add(MemoryTestResult(
          test: test,
          passed: similarity < 0.3, // Should be low similarity
          actualSimilarity: similarity,
          foundKeywords: [],
          errorMessage: similarity >= 0.3 ? 'Unexpected match for negative test' : null,
        ));
        continue;
      }
      
      // For positive tests, need at least one keyword match
      final passed = foundKeywords.isNotEmpty;
      
      results.add(MemoryTestResult(
        test: test,
        passed: passed,
        actualSimilarity: similarity,
        foundKeywords: foundKeywords,
        errorMessage: passed ? null : 'No expected keywords found in: "$summary"',
      ));
      
    } catch (e) {
      results.add(MemoryTestResult(
        test: test,
        passed: false,
        actualSimilarity: 0.0,
        foundKeywords: [],
        errorMessage: 'Exception: $e',
      ));
    }
  }
  
  return results;
}

/// Print detailed test results
void printTestResults(List<MemoryTestResult> results, String version) {
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📋 DETAILED TEST RESULTS');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  
  for (final result in results) {
    print(result);
  }
  
  final summary = TestRunSummary(
    total: results.length,
    passed: results.where((r) => r.passed).length,
    failed: results.where((r) => r.failed).length,
    timestamp: DateTime.now(),
    version: version,
  );
  
  print(summary);
  
  // Save results to file for tracking
  // TODO: Add file logging
}

/// Main test function for Flutter test framework
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Memory Golden Tests', () {
    test('Run all golden tests', () async {
      final results = await runGoldenTests(
        personaId: 'truekai',
        version: '0.7.4+47',
      );
      
      printTestResults(results, '0.7.4+47');
      
      // Assert that at least 80% of tests pass
      final passRate = results.where((r) => r.passed).length / results.length;
      expect(passRate, greaterThanOrEqualTo(0.8), 
        reason: 'Pass rate ${(passRate * 100).toStringAsFixed(1)}% is below 80% threshold');
    });
  });
}
