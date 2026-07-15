// lib/widgets/kai_rich_text.dart
// KaiRichText — renders the markdown Kai actually writes.
//
// He types like everyone types now: **bold**, `code`, fenced code blocks,
// - bullets, and ### headings. Rendered as plain Text those come out as literal
// asterisks/backticks/hashes, which makes a careful answer look like a broken
// template — and makes HIM look careless, when he wasn't.
//
// Deliberately hand-rolled instead of pulling in flutter_markdown:
//   • no new dependency (no pub get, nothing to break on Windows)
//   • flutter_markdown renders like a document; this renders like a HUD, which
//     is the whole point of the room he lives in
//   • we only need the handful of things he actually uses
//
// Supports: **bold**, *italic*, `code`, fenced ``` code blocks, - / • bullets,
// 1. lists, and ### headings. Anything unrecognised falls through as plain text,
// so a weird edge case degrades to "readable" rather than "mangled".
library;

import 'package:flutter/material.dart';

class KaiRichText extends StatelessWidget {
  final String text;
  final Color color;
  final Color accent;
  final double fontSize;

  /// Desktop chat bubbles need to behave like real text, not a museum plaque.
  /// When true, inline markdown still renders, but normal prose can be dragged,
  /// selected, and copied with normal platform shortcuts.
  ///
  /// Fenced code blocks intentionally become their own selectable panels so code
  /// is visually separate from the surrounding answer and easy to copy alone.
  final bool selectable;

  const KaiRichText({
    super.key,
    required this.text,
    required this.color,
    required this.accent,
    this.fontSize = 13.5,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);

    // Preserve the old full-bubble copy behaviour for ordinary prose. Only split
    // into widgets when there is an actual fenced code panel to separate.
    if (selectable && blocks.length == 1 && !blocks.first.isCode) {
      return SelectableText.rich(
        _documentSpan(blocks.first.text),
        cursorColor: accent,
        selectionControls: materialTextSelectionControls,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          if (blocks[i].isCode)
            _codeBlock(blocks[i].text)
          else if (selectable)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText.rich(
                _documentSpan(blocks[i].text),
                cursorColor: accent,
                selectionControls: materialTextSelectionControls,
              ),
            )
          else
            ..._textWidgets(blocks[i].text),
        ],
      ],
    );
  }

  List<_RichBlock> _parseBlocks(String source) {
    final blocks = <_RichBlock>[];
    final normal = <String>[];
    final code = <String>[];
    var inCode = false;

    void flushNormal() {
      if (normal.isEmpty) return;
      blocks.add(_RichBlock.text(normal.join('\n')));
      normal.clear();
    }

    void flushCode() {
      blocks.add(_RichBlock.code(code.join('\n').trimRight()));
      code.clear();
    }

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trimRight();
      if (RegExp(r'^\s*```').hasMatch(line)) {
        if (inCode) {
          flushCode();
          inCode = false;
        } else {
          flushNormal();
          inCode = true;
        }
        continue;
      }

      if (inCode) {
        code.add(rawLine);
      } else {
        normal.add(line);
      }
    }

    if (inCode) flushCode();
    flushNormal();

    if (blocks.isEmpty) return [_RichBlock.text('')];
    return blocks;
  }

  Widget _codeBlock(String code) {
    final style = TextStyle(
      color: const Color(0xFFEAF6FF),
      fontFamily: 'monospace',
      fontSize: fontSize - 0.5,
      height: 1.42,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.32)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: selectable
          ? SelectableText(
              code,
              style: style,
              cursorColor: accent,
              selectionControls: materialTextSelectionControls,
            )
          : Text(code, style: style),
    );
  }

  List<Widget> _textWidgets(String source) {
    final widgets = <Widget>[];
    final lines = source.split('\n');

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 7));
        continue;
      }

      // ### heading
      final h = RegExp(r'^\s*(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: _rich(
            h.group(2)!,
            weight: FontWeight.w700,
            size: fontSize + 1.5,
            colorOverride: accent,
          ),
        ));
        continue;
      }

      // - bullet  /  • bullet
      final b = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (b != null) {
        widgets.add(_bulleted('•', b.group(1)!));
        continue;
      }

      // 1. numbered
      final n = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (n != null) {
        widgets.add(_bulleted('${n.group(1)}.', n.group(2)!));
        continue;
      }

      widgets.add(_rich(line));
    }

    return widgets;
  }

  TextSpan _documentSpan(String source) {
    final children = <InlineSpan>[];
    final lines = source.split('\n');

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimRight();
      final isLast = index == lines.length - 1;

      if (line.trim().isEmpty) {
        if (!isLast) children.add(const TextSpan(text: '\n'));
        continue;
      }

      final h = RegExp(r'^\s*(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        children.add(_lineSpan(
          h.group(2)!,
          weight: FontWeight.w700,
          size: fontSize + 1.5,
          colorOverride: accent,
        ));
      } else {
        final b = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
        if (b != null) {
          children.add(TextSpan(
            text: '• ',
            style: TextStyle(
              color: accent.withOpacity(0.85),
              fontSize: fontSize,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ));
          children.add(_lineSpan(b.group(1)!));
        } else {
          final n = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
          if (n != null) {
            children.add(TextSpan(
              text: '${n.group(1)}. ',
              style: TextStyle(
                color: accent.withOpacity(0.85),
                fontSize: fontSize,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ));
            children.add(_lineSpan(n.group(2)!));
          } else {
            children.add(_lineSpan(line));
          }
        }
      }

      if (!isLast) children.add(const TextSpan(text: '\n'));
    }

    return TextSpan(
      style: TextStyle(color: color, fontSize: fontSize, height: 1.5),
      children: children,
    );
  }

  Widget _bulleted(String marker, String rest) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 1),
            child: Text(
              marker,
              style: TextStyle(
                color: accent.withOpacity(0.85),
                fontSize: fontSize,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: _rich(rest)),
        ],
      ),
    );
  }

  /// Inline pass: **bold**, *italic*, `code`.
  Widget _rich(String line,
      {FontWeight? weight, double? size, Color? colorOverride}) {
    return RichText(
      text: _lineSpan(
        line,
        weight: weight,
        size: size,
        colorOverride: colorOverride,
      ),
    );
  }

  TextSpan _lineSpan(String line,
      {FontWeight? weight, double? size, Color? colorOverride}) {
    final spans = <TextSpan>[];
    // One regex, alternation ordered so ** wins before * — otherwise "**x**"
    // parses as an empty italic followed by junk.
    final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    int i = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > i) spans.add(TextSpan(text: line.substring(i, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorOverride ?? accent,
          ),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: ' ${m.group(3)} ',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (size ?? fontSize) - 1.5,
            color: accent,
            backgroundColor: Colors.black.withOpacity(0.35),
          ),
        ));
      }
      i = m.end;
    }
    if (i < line.length) spans.add(TextSpan(text: line.substring(i)));

    return TextSpan(
      style: TextStyle(
        color: colorOverride ?? color,
        fontSize: size ?? fontSize,
        height: 1.5,
        fontWeight: weight,
      ),
      children: spans.isEmpty ? [TextSpan(text: line)] : spans,
    );
  }
}

class _RichBlock {
  final String text;
  final bool isCode;

  const _RichBlock._(this.text, this.isCode);

  const _RichBlock.text(String text) : this._(text, false);
  const _RichBlock.code(String text) : this._(text, true);
}
