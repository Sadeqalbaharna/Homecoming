import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/screens/chatgpt_import_screen.dart';

void main() {
  testWidgets('full archive path is visibly local-only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatGPTImportScreen(personaId: 'truekai'),
      ),
    );

    expect(find.text('FULL HISTORY — OLLAMA ONLY'), findsOneWidget);
    expect(find.text('Choose conversations.json'), findsOneWidget);
    expect(find.textContaining('cloud fallback physically disabled'),
        findsOneWidget);
    expect(find.text('SMALL SAVED-MEMORY NOTE — CLOUD IMPORT'), findsOneWidget);
  });
}
