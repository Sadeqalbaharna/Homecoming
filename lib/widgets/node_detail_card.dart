/// Node Detail Card - Shows information about selected node
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/knowledge_node.dart';

class NodeDetailCard extends StatelessWidget {
  final KnowledgeNode node;
  final KnowledgeGraph graph;
  final VoidCallback onClose;
  final Function(KnowledgeNode) onPinMemory;

  const NodeDetailCard({
    super.key,
    required this.node,
    required this.graph,
    required this.onClose,
    required this.onPinMemory,
  });

  @override
  Widget build(BuildContext context) {
    final connectedNodes = graph.getConnectedNodes(node.id);
    
    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 600),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: node.color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: node.color.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: node.color.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Type emoji
                Text(
                  node.emoji,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                
                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatNodeType(node.type),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                  iconSize: 20,
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp
                  _buildInfoRow(
                    icon: Icons.access_time,
                    label: 'First mentioned',
                    value: _formatDate(node.timestamp),
                  ),
                  const SizedBox(height: 12),
                  
                  // Importance
                  _buildInfoRow(
                    icon: Icons.star,
                    label: 'Importance',
                    value: _formatImportance(node.importance),
                  ),
                  const SizedBox(height: 12),
                  
                  // Connections
                  _buildInfoRow(
                    icon: Icons.hub,
                    label: 'Connections',
                    value: '${connectedNodes.length}',
                  ),
                  const SizedBox(height: 16),
                  
                  // Tags
                  if (node.tags.isNotEmpty) ...[
                    const Text(
                      'Tags',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: node.tags.map((tag) {
                        return Chip(
                          label: Text(tag),
                          labelStyle: const TextStyle(fontSize: 10),
                          backgroundColor: node.color.withOpacity(0.3),
                          padding: EdgeInsets.zero,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Metadata (for conversation nodes)
                  if (node.type == NodeType.conversation && 
                      node.metadata.containsKey('userMessage')) ...[
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    const Text(
                      'Conversation',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildConversationBubble(
                      'You',
                      node.metadata['userMessage'] as String,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildConversationBubble(
                      'Kai',
                      node.metadata['aiResponse'] as String,
                      Colors.purple,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Connected nodes
                  if (connectedNodes.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    const Text(
                      'Connected to',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...connectedNodes.take(10).map((connectedNode) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              connectedNode.emoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                connectedNode.label,
                                style: TextStyle(
                                  color: connectedNode.color,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (connectedNodes.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${connectedNodes.length - 10} more...',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          
          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onPinMemory(node),
                    icon: const Icon(Icons.push_pin, size: 16),
                    label: const Text('Pin', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Share functionality
                    },
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildConversationBubble(String sender, String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sender,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message.length > 200 ? '${message.substring(0, 200)}...' : message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNodeType(NodeType type) {
    return type.name[0].toUpperCase() + type.name.substring(1);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today at ${DateFormat('HH:mm').format(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  String _formatImportance(double importance) {
    if (importance >= 0.8) return '⭐⭐⭐⭐⭐ Very High';
    if (importance >= 0.6) return '⭐⭐⭐⭐ High';
    if (importance >= 0.4) return '⭐⭐⭐ Medium';
    if (importance >= 0.2) return '⭐⭐ Low';
    return '⭐ Very Low';
  }
}
