// Memory Chips Widget
// Shows memories used in a response with pin/dismiss actions

import 'package:flutter/material.dart';

class MemoryChips extends StatelessWidget {
  final List<Map<String, dynamic>> memoryDetails;
  final Function(String memoryId)? onPin;
  final Function(String memoryId)? onDismiss;

  const MemoryChips({
    Key? key,
    required this.memoryDetails,
    this.onPin,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Filter to only show included memories
    final usedMemories = memoryDetails
        .where((m) => m['included'] == true)
        .toList();

    if (usedMemories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.psychology,
                size: 14,
                color: Colors.purple.shade300,
              ),
              const SizedBox(width: 4),
              Text(
                'Used ${usedMemories.length} ${usedMemories.length == 1 ? "memory" : "memories"}:',
                style: TextStyle(
                  color: Colors.purple.shade300,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Memory chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: usedMemories.map((memory) {
              return _buildMemoryChip(memory);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryChip(Map<String, dynamic> memory) {
    final similarity = ((memory['similarity'] ?? 0.0) * 100).toStringAsFixed(0);
    final summary = memory['summary'] as String? ?? 'Unknown';
    final memoryId = memory['id'] as String? ?? '';
    
    // Truncate summary to ~50 chars
    final displaySummary = summary.length > 50 
        ? '${summary.substring(0, 47)}...' 
        : summary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.purple.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary and similarity
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    displaySummary,
                    style: TextStyle(
                      color: Colors.purple.shade200,
                      fontSize: 11,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$similarity%',
                    style: TextStyle(
                      color: Colors.purple.shade100,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pin button
                if (onPin != null)
                  _ActionButton(
                    icon: Icons.push_pin_outlined,
                    label: 'Pin',
                    onTap: () => onPin!(memoryId),
                  ),
                if (onPin != null && onDismiss != null)
                  const SizedBox(width: 4),
                // Dismiss button
                if (onDismiss != null)
                  _ActionButton(
                    icon: Icons.close,
                    label: 'Dismiss',
                    onTap: () => onDismiss!(memoryId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: Colors.purple.shade300,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.purple.shade300,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
