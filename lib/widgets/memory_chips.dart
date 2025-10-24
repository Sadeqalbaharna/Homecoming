// Memory Chips Widget
// Shows memories used in a response with pin/dismiss actions

import 'package:flutter/material.dart';

class MemoryChips extends StatelessWidget {
  final List<Map<String, dynamic>> memoryDetails;

  const MemoryChips({
    super.key,
    required this.memoryDetails,
  });

  @override
  Widget build(BuildContext context) {
    // Filter to only show included memories
    final usedMemories = memoryDetails
        .where((m) => m['included'] == true)
        .toList();

    if (usedMemories.isEmpty) {
      return const SizedBox.shrink();
    }

    // Just show a simple one-line summary
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.purple.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology,
            size: 12,
            color: Colors.purple.shade300,
          ),
          const SizedBox(width: 4),
          Text(
            'Used ${usedMemories.length} ${usedMemories.length == 1 ? "memory" : "memories"}',
            style: TextStyle(
              color: Colors.purple.shade300,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
