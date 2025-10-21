import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/usage_tracking_service.dart';

class UsageStatsScreen extends StatefulWidget {
  const UsageStatsScreen({Key? key}) : super(key: key);

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

    final tokens = _sessionData!['tokens'] as int;
    final cost = _sessionData!['cost'] as double;
    final apiCalls = _sessionData!['api_calls'] as int;
    final ttsChars = _sessionData!['tts_characters'] as int;
    final startedAt = _sessionData!['started_at'] as String;

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
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCostCard() {
    final totalCost = _usageData!['total_cost'] as double;
    final totalTokens = _usageData!['total_tokens'] as int;

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
    final totalCost = _usageData!['total_cost'] as double;

    final openaiPercent = totalCost > 0 ? (openaiCost / totalCost * 100) : 0.0;
    final elevenlabsPercent = totalCost > 0 ? (elevenlabsCost / totalCost * 100) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
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
            Row(
              children: const [
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
              final data = entry.value as Map<String, dynamic>;
              final inputTokens = data['input_tokens'] as int;
              final outputTokens = data['output_tokens'] as int;
              final cost = data['total_cost'] as double;
              final calls = data['call_count'] as int;

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
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationUsageCard() {
    final operations = _usageData!['operations'] as Map<String, dynamic>;

    if (operations.isEmpty) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
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
              final data = entry.value as Map<String, dynamic>;
              final count = data['count'] as int;
              final tokens = data['tokens'] as int;
              final cost = data['cost'] as double;

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
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsCard() {
    final totalCost = _usageData!['total_cost'] as double;
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
            Row(
              children: const [
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
