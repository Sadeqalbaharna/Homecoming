// Golden set for knowledge extraction.
//
// Memory has golden tests. The graph had none — which meant "is what he knows
// any good?" was answerable only by vibes, and vibes drift. That is the exact
// reason kai_project_service freezes its intent in code.
//
// What these pin down:
//
//   1. The stranger test. A node that would be true of a random other person is
//      not knowledge about Sadeq. "importance of clarity" is a horoscope.
//   2. Entities as nodes, claims as edges. A proposition crammed into a node
//      label ("fear of sounding generic") spends the meaning on the noun and
//      leaves the edge with nothing to say but "relates to".
//   3. The EdgeType vocabulary actually resolves. Twenty relationships existed
//      with colours assigned and were never once written.
//
// Everything here is pure — no OpenAI, no Firebase, no secure storage.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/models/knowledge_node.dart';
import 'package:homecoming_app/services/core/brain_extraction_service.dart';

/// Labels that must never survive extraction. Every one of these was really in
/// the graph, and every one is true of every human alive.
const genericLabels = <String>[
  'importance of clarity',
  'importance of context',
  'importance of connection',
  'importance of memory',
  'importance of structure',
  'importance of predictability',
  'embracing vulnerability',
  'embracing uncertainty',
  'embracing complexity',
  'fear of failure',
  'desire for progress',
  'goal of being useful',
  'goal of efficiency',
  'frustration with complexity',
  'frustration with limitations',
  'value of connection',
];

/// Labels that must survive. A stranger doesn't know his son's name.
const specificLabels = <String>[
  'Mikey',
  'the Tavern',
  'Bahrain',
  'Walker Scobell',
  'Flutter',
  'sounding like every other AI assistant',
];

/// The five syntactic frames the old extractor collapsed into. 22 nodes from
/// five templates with slots — Mad-Libs wearing a knowledge graph.
final _nominalisationFrames = RegExp(
  r'^(importance of|value of|fear of|goal of|desire for|frustration with|embracing)\b',
  caseSensitive: false,
);

void main() {
  group('the stranger test — would this be FALSE for someone else?', () {
    test('every known-generic label matches a nominalisation frame', () {
      // If this fails, the frame list is out of date, not the labels.
      for (final l in genericLabels) {
        expect(_nominalisationFrames.hasMatch(l), isTrue,
            reason: '"$l" should be recognisable as a template abstraction');
      }
    });

    test('no specific label looks like a nominalisation', () {
      for (final l in specificLabels) {
        expect(_nominalisationFrames.hasMatch(l), isFalse,
            reason: '"$l" is a real thing and must never be pruned as generic');
      }
    });
  });

  group('EdgeType vocabulary resolves', () {
    test('exact enum names round-trip', () {
      expect(parseEdgeType('caresAbout'), EdgeType.caresAbout);
      expect(parseEdgeType('holdsValue'), EdgeType.holdsValue);
      expect(parseEdgeType('pursues'), EdgeType.pursues);
      expect(parseEdgeType('contradicts'), EdgeType.contradicts);
    });

    test('tolerates the spacing and casing a model actually emits', () {
      // Dropping a good relationship over a space would be an own goal.
      expect(parseEdgeType('cares about'), EdgeType.caresAbout);
      expect(parseEdgeType('cares_about'), EdgeType.caresAbout);
      expect(parseEdgeType('CARES ABOUT'), EdgeType.caresAbout);
      expect(parseEdgeType('  caresAbout '), EdgeType.caresAbout);
    });

    test('maps the natural phrasing a model reaches for', () {
      expect(parseEdgeType('cares for'), EdgeType.caresAbout);
      expect(parseEdgeType('loves'), EdgeType.caresAbout);
      expect(parseEdgeType('values'), EdgeType.holdsValue);
      expect(parseEdgeType('is building'), EdgeType.pursues);
      expect(parseEdgeType('working on'), EdgeType.pursues);
      expect(parseEdgeType('fears'), EdgeType.dislikes);
      expect(parseEdgeType('avoids'), EdgeType.dislikes);
      expect(parseEdgeType('realised'), EdgeType.learned);
    });

    test('falls back to related rather than throwing', () {
      // An unknown verb must degrade, not crash the whole extraction.
      expect(parseEdgeType('splorked'), EdgeType.related);
      expect(parseEdgeType(''), EdgeType.related);
      expect(parseEdgeType('!!!'), EdgeType.related);
    });

    test('"Sadeq cares for Kai" survives the whole way to an EdgeType', () {
      // The sentence this entire exercise exists for.
      final t = parseEdgeType('cares for');
      expect(t, EdgeType.caresAbout);
      final edge = KnowledgeEdge(
        fromId: 'sadeq',
        toId: 'kai',
        type: t,
        strength: 0.9,
        timestamp: DateTime.now(),
        label: 'cares for',
      );
      expect(edge.type, EdgeType.caresAbout);
      expect(edge.label, 'cares for');
      // The colour switch has existed since the model was written and has never
      // fired, because every edge was stamped `related` on the way in.
      expect(edge.color, isNot(equals(KnowledgeEdge(
        fromId: 'a', toId: 'b', type: EdgeType.related,
        strength: 0.5, timestamp: DateTime.now(),
      ).color)));
    });
  });

  group('the graph has a centre, and claims can reach it', () {
    // `NodeType.you` is documented in the model as "The user (central node -
    // most important)" and was never once created. No Sadeq node meant no
    // subject for any claim — which is WHY the extractor nominalised everything
    // into "fear of sounding generic" instead of an edge from Sadeq.
    test('NodeType.you exists to be used', () {
      expect(NodeType.values.contains(NodeType.you), isTrue);
    });

    test('the founding sentence is representable end to end', () {
      final sadeq = KnowledgeNode(
        id: 's', label: 'Sadeq', type: NodeType.you,
        timestamp: DateTime.now(), importance: 1.0,
        metadata: const {'anchor': true},
      );
      final kai = KnowledgeNode(
        id: 'k', label: 'Kai', type: NodeType.person,
        timestamp: DateTime.now(), importance: 1.0,
        metadata: const {'anchor': true},
      );
      final e = KnowledgeEdge(
        fromId: sadeq.id, toId: kai.id,
        type: parseEdgeType('cares for'),
        strength: 1.0, timestamp: DateTime.now(), label: 'cares for',
      );

      expect(sadeq.type, NodeType.you);
      expect(e.type, EdgeType.caresAbout);
      expect(e.fromId, sadeq.id);
      expect(e.toId, kai.id);
      // Anchors are flagged so decay and pruning can refuse to touch them.
      expect(sadeq.metadata['anchor'], isTrue);
      expect(kai.metadata['anchor'], isTrue);
    });
  });

  group('multiple relationships between the same two nodes', () {
    // Edge identity used to be the PAIR alone, so two entities could only ever
    // have one relationship — whichever arrived first won forever. The pairs
    // that suffered most were the richest ones: the people he actually talks
    // about.
    test('knows and caresAbout are two different facts, not one', () {
      final knows = KnowledgeEdge(
        fromId: 'sadeq', toId: 'mikey', type: EdgeType.knows,
        strength: 0.8, timestamp: DateTime.now(), label: 'knows',
      );
      final cares = KnowledgeEdge(
        fromId: 'sadeq', toId: 'mikey', type: EdgeType.caresAbout,
        strength: 0.9, timestamp: DateTime.now(), label: 'cares about',
      );

      // Same pair, different relationship → must not collide.
      expect(knows.fromId, cares.fromId);
      expect(knows.toId, cares.toId);
      expect(knows.type, isNot(cares.type));

      // The identity the merge now uses.
      bool sameEdge(KnowledgeEdge a, KnowledgeEdge b) =>
          a.fromId == b.fromId && a.toId == b.toId && a.type == b.type;
      expect(sameEdge(knows, cares), isFalse,
          reason: 'multiple links between the same two nodes must coexist');

      // The old identity — kept here to pin the bug that was fixed.
      bool oldIdentity(KnowledgeEdge a, KnowledgeEdge b) =>
          a.fromId == b.fromId && a.toId == b.toId;
      expect(oldIdentity(knows, cares), isTrue,
          reason: 'this is what used to flatten them into one edge');
    });

    test('direction is part of the fact', () {
      final aToB = KnowledgeEdge(
        fromId: 'sadeq', toId: 'kai', type: EdgeType.caresAbout,
        strength: 1.0, timestamp: DateTime.now(),
      );
      final bToA = KnowledgeEdge(
        fromId: 'kai', toId: 'sadeq', type: EdgeType.caresAbout,
        strength: 1.0, timestamp: DateTime.now(),
      );
      expect(aToB.fromId, isNot(bToA.fromId));
    });
  });

  group('provenance — a claim you cannot trace is a rumour', () {
    test('an edge carries the memory shards it came from', () {
      final e = KnowledgeEdge(
        fromId: 'sadeq', toId: 'tavern', type: EdgeType.pursues,
        strength: 0.9, timestamp: DateTime.now(), label: 'is building',
        sources: const ['-Nabc123', '-Nabc456'],
      );
      expect(e.sources, hasLength(2));
      // Round-trips, or provenance dies at the first save.
      final back = KnowledgeEdge.fromJson(e.toJson());
      expect(back.sources, e.sources);
    });

    test('legacy edges without sources still load', () {
      // Every edge written before today has no provenance. "We don't know where
      // this came from" is the honest reading, and it must not crash.
      final legacy = KnowledgeEdge.fromJson({
        'fromId': 'a', 'toId': 'b', 'type': 'related', 'strength': 0.5,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      expect(legacy.sources, isEmpty);
      expect(legacy.isActive, isTrue);
    });
  });

  group('supersession — a mind that changed, not one always right', () {
    test('a superseded claim is retired, not deleted', () {
      final claim = KnowledgeEdge(
        fromId: 'sadeq', toId: 'bahrain', type: EdgeType.does,
        strength: 0.8, timestamp: DateTime.now(), label: 'lives in',
      );
      expect(claim.isActive, isTrue);

      final retired = claim.copyWith(supersededAt: DateTime.now());
      expect(retired.isActive, isFalse);
      // Still there. Still says what it said. That's the point.
      expect(retired.label, 'lives in');
      expect(retired.fromId, claim.fromId);
      expect(retired.toId, claim.toId);
    });

    test('supersededAt round-trips through JSON', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1750000000000);
      final e = KnowledgeEdge(
        fromId: 'a', toId: 'b', type: EdgeType.believes,
        strength: 0.5, timestamp: DateTime.now(), supersededAt: t,
      );
      final back = KnowledgeEdge.fromJson(e.toJson());
      expect(back.isActive, isFalse);
      expect(back.supersededAt!.millisecondsSinceEpoch, t.millisecondsSinceEpoch);
    });

    test('an active edge omits supersededAt entirely', () {
      final e = KnowledgeEdge(
        fromId: 'a', toId: 'b', type: EdgeType.knows,
        strength: 0.5, timestamp: DateTime.now(),
      );
      expect(e.toJson().containsKey('supersededAt'), isFalse);
    });
  });

  group('the neuromorphic fields can finally survive a save', () {
    // The previous neuromorphic push wired real behaviour into fields that
    // _saveGraph silently dropped on every write. accessCount was incremented
    // faithfully by reinforceNodes and reset to 0 on every load, forever. The
    // fields weren't decoration because nobody used them — they were decoration
    // because they could not persist.
    test('a node round-trips every neuromorphic field', () {
      final n = KnowledgeNode(
        id: 'n1', label: 'the Tavern', type: NodeType.topic,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1750000000000),
        importance: 0.8,
        emotionalIntensity: 0.7,
        accessCount: 9,
        retention: 0.85,
        lastAccessed: DateTime.fromMillisecondsSinceEpoch(1750000600000),
        activationLevel: 1.0,
        metadata: const {'mentions': 4, 'sources': ['-Nabc']},
      );

      final back = KnowledgeNode.fromJson(n.toJson());

      expect(back.accessCount, 9, reason: 'recall count must survive — it was 0 forever');
      expect(back.emotionalIntensity, 0.7);
      expect(back.retention, 0.85);
      expect(back.activationLevel, 1.0);
      expect(back.lastAccessed!.millisecondsSinceEpoch, 1750000600000,
          reason: 'lastAccessed drives the refractory period');
      expect(back.metadata['sources'], isNotNull, reason: 'provenance must survive');
    });

    test('a fresh node starts cold, not activated', () {
      final n = KnowledgeNode(
        id: 'x', label: 'y', type: NodeType.concept, timestamp: DateTime.now(),
      );
      expect(n.activationLevel, 0.0);
      expect(n.accessCount, 0);
      expect(n.retention, 1.0);
      expect(n.lastAccessed, isNull);
    });
  });

  group('claims belong on edges, not inside nouns', () {
    test('a proposition node is representable as entity + typed edge', () {
      // "fear of sounding generic" is a subject, a predicate and an object
      // mashed into a noun phrase. Split properly it becomes:
      final entity = KnowledgeNode(
        id: 'n1',
        label: 'sounding like every other AI assistant',
        type: NodeType.concept,
        timestamp: DateTime.now(),
        importance: 0.8,
      );
      final claim = KnowledgeEdge(
        fromId: 'sadeq',
        toId: entity.id,
        type: EdgeType.dislikes,
        strength: 0.9,
        timestamp: DateTime.now(),
        label: 'is afraid of',
      );

      // The entity carries no verb…
      expect(_nominalisationFrames.hasMatch(entity.label), isFalse);
      // …and the claim carries the meaning.
      expect(claim.type, EdgeType.dislikes);
      expect(claim.type, isNot(EdgeType.related));
    });
  });
}
