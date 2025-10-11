// lib/features/shell/ui/model_chip.dart
part of floating_kai;

/* ================================== MODEL CHIP =================================== */

class _ModelChip extends StatelessWidget {
  final String modelId;
  final ValueChanged<String> onChanged;
  final Color color;
  const _ModelChip(
      {required this.modelId, required this.onChanged, required this.color});
  @override
  Widget build(BuildContext context) {
    final label = modelId == 'gpt-5' ? 'GPT-5' : 'GPT-4o';
    return PopupMenuButton<String>(
      tooltip: 'Model',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'gpt-4o', child: Text('GPT-4o')),
        PopupMenuItem(value: 'gpt-5', child: Text('GPT-5')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.memory, size: 16, color: Colors.amber),
            SizedBox(width: 6),
            Text('Model', style: TextStyle(color: Colors.white)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
