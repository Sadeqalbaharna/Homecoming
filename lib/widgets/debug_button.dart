import 'package:flutter/material.dart';

/// Debug button widget that shows detailed AI decision-making information
class DebugButton extends StatefulWidget {
  final Map<String, dynamic> debugInfo;

  const DebugButton({super.key, required this.debugInfo});

  @override
  State<DebugButton> createState() => _DebugButtonState();
}

class _DebugButtonState extends State<DebugButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.cyan,
            side: const BorderSide(color: Colors.cyan),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: Icon(_expanded ? Icons.bug_report : Icons.bug_report_outlined, size: 16),
          label: const Text('Debug', style: TextStyle(fontSize: 12)),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyan.withOpacity(0.5)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Memory Query', widget.debugInfo['memory_query']),
                  const Divider(color: Colors.cyan, height: 24),
                  _buildSection('Personality', widget.debugInfo['personality']),
                  const Divider(color: Colors.cyan, height: 24),
                  _buildSection('Mood', widget.debugInfo['mood']),
                  const Divider(color: Colors.cyan, height: 24),
                  _buildSection('Affinity', widget.debugInfo['affinity']),
                  const Divider(color: Colors.cyan, height: 24),
                  _buildSection('Other', {
                    'model': widget.debugInfo['model'],
                    'conversation_history_turns': widget.debugInfo['conversation_history_turns'],
                    'tags': widget.debugInfo['tags'],
                  }),
                  const Divider(color: Colors.cyan, height: 24),
                  ExpansionTile(
                    title: const Text(
                      'System Prompt',
                      style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SelectableText(
                          widget.debugInfo['system_prompt'] ?? 'N/A',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSection(String title, dynamic data) {
    if (data == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.cyan,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        if (data is Map<String, dynamic>) ...[
          ...data.entries.map((e) => _buildKeyValue(e.key, e.value)),
        ] else
          Text(
            data.toString(),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
      ],
    );
  }

  Widget _buildKeyValue(String key, dynamic value) {
    if (key == 'memory_details' && value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$key:',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ...value.map((item) {
            final included = item['included'] ?? false;
            final similarity = ((item['similarity'] ?? 0.0) * 100).toStringAsFixed(1);
            return Container(
              margin: const EdgeInsets.only(bottom: 8, left: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: included ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: included ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        included ? Icons.check_circle : Icons.cancel,
                        color: included ? Colors.green : Colors.red,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$similarity% similarity',
                        style: TextStyle(
                          color: included ? Colors.green : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (included)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'USED',
                            style: TextStyle(color: Colors.purple, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['summary'] ?? 'N/A',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${item['id']}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      );
    }

    if (key == 'memory_context' || key == 'system_prompt') {
      return const SizedBox.shrink(); // Skip these, shown separately
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$key: ',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              _formatValue(value),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value is Map) {
      return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    if (value is List) {
      return value.join(', ');
    }
    return value.toString();
  }
}
