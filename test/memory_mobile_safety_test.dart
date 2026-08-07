import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile memory retrieval has a bounded indexed working set', () {
    final source =
        File('lib/services/ai/memory_service.dart').readAsStringSync();
    final rules = File('database.rules.json').readAsStringSync();

    expect(
      source,
      isNot(contains(
        "FirebaseService.readData('memory/embeddings/\$personaId')",
      )),
      reason: 'A full embedding-tree read can exhaust the Android heap.',
    );
    expect(source, contains(".orderByChild('timestamp')"));
    expect(source, contains(".uncachedRef('memory/embeddings/\$personaId')"));
    expect(source, contains('.limitToLast(40)'));
    expect(source, contains('.timeout(const Duration(seconds: 12))'));
    expect(rules, contains('".indexOn": ["timestamp"]'));
  });

  test('conversation rules validate nested surface turns', () {
    final rules = jsonDecode(File('database.rules.json').readAsStringSync())
        as Map<String, dynamic>;
    final conversations = ((rules['rules']
        as Map<String, dynamic>)['conversations'] as Map<String, dynamic>);
    final persona = conversations[r'$personaId'] as Map<String, dynamic>;
    final surface = persona[r'$surfaceId'] as Map<String, dynamic>;
    final turn = surface[r'$turnId'] as Map<String, dynamic>;

    expect(surface['.indexOn'], ['timestamp']);
    expect(
      turn['.validate'],
      "newData.hasChildren(['userMessage', 'aiResponse', 'timestamp'])",
      reason:
          'validation at the old persona/turn level rejects surface buckets',
    );
  });

  test('every memory source respects the friend-mode content boundary', () {
    final source = File('lib/services/ai/ai_service.dart').readAsStringSync();

    expect(source, contains('.where(memoryAccessPolicy.allowsContent)'));
    expect(
      source,
      contains('memoryAccessPolicy.allowsContent(spreadBlock)'),
      reason: 'knowledge-graph context must not bypass memory filtering',
    );
    expect(
      source,
      contains('capabilityManifest.allowsTechnicalConversation'),
      reason: 'visible output must use the authoritative capability boundary',
    );
    expect(
      source,
      contains('capabilityManifest.allowsGeneralTools &&'),
      reason:
          'desktop coding-tool assertions must not reject VR co-creator talk',
    );
  });
}
