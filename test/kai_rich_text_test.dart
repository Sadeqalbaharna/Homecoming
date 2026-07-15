import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_rich_text.dart';

void main() {
  const textColor = Color(0xFFEAF6FF);
  const accentColor = Color(0xFF65D9FF);

  Widget harness(String text) {
    return MaterialApp(
      home: Scaffold(
        body: KaiRichText(
          text: text,
          color: textColor,
          accent: accentColor,
          selectable: true,
        ),
      ),
    );
  }

  Finder codePanelFinder() {
    return find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.borderRadius != null &&
          decoration.border is BoxBorder &&
          decoration.boxShadow != null &&
          decoration.boxShadow!.isNotEmpty;
    });
  }

  testWidgets(
    'selectable KaiRichText keeps ordinary prose as one rich selectable document',
    (tester) async {
      await tester.pumpWidget(harness('Hello **tiny goblin**. Copy me properly.'));

      expect(find.byType(SelectableText), findsOneWidget);
      expect(codePanelFinder(), findsNothing);
    },
  );

  testWidgets(
    'fenced code blocks render as visually separate selectable panels',
    (tester) async {
      await tester.pumpWidget(harness('```dart\nfinal goblin = true;\n```'));

      expect(codePanelFinder(), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == 'final goblin = true;',
        ),
        findsOneWidget,
      );
    },
  );
}
