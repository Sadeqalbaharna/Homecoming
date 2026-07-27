import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';
import 'package:homecoming_app/services/core/kai_schema_consolidator.dart';
import 'package:homecoming_app/services/core/kai_self_schema_service.dart';
import 'package:homecoming_app/services/core/kai_structured_reflection_service.dart';

void main() {
  KaiStructuredReflection reflection(String id, List<String> events) =>
      KaiStructuredReflection(
        id: id,
        eventIds: events,
        expectation: 'I expected the explanation to be accurate.',
        observedOutcome: 'Inspection changed the result.',
        intention: 'I wanted to answer accurately.',
        hypotheses: const [],
        provisionalLesson:
            'Inspect disconfirming evidence before expressing confidence.',
        nextExperiment: 'Inspect a competing trace before the next answer.',
        createdAt: 100,
      );

  KaiLifeEvent event(String id, String context) => KaiLifeEvent(
        id: id,
        kind: KaiLifeEventKind.actionOutcome,
        source: KaiLifeEventSource.toolReceipt,
        occurredAt: 200,
        recordedAt: 200,
        outcome: 'A later observable result was recorded.',
        tags: [context],
        evidenceIds: ['tool:test:$id'],
        confidence: 0.8,
      );

  test('two validated reflections with three events become eligible', () {
    final reflections = [
      reflection('r1', ['e1']),
      reflection('r2', ['e2']),
    ];
    final validations = const [
      KaiReflectionValidation(
        id: 'v1',
        reflectionId: 'r1',
        resolution: KaiReflectionResolution.supported,
        outcomeEventIds: ['e3'],
        finding: 'Inspection improved the resulting explanation.',
        validatedAt: 300,
      ),
      KaiReflectionValidation(
        id: 'v2',
        reflectionId: 'r2',
        resolution: KaiReflectionResolution.revised,
        outcomeEventIds: ['e4'],
        finding: 'The effect held, but only when traces were available.',
        validatedAt: 301,
      ),
    ];
    final clusters = schemaEvidenceClusters(
      reflections: reflections,
      validations: validations,
      events: [
        event('e1', 'coding'),
        event('e2', 'planning'),
        event('e3', 'coding'),
        event('e4', 'planning'),
      ],
    );
    expect(clusters, hasLength(1));
    expect(clusters.single.isEligible, isTrue);
    expect(clusters.single.supportingEventIds, hasLength(4));
    expect(clusters.single.contextKeys, containsAll(['coding', 'planning']));
  });

  test('rejected validation becomes counterevidence', () {
    final clusters = schemaEvidenceClusters(
      reflections: [
        reflection('r1', ['e1', 'e2']),
        reflection('r2', ['e3', 'e4']),
      ],
      validations: const [
        KaiReflectionValidation(
          id: 'v1',
          reflectionId: 'r1',
          resolution: KaiReflectionResolution.supported,
          outcomeEventIds: ['e5'],
          finding: 'The experiment supported the lesson.',
          validatedAt: 300,
        ),
        KaiReflectionValidation(
          id: 'v2',
          reflectionId: 'r2',
          resolution: KaiReflectionResolution.rejected,
          outcomeEventIds: ['e6'],
          finding: 'The later result contradicted the lesson.',
          validatedAt: 301,
        ),
      ],
      events: [
        for (final id in ['e1', 'e2', 'e3', 'e4', 'e5', 'e6'])
          event(id, id == 'e1' ? 'coding' : 'planning'),
      ],
    );
    expect(
        clusters.single.contradictingEventIds, containsAll(['e3', 'e4', 'e6']));
  });

  test('local phrasing cannot alter deterministic evidence', () {
    final cluster = KaiSchemaEvidenceCluster(
      reflections: [
        reflection('r1', ['e1']),
        reflection('r2', ['e2']),
      ],
      validations: const [],
      supportingEventIds: const ['e1', 'e2', 'e3'],
      contradictingEventIds: const ['e4'],
      contextKeys: const ['coding', 'planning'],
    );
    final schema = parseConsolidatedSchema(
      '{"schemaKey":"inspect_before_confidence","domain":"competence","proposition":"I tend to become reliably confident after inspection.","conditions":["when evidence is inspectable"],"status":"active"}',
      revisionId: 'schema_revision_1',
      evidence: cluster,
      createdAt: 400,
    );
    expect(schema, isNotNull);
    expect(schema!.evidenceFor, ['e1', 'e2', 'e3']);
    expect(schema.evidenceAgainst, ['e4']);
    expect(schema.status, KaiSelfSchemaStatus.active);
  });
}
