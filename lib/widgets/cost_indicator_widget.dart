import 'package:flutter/material.dart';
import '../services/usage_tracking_service.dart';

class CostIndicatorWidget extends StatefulWidget {
  const CostIndicatorWidget({Key? key}) : super(key: key);

  @override
  State<CostIndicatorWidget> createState() => _CostIndicatorWidgetState();
}

class _CostIndicatorWidgetState extends State<CostIndicatorWidget> {
  double _sessionCost = 0.0;
  int _apiCalls = 0;
  
  @override
  void initState() {
    super.initState();
    _loadSessionCost();
  }

  Future<void> _loadSessionCost() async {
    final session = await UsageTrackingService.getSessionStats();
    if (mounted) {
      setState(() {
        _sessionCost = session['cost'] as double;
        _apiCalls = session['api_calls'] as int;
      });
    }
  }

  Future<void> _showUsageDialog() async {
    final stats = await UsageTrackingService.getUsageStats();
    final session = await UsageTrackingService.getSessionStats();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usage Summary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDialogSection(
                'Current Session',
                [
                  _buildDialogRow('Cost', UsageTrackingService.formatCost(session['cost'] as double)),
                  _buildDialogRow('API Calls', (session['api_calls'] as int).toString()),
                  _buildDialogRow('Tokens', UsageTrackingService.formatTokens(session['tokens'] as int)),
                ],
              ),
              const Divider(height: 24),
              _buildDialogSection(
                'Lifetime Total',
                [
                  _buildDialogRow('Total Cost', UsageTrackingService.formatCost(stats['total_cost'] as double)),
                  _buildDialogRow('Total Tokens', UsageTrackingService.formatTokens(stats['total_tokens'] as int)),
                  _buildDialogRow('OpenAI', UsageTrackingService.formatCost(stats['openai_cost'] as double)),
                  _buildDialogRow('ElevenLabs', UsageTrackingService.formatCost(stats['elevenlabs_cost'] as double)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/usage-stats');
            },
            child: const Text('View Details'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showUsageDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_money,
              color: Colors.green,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _sessionCost < 0.01
                  ? '<\$0.01'
                  : '\$${_sessionCost.toStringAsFixed(3)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 16,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(width: 8),
            Text(
              '$_apiCalls calls',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A floating action button style cost indicator
class FloatingCostIndicator extends StatefulWidget {
  final VoidCallback? onTap;
  
  const FloatingCostIndicator({Key? key, this.onTap}) : super(key: key);

  @override
  State<FloatingCostIndicator> createState() => _FloatingCostIndicatorState();
}

class _FloatingCostIndicatorState extends State<FloatingCostIndicator> {
  double _sessionCost = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCost();
  }

  Future<void> _loadCost() async {
    final session = await UsageTrackingService.getSessionStats();
    if (mounted) {
      setState(() {
        _sessionCost = session['cost'] as double;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: widget.onTap,
      backgroundColor: Colors.green.shade600,
      icon: const Icon(Icons.paid, size: 20),
      label: Text(
        UsageTrackingService.formatCost(_sessionCost),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
