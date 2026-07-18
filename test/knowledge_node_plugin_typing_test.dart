// The node parser has to survive the shape the phone actually hands it.
//
// ── The bug ─────────────────────────────────────────────────────────────────
//
// KaiDb is a facade: REST on desktop, the firebase_database plugin on mobile.
// dart:convert (REST) yields `Map<String, dynamic>`. The plugin yields
// `Map<Object?, Object?>`.
//
// KnowledgeNode.fromJson did `json['metadata'] as Map<String, dynamic>?`, and
// that cast THROWS on a `Map<Object?, Object?>` — it does not fall through to
// the `?? {}`. Every node has a metadata field, so on mobile every node threw,
// _loadGraph parsed 0 of 168, and the graph guard refused to load rather than
// let the next save wipe it. Verbatim from a device:
//
//   ❌ [Brain] _loadGraph REFUSED: parsed 0 of 168 stored nodes — schema mismatch
//
// So Kai was amnesiac on his own phone — hasMemory:false every turn — while the
// desktop read the identical graph without a hitch. It looked like a schema
// change. It was a Map type the desktop never sees.
//
// This test reproduces the plugin's typing (Map<Object?,Object?>, nested) and
// asserts fromJson survives it. If someone adds another `as Map<String,dynamic>`
// to the model, this goes red on the desk instead of going silent on the phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/models/knowledge_node.dart';

/// A node exactly as the firebase_database plugin deserializes it: every map,
/// at every depth, is Map<Object?, Object?>. This is NOT how dart:convert types
/// it, and that difference is the entire bug.
Map<Object?, Object?> pluginNode() => <Object?, Object?>{
      'id': 'sadeq',
      'label': 'Sadeq',
      'type': 'person',
      'timestamp': 1784300000000,
      'tags': <Object?>['maker', 'father'],
      'importance': 0.9,
      // The landmine: a non-null nested map, plugin-typed.
      'metadata': <Object?, Object?>{
        'source': 'shard_a',
        'note': 'builds Kai with his daughter nearby',
      },
      'emotionalIntensity': 0.4,
      'accessCount': 12,
      'retention': 1.0,
      'activationLevel': 0.0,
    };

void main() {
  test('a node typed the way the phone types it still parses', () {
    final node = KnowledgeNode.fromJson(
      // fromJson's signature is Map<String, dynamic>; the plugin's map satisfies
      // it structurally (Map is Map), which is why this compiled and shipped and
      // then threw at runtime on the nested cast rather than at the boundary.
      Map<String, dynamic>.from(pluginNode()),
    );

    expect(node.id, 'sadeq');
    expect(node.label, 'Sadeq');
    expect(node.type, NodeType.person);
    // The field that used to throw the whole node away.
    expect(node.metadata['source'], 'shard_a');
    expect(node.metadata['note'], contains('daughter'));
  });

  test('metadata absent is an empty map, not a crash', () {
    final node = KnowledgeNode.fromJson(<String, dynamic>{
      'id': 'x',
      'label': 'x',
      'type': 'fact',
      'timestamp': 1784300000000,
    });
    expect(node.metadata, isEmpty);
  });

  test('a whole graph of plugin-typed nodes loses none of them', () {
    // The real failure was collective: not "some rows are odd" but "every row
    // dies the same way, so the count is zero and the guard trips." Prove the
    // batch survives, because 0-of-N was the actual symptom.
    final parsed = [
      for (var i = 0; i < 10; i++)
        KnowledgeNode.fromJson(Map<String, dynamic>.from(pluginNode()..['id'] = 'n$i')),
    ];
    expect(parsed, hasLength(10));
    expect(parsed.every((n) => n.metadata.isNotEmpty), isTrue);
  });
}
