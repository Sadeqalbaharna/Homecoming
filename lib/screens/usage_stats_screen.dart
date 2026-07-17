import 'package:flutter/material.dart';
import '../services/ai/usage_tracking_service.dart';

class UsageStatsScreen extends StatefulWidget {
  const UsageStatsScreen({super.key});

  @override
  State<UsageStatsScreen> createState() => _UsageStatsScreenState();
}

class _UsageStatsScreenState extends State<UsageStatsScreen> {
  Map<String, dynamic>? _usageData;
  Map<String, dynamic>? _sessionData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    setState(() => _isLoading = true);

    final usage = await UsageTrackingService.getUsageStats();
    final session = await UsageTrackingService.getSessionStats();

    setState(() {
      _usageData = usage;
      _sessionData = session;
      _isLoading = false;
    });
  }

  // (A second "Where it goes" card used to live here — mine. Deleted.
  //
  // _buildOperationUsageCard() below is titled "Usage by Operation", has always
  // been wired into the ListView, and reads exactly the per-operation count /
  // tokens / cost I was about to re-invent. It was never populated because the
  // service didn't write the key — a wire, not a missing feature.
  //
  // I told Kai this morning: "before you build anything, search_code for it.
  // it's already there." Then I didn't search, and built the duplicate anyway,
  // three feet from the original. The disease doesn't care who you are.)

  Future<void> _resetStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Statistics?'),
        content: const Text('This will permanently delete all usage tracking data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await UsageTrackingService.resetAllStats();
      await _loadUsageData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All statistics have been reset')),
        );
      }
    }
  }

  Future<void> _resetSession() async {
    await UsageTrackingService.resetSession();
    await _loadUsageData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session statistics reset')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage & Cost Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsageData,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset_session') {
                _resetSession();
              } else if (value == 'reset_all') {
                _resetStats();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset_session',
                child: Text('Reset Session'),
              ),
              const PopupMenuItem(
                value: 'reset_all',
                child: Text('Reset All Stats'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _usageData == null
              ? const Center(child: Text('No usage data available'))
              : RefreshIndicator(
                  onRefresh: _loadUsageData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSessionCard(),
                      const SizedBox(height: 16),
                      _buildTotalCostCard(),
                      const SizedBox(height: 16),
                      _buildCostBreakdownCard(),
                      const SizedBox(height: 16),
                      _buildFirebaseUsageCard(),
                      const SizedBox(height: 16),
                      _buildCloudFunctionsCard(),
                      const SizedBox(height: 16),
                      _buildModelUsageCard(),
                      const SizedBox(height: 16),
                      _buildOperationUsageCard(),
                      const SizedBox(height: 16),
                      _buildInsightsCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSessionCard() {
    if (_sessionData == null) return const SizedBox();

    // ── Every read here is null-safe now, and the keys are the REAL ones ────
    //
    // This screen crashed the app the instant it got a door:
    //   type 'Null' is not a subtype of type 'int' in type cast
    //
    // It was asking for 'api_calls', 'tts_characters', 'firebase_operations',
    // 'search_queries' and 'started_at'. getSessionStats() returns
    // 'openai_calls', 'elevenlabs_chars', 'firebase_reads'/'firebase_writes',
    // 'google_searches' — and no start time at all.
    //
    // The screen and the service drifted apart at some point and NOTHING
    // noticed, because the screen had zero importers. Dead code doesn't stay
    // correct; it stays compile-clean, which is not the same thing and looks
    // identical from the outside. It rotted quietly for months and the rot only
    // became visible the moment someone could walk in.
    //
    // That's the real argument against doorless rooms: not that they're unused,
    // but that they're unverified while looking finished.
    int i(String k) => (_sessionData![k] as num?)?.toInt() ?? 0;
    double d(String k) => (_sessionData![k] as num?)?.toDouble() ?? 0.0;

    final tokens = i('tokens');
    final cost = d('cost');
    final apiCalls = i('openai_calls');
    final ttsChars = i('elevenlabs_chars');
    final firebaseOps = i('firebase_reads') + i('firebase_writes');
    final functionCalls = i('function_calls');
    final searchQueries = i('google_searches');
    final startedAt = (_sessionData!['started_at'] as String?) ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Current Session',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _resetSession,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Started: ${_formatDateTime(startedAt)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const Divider(height: 24),
            _buildStatRow('Total Cost', UsageTrackingService.formatCost(cost), Colors.green),
            _buildStatRow('API Calls', apiCalls.toString(), Colors.blue),
            _buildStatRow('Tokens Used', UsageTrackingService.formatTokens(tokens), Colors.orange),
            _buildStatRow('TTS Characters', UsageTrackingService.formatTokens(ttsChars), Colors.purple),
            if (firebaseOps > 0)
              _buildStatRow('Firebase Operations', firebaseOps.toString(), Colors.orange),
            if (functionCalls > 0)
              _buildStatRow('Function Calls', functionCalls.toString(), Colors.blue),
            if (searchQueries > 0)
              _buildStatRow('Search Queries', searchQueries.toString(), Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCostCard() {
    // Null-safe: same reason as _buildSessionCard. A missing key must render a
    // zero, not take the whole app down.
    final totalCost = (_usageData!['total_cost'] as num?)?.toDouble() ?? 0.0;
    final totalTokens = (_usageData!['total_tokens'] as num?)?.toInt() ?? 0;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Total Lifetime Cost',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              UsageTrackingService.formatCost(totalCost),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${UsageTrackingService.formatTokens(totalTokens)} tokens',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostBreakdownCard() {
    final openaiCost = _usageData!['openai_cost'] as double;
    final elevenlabsCost = _usageData!['elevenlabs_cost'] as double;
    final firebaseCost = _usageData!['firebase_cost'] as double? ?? 0.0;
    final functionsCost = _usageData!['functions_cost'] as double? ?? 0.0;
    final googleCost = _usageData!['google_cost'] as double? ?? 0.0;
    final totalCost = _usageData!['total_cost'] as double;

    final openaiPercent = totalCost > 0 ? (openaiCost / totalCost * 100) : 0.0;
    final elevenlabsPercent = totalCost > 0 ? (elevenlabsCost / totalCost * 100) : 0.0;
    final firebasePercent = totalCost > 0 ? (firebaseCost / totalCost * 100) : 0.0;
    final functionsPercent = totalCost > 0 ? (functionsCost / totalCost * 100) : 0.0;
    final googlePercent = totalCost > 0 ? (googleCost / totalCost * 100) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart, size: 20),
                SizedBox(width: 8),
                Text(
                  'Cost Breakdown',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCostBreakdownRow(
              'OpenAI (Chat & Embeddings)',
              openaiCost,
              openaiPercent,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildCostBreakdownRow(
              'ElevenLabs (TTS)',
              elevenlabsCost,
              elevenlabsPercent,
              Colors.purple,
            ),
            const SizedBox(height: 12),
            _buildCostBreakdownRow(
              'Firebase (Database)',
              firebaseCost,
              firebasePercent,
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildCostBreakdownRow(
              'Cloud Functions',
              functionsCost,
              functionsPercent,
              Colors.blue,
            ),
            if (googleCost > 0) ...[
              const SizedBox(height: 12),
              _buildCostBreakdownRow(
                'Google Search API',
                googleCost,
                googlePercent,
                Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCostBreakdownRow(String label, double cost, double percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              UsageTrackingService.formatCost(cost),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: percent / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFirebaseUsageCard() {
    final firebaseReads = _usageData!['firebase_reads'] as int? ?? 0;
    final firebaseWrites = _usageData!['firebase_writes'] as int? ?? 0;
    final firebaseCost = _usageData!['firebase_cost'] as double? ?? 0.0;

    if (firebaseReads == 0 && firebaseWrites == 0) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud, size: 20, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Firebase Database',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('Total Operations', '${firebaseReads + firebaseWrites}', Colors.orange),
            _buildStatRow('Reads', firebaseReads.toString(), Colors.blue),
            _buildStatRow('Writes', firebaseWrites.toString(), Colors.green),
            _buildStatRow('Cost', UsageTrackingService.formatCost(firebaseCost), Colors.orange),
            const SizedBox(height: 8),
            Text(
              'Pricing: \$1.00/100K reads, \$5.00/100K writes',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudFunctionsCard() {
    final functionInvocations = _usageData!['function_invocations'] as int? ?? 0;
    final functionComputeSeconds = _usageData!['function_compute_seconds'] as double? ?? 0.0;
    final functionsCost = _usageData!['functions_cost'] as double? ?? 0.0;
    final functions = _usageData!['functions'] as Map<String, dynamic>? ?? {};

    if (functionInvocations == 0) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.functions, size: 20, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Cloud Functions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('Total Invocations', functionInvocations.toString(), Colors.blue),
            _buildStatRow('Compute Time', '${functionComputeSeconds.toStringAsFixed(2)}s', Colors.purple),
            _buildStatRow('Total Cost', UsageTrackingService.formatCost(functionsCost), Colors.blue),
            if (functions.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                'Per-Function Breakdown',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...functions.entries.map((entry) {
                final functionName = entry.key;
                final data = entry.value as Map<String, dynamic>;
                final invocations = data['invocations'] as int? ?? 0;
                final cost = data['cost'] as double? ?? 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          functionName,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '$invocations calls',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        UsageTrackingService.formatCost(cost),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 8),
            Text(
              'Pricing: \$0.40/1M invocations + \$0.0000025/GB-second',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelUsageCard() {
    final models = _usageData!['models'] as Map<String, dynamic>;

    if (models.isEmpty) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology, size: 20),
                SizedBox(width: 8),
                Text(
                  'Model Usage',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...models.entries.map((entry) {
              final modelName = entry.key;
              // Firebase hands back Map<Object?, Object?>, never
              // Map<String, dynamic> — so the old cast was a second crash
              // waiting behind the first.
              final data = Map<String, dynamic>.from(entry.value as Map);
              final inputTokens = (data['input_tokens'] as num?)?.toInt() ?? 0;
              final outputTokens = (data['output_tokens'] as num?)?.toInt() ?? 0;
              final cost = (data['total_cost'] as num?)?.toDouble() ?? 0.0;
              final calls = (data['call_count'] as num?)?.toInt() ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          modelName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          UsageTrackingService.formatCost(cost),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$calls calls • ${UsageTrackingService.formatTokens(inputTokens + outputTokens)} tokens',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      'In: ${UsageTrackingService.formatTokens(inputTokens)} • Out: ${UsageTrackingService.formatTokens(outputTokens)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationUsageCard() {
    // Null-safe: this key genuinely didn't exist until now, and a screen that
    // can't open is a screen whose casts are never tested.
    final operations =
        Map<String, dynamic>.from(_usageData!['operations'] as Map? ?? const {});

    if (operations.isEmpty) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.category, size: 20),
                SizedBox(width: 8),
                Text(
                  'Usage by Operation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...operations.entries.map((entry) {
              final opName = entry.key;
              final data = Map<String, dynamic>.from(entry.value as Map);
              final count = (data['count'] as num?)?.toInt() ?? 0;
              final tokens = (data['tokens'] as num?)?.toInt() ?? 0;
              final cost = (data['cost'] as num?)?.toDouble() ?? 0.0;

              final icon = _getOperationIcon(opName);
              final displayName = _getOperationDisplayName(opName);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$count calls • ${UsageTrackingService.formatTokens(tokens)} tokens',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      UsageTrackingService.formatCost(cost),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsCard() {
    final operations = _usageData!['operations'] as Map<String, dynamic>;
    final chatOp = operations['chat'] as Map<String, dynamic>?;
    
    final avgCostPerChat = chatOp != null && chatOp['count'] > 0
        ? (chatOp['cost'] as double) / (chatOp['count'] as int)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, size: 20),
                SizedBox(width: 8),
                Text(
                  'Insights',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (chatOp != null) ...[
              _buildInsightRow(
                Icons.chat,
                'Average cost per conversation',
                UsageTrackingService.formatCost(avgCostPerChat),
              ),
              const SizedBox(height: 12),
            ],
            _buildInsightRow(
              Icons.calculate,
              'Estimated monthly cost (30 days)',
              UsageTrackingService.formatCost(_estimateMonthlyCost()),
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.trending_down,
              'Most expensive model',
              _getMostExpensiveModel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  IconData _getOperationIcon(String operation) {
    switch (operation) {
      case 'chat':
        return Icons.chat;
      case 'tags':
        return Icons.label;
      case 'embedding':
        return Icons.memory;
      default:
        return Icons.api;
    }
  }

  String _getOperationDisplayName(String operation) {
    switch (operation) {
      case 'chat':
        return 'Chat Messages';
      case 'tags':
        return 'Personality Analysis';
      case 'embedding':
        return 'Memory Embeddings';
      default:
        return operation;
    }
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return 'Just now';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (e) {
      return isoString;
    }
  }

  double _estimateMonthlyCost() {
    final sessionCost = _sessionData?['cost'] as double? ?? 0.0;
    final startedAtStr = _sessionData?['started_at'] as String?;
    
    if (startedAtStr == null || sessionCost == 0) {
      return 0.0;
    }

    try {
      final startedAt = DateTime.parse(startedAtStr);
      final now = DateTime.now();
      final sessionHours = now.difference(startedAt).inHours;
      
      if (sessionHours < 1) {
        // Less than an hour, extrapolate from minutes
        final sessionMinutes = now.difference(startedAt).inMinutes;
        if (sessionMinutes < 1) return 0.0;
        return (sessionCost / sessionMinutes) * 60 * 24 * 30;
      }
      
      // Extrapolate based on hours
      final costPerHour = sessionCost / sessionHours;
      return costPerHour * 24 * 30;
    } catch (e) {
      return 0.0;
    }
  }

  String _getMostExpensiveModel() {
    final models = _usageData!['models'] as Map<String, dynamic>;
    
    if (models.isEmpty) {
      return 'N/A';
    }

    String mostExpensive = '';
    double highestCost = 0.0;

    for (final entry in models.entries) {
      final data = entry.value as Map<String, dynamic>;
      final cost = data['total_cost'] as double;
      
      if (cost > highestCost) {
        highestCost = cost;
        mostExpensive = entry.key;
      }
    }

    return mostExpensive.isNotEmpty ? mostExpensive : 'N/A';
  }
}
