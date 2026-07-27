import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_self_schema_service.dart';

void main() {
  KaiSelfSchemaRevision schema({
    String id = 'schema_revision_1',
    String key = 'verification_confidence',
    List<String> evidenceFor = const ['e1', 'e2', 'e3'],
    List<String> evidenceAgainst = const ['e4'],
    List<String> reflections = const ['r1', 'r2'],
    List<String> contexts = const ['coding', 'planning'],
    KaiSelfSchemaStatus status = KaiSelfSchemaStatus.active,
    int createdAt = 100,
  }) =>
      KaiSelfSchemaRevision(
        id: id,
        schemaKey: key,
        domain: 'competence',
        proposition: 'My confidence becomes reliable after inspection.',
        conditions: const ['when evidence can be directly inspected'],
        contextKeys: contexts,
        evidenceFor: evidenceFor,
        evidenceAgainst: evidenceAgainst,
        reflectionIds: reflections,
        confidence: schemaConfidence(
          supportingEvents: evidenceFor.length,
          contradictingEvents: evidenceAgainst.length,
          contextCount: contexts.length,
        ),
        status: status,
        createdAt: createdAt,
      );

  test('repeated reflected evidence forms a conditional schema', () {
    final admission = admitSelfSchema(
      schema(),
      availableEventIds: {'e1', 'e2', 'e3', 'e4'},
      availableReflectionIds: {'r1', 'r2'},
    );
    expect(admission.admitted, isTrue);
  });

  test('one eloquent reflection cannot become character', () {
    final admission = admitSelfSchema(
      schema(reflections: const ['r1']),
      availableEventIds: {'e1', 'e2', 'e3', 'e4'},
      availableReflectionIds: {'r1'},
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('three events and two reflections'));
  });

  test('single-context evidence remains contextual instead of universal', () {
    final rejected = admitSelfSchema(
      schema(contexts: const ['coding']),
      availableEventIds: {'e1', 'e2', 'e3', 'e4'},
      availableReflectionIds: {'r1', 'r2'},
    );
    expect(rejected.admitted, isFalse);

    final admitted = admitSelfSchema(
      schema(
        contexts: const ['coding'],
        status: KaiSelfSchemaStatus.contextual,
      ),
      availableEventIds: {'e1', 'e2', 'e3', 'e4'},
      availableReflectionIds: {'r1', 'r2'},
    );
    expect(admitted.admitted, isTrue);
  });

  test('counterevidence lowers confidence rather than being deleted', () {
    final clean = schemaConfidence(
      supportingEvents: 5,
      contradictingEvents: 0,
      contextCount: 2,
    );
    final conflicted = schemaConfidence(
      supportingEvents: 5,
      contradictingEvents: 3,
      contextCount: 2,
    );
    expect(conflicted, lessThan(clean));
  });

  test('retirement changes active view without erasing old revision', () {
    final original = schema(createdAt: 100);
    final retired = schema(
      id: 'schema_revision_2',
      status: KaiSelfSchemaStatus.retired,
      createdAt: 200,
    );
    final active = KaiSelfSchemaService.activeView([original, retired]);
    expect(active, isEmpty);
    expect([original, retired], hasLength(2));
  });
}
