import 'dart:convert';

/// Splits assistant replies into readable reveal chunks for the UI.
///
/// This is deliberately a display concern, not a prompt trick: Kai can still
/// think/write normally, but the app does not drop a whole essay-brick on screen
/// in one frame.
class ReplyChunkerService {
  const ReplyChunkerService();

  List<String> chunks(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const ['(no reply)'];

    final chunks = <String>[];
    final buffer = StringBuffer();
    var inFence = false;

    void flush() {
      final chunk = buffer.toString().trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      buffer.clear();
    }

    for (final line in const LineSplitter().convert(trimmed)) {
      if (line.trimLeft().startsWith('```')) inFence = !inFence;

      if (!inFence && line.trim().isEmpty) {
        flush();
        continue;
      }

      buffer.writeln(line);

      // Long bullets/sections are readable as soon as they finish. Code blocks
      // stay whole so we do not reveal half a fence like a tiny syntax criminal.
      if (!inFence &&
          (line.trimLeft().startsWith('- ') ||
              line.trimLeft().startsWith('• ') ||
              RegExp(r'^#{1,3}\s+').hasMatch(line.trimLeft())) &&
          buffer.length > 420) {
        flush();
      }
    }
    flush();

    return chunks.isEmpty ? const ['(no reply)'] : chunks;
  }
}
