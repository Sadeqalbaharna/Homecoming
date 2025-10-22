// Golden Test Set for Memory System
// Run this before and after any memory changes to prevent regressions

import 'package:flutter_test/flutter_test.dart';

/// A single test case for memory recall quality
class MemoryTest {
  final String query;
  final List<String> expectedKeywords;
  final double minSimilarity;
  final String? expectedMemoryId;
  final String description;

  MemoryTest({
    required this.query,
    required this.expectedKeywords,
    required this.minSimilarity,
    this.expectedMemoryId,
    required this.description,
  });
}

/// Golden test set - these should ALWAYS pass
final List<MemoryTest> goldenTests = [
  // User Preferences
  MemoryTest(
    query: "What units do I use for weight?",
    expectedKeywords: ["kg", "kilogram", "metric"],
    minSimilarity: 0.7,
    description: "Should recall metric unit preference",
  ),
  
  MemoryTest(
    query: "What timezone am I in?",
    expectedKeywords: ["bahrain", "asia/bahrain", "utc+3"],
    minSimilarity: 0.7,
    description: "Should recall timezone preference",
  ),

  // Hobbies & Interests
  MemoryTest(
    query: "What are my hobbies?",
    expectedKeywords: ["gaming", "digimon", "game"],
    minSimilarity: 0.35,
    description: "Should recall gaming hobby at 35% threshold",
  ),

  MemoryTest(
    query: "Tell me about my interests",
    expectedKeywords: ["gaming", "digimon", "interests"],
    minSimilarity: 0.35,
    description: "Should match hobbies query with different phrasing",
  ),

  // Projects
  MemoryTest(
    query: "What is Homecoming?",
    expectedKeywords: ["homecoming", "app", "ai", "companion"],
    minSimilarity: 0.5,
    description: "Should know about Homecoming project",
  ),

  MemoryTest(
    query: "Tell me about Tavern",
    expectedKeywords: ["tavern", "brunch", "friday", "content"],
    minSimilarity: 0.5,
    description: "Should know about Tavern brunch project",
  ),

  MemoryTest(
    query: "What is Lionheart?",
    expectedKeywords: ["lionheart", "fitness", "workout", "training"],
    minSimilarity: 0.5,
    description: "Should know about Lionheart fitness project",
  ),

  // Context & Relationships
  MemoryTest(
    query: "Who is building this app?",
    expectedKeywords: ["sadeq", "developer", "building"],
    minSimilarity: 0.6,
    description: "Should know Sadeq is the developer",
  ),

  // Negative cases - should NOT match
  MemoryTest(
    query: "What's the weather like?",
    expectedKeywords: [],
    minSimilarity: 0.0,
    description: "Should NOT find memories for unrelated queries (weather)",
  ),

  MemoryTest(
    query: "Tell me a joke",
    expectedKeywords: [],
    minSimilarity: 0.0,
    description: "Should NOT find memories for generic requests (jokes)",
  ),
];

/// Test result for tracking pass/fail
class MemoryTestResult {
  final MemoryTest test;
  final bool passed;
  final double actualSimilarity;
  final List<String> foundKeywords;
  final String? errorMessage;

  MemoryTestResult({
    required this.test,
    required this.passed,
    required this.actualSimilarity,
    required this.foundKeywords,
    this.errorMessage,
  });

  @override
  String toString() {
    final status = passed ? '✅ PASS' : '❌ FAIL';
    final similarity = '${(actualSimilarity * 100).toStringAsFixed(1)}%';
    final keywords = foundKeywords.isEmpty ? 'none' : foundKeywords.join(', ');
    
    return '''
$status: ${test.description}
  Query: "${test.query}"
  Expected: ${test.expectedKeywords.join(', ')} (≥${(test.minSimilarity * 100).toStringAsFixed(0)}%)
  Found: $keywords ($similarity)
  ${errorMessage != null ? 'Error: $errorMessage' : ''}
''';
  }
}

/// Summary statistics for test run
class TestRunSummary {
  final int total;
  final int passed;
  final int failed;
  final DateTime timestamp;
  final String version;

  TestRunSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.timestamp,
    required this.version,
  });

  double get passRate => total > 0 ? (passed / total) * 100 : 0;

  @override
  String toString() {
    return '''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 MEMORY GOLDEN TEST SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Version: $version
Timestamp: ${timestamp.toIso8601String()}
Total Tests: $total
✅ Passed: $passed
❌ Failed: $failed
📈 Pass Rate: ${passRate.toStringAsFixed(1)}%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
  }

  /// Convert to JSON for logging
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'timestamp': timestamp.toIso8601String(),
      'total': total,
      'passed': passed,
      'failed': failed,
      'pass_rate': passRate,
    };
  }
}

// Note: Actual test implementation will be in a separate file
// This file just defines the test cases and data structures
