import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/chatgpt_export.dart';
import 'package:homecoming_app/tools/chatgpt_history_import.dart';

void main() {
  ExportConversation conversation(
    String title,
    String user,
    String assistant,
  ) =>
      ExportConversation(title, [
        ExportTurn('user', user, 1),
        ExportTurn('assistant', assistant, 2),
      ]);

  test('estimate excludes task chatter before local inference', () {
    final estimate = estimateArchiveImport([
      conversation(
        'personal',
        'I have been thinking about my family and I want Kai to remember why this matters to me.',
        'I understand why that history matters.',
      ),
      conversation(
        'task',
        'Fix this API function and debug the null error in this code.',
        'Here is the refactored function.',
      ),
    ]);

    expect(estimate.totalConversations, 2);
    expect(estimate.personalConversations, 1);
    expect(estimate.approximateLocalInputTokens, greaterThan(0));
  });

  test('conversation checkpoint identity is stable and content-sensitive', () {
    final original = conversation(
      'Kai origins',
      'I want to preserve our history together because it matters to me.',
      'Then we should preserve it carefully.',
    );
    final same = conversation(
      'Kai origins',
      'I want to preserve our history together because it matters to me.',
      'Then we should preserve it carefully.',
    );
    final changed = conversation(
      'Kai origins',
      'I want to preserve our whole history together because it matters to me.',
      'Then we should preserve it carefully.',
    );

    expect(archiveConversationId(original), archiveConversationId(same));
    expect(
        archiveConversationId(original), isNot(archiveConversationId(changed)));
    expect(archiveConversationId(original).length, lessThan(80));
  });

  test('archive path hard-disables cloud fallback', () {
    final source =
        File('lib/tools/chatgpt_history_import.dart').readAsStringSync();
    expect(source, contains('allowCloudFallback: false'));
    expect(source, contains("'paidTokens': 0"));
  });

  test('evidence capsule is bounded and old assistant text has no authority',
      () {
    final source = conversation(
      'A long shared history',
      'I want this detail remembered because it mattered to me. ' * 30,
      'I am an old assistant response and must not become a factual claim. ' *
          30,
    );
    final capsule = archiveEvidenceCapsule(source, excerptChars: 120);

    expect((capsule['userExcerpt'] as String).length, lessThanOrEqualTo(121));
    expect(
      (capsule['legacyAssistantExcerpt'] as String).length,
      lessThanOrEqualTo(121),
    );
    expect(capsule['assistantAuthority'], 'historical_voice_only');
    expect(capsule['livePromptEligible'], isFalse);
  });
}
