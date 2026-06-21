import 'package:flutter/material.dart';
import '../services/ai/memory_service.dart';

/// Debug button widget that displays AI decision-making data
class DebugButton extends StatefulWidget {
  final Map<String, dynamic> debugInfo;
  final String personaId;

  const DebugButton({
    super.key,
    required this.debugInfo,
    required this.personaId,
  });

  @override
  State<DebugButton> createState() => _DebugButtonState();
}

class _DebugButtonState extends State<DebugButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Expandable button
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          label: const Text('Debug Info'),
        ),

        // Debug info panel
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.cyan.shade900.withOpacity(0.2),
              border: Border.all(color: Colors.cyan.shade700),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Memory Query Section
                  if (widget.debugInfo['memory_query'] != null)
                    _buildSection('Memory Query', widget.debugInfo['memory_query']),

                  const SizedBox(height: 12),

                  // Personality Section
                  if (widget.debugInfo['personality'] != null)
                    _buildSection('Personality', widget.debugInfo['personality']),

                  const SizedBox(height: 12),

                  // Mood Section
                  if (widget.debugInfo['mood'] != null)
                    _buildSection('Mood', widget.debugInfo['mood']),

                  const SizedBox(height: 12),

                  // Affinity Section
                  if (widget.debugInfo['affinity'] != null)
                    _buildSection('Affinity', widget.debugInfo['affinity']),

                  const SizedBox(height: 12),

                  // Other info
                  _buildSection('Other', {
                    'model': widget.debugInfo['model'],
                    'conversation_history_turns': widget.debugInfo['conversation_history_turns'],
                    'tags': widget.debugInfo['tags'],
                  }),

                  const SizedBox(height: 12),

                  // System Prompt (expandable)
                  if (widget.debugInfo['system_prompt'] != null)
                    ExpansionTile(
                      title: const Text(
                        'System Prompt',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            widget.debugInfo['system_prompt'],
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
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

  Widget _buildSection(String title, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.cyan,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        ...data.entries.map((e) => _buildKeyValue(e.key, e.value)),
      ],
    );
  }

  Widget _buildKeyValue(String key, dynamic value) {
    // Special handling for memory_details
    if (key == 'memory_details' && value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Memory Details:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...value.map((item) {
            final included = item['included'] ?? false;
            final similarity = ((item['similarity'] ?? 0.0) * 100).toStringAsFixed(1);
            final memoryId = item['id'] ?? '';
            final summary = item['summary'] ?? '';
            final shardRef = item['shard_ref'] ?? '';
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: included 
                    ? Colors.green.withOpacity(0.1) 
                    : Colors.red.withOpacity(0.1),
                border: Border.all(
                  color: included 
                      ? Colors.green.withOpacity(0.5) 
                      : Colors.red.withOpacity(0.5),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        included ? Icons.check_circle : Icons.cancel,
                        color: included ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Similarity: $similarity%',
                        style: TextStyle(
                          color: included ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (included) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'USED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Summary: $summary',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: $memoryId',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Action buttons
                  Row(
                    children: [
                      // Pin to Facts button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (memoryId.isEmpty || summary.isEmpty || shardRef.isEmpty) {
                              _showSnackBar('Missing memory data', isError: true);
                              return;
                            }
                            
                            final success = await MemoryService.pinMemoryToFacts(
                              personaId: widget.personaId,
                              memoryId: memoryId,
                              summary: summary,
                              shardRef: shardRef,
                            );
                            
                            if (success) {
                              _showSnackBar('Memory pinned to facts ✓');
                            } else {
                              _showSnackBar('Failed to pin memory', isError: true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: const Icon(Icons.push_pin, size: 14),
                          label: const Text(
                            'Pin',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Dismiss button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (memoryId.isEmpty || shardRef.isEmpty) {
                              _showSnackBar('Missing memory data', isError: true);
                              return;
                            }
                            
                            final success = await MemoryService.dismissMemory(
                              personaId: widget.personaId,
                              memoryId: memoryId,
                              shardRef: shardRef,
                            );
                            
                            if (success) {
                              _showSnackBar('Memory dismissed ✓');
                            } else {
                              _showSnackBar('Failed to dismiss memory', isError: true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text(
                            'Dismiss',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$key: ${_formatValue(value)}',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
    }
    if (value is List) {
      return value.join(', ');
    }
    return value.toString();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

