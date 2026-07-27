// Consolidates multiple validated reflections into conditional self-schemas.
// Local model phrases the schema; deterministic code owns eligibility/evidence.
library;

import 'dart:convert';

import '../ai/local_llm_service.dart';
import 'kai_db.dart';
import 'kai_life_event_service.dart';
import 'kai_self_schema_service.dart';
import 'kai_structured_reflection_service.dart';

class KaiSchemaEvidenceCluster {
  final List<KaiStructuredReflection> reflections;
  final List<KaiReflectionValidation> validations;
  final List<String> supportingEventIds;
  final List<String> contradictingEventIds;
  final List<String> contextKeys;

  const KaiSchemaEvidenceCluster({
    required this.reflections,
    required this.validations,
    required this.supportingEventIds,
    required this.contradictingEventIds,
    required this.contextKeys,
  });

  bool get isEligible =>
      reflections.length >= 2 && supportingEventIds.toSet().length >= 3;

  String get fingerprint {
    final ids = reflections.map((item) => item.id).toList()..sort();
    // Stable and bounded for Firebase path segments even after years of use.
    var hash = 0xcbf29ce484222325;
    for (final unit in ids.join('|').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'cluster_${hash.toRadixString(16).padLeft(16, '0')}';
  }
}

List<KaiSchemaEvidenceCluster> schemaEvidenceClusters({
  required List<KaiStructuredReflection> reflections,
  required List<KaiReflectionValidation> validations,
  required List<KaiLifeEvent> events,
}) {
  final validationByReflection = <String, List<KaiReflectionValidation>>{};
  for (final validation in validations) {
    validationByReflection
        .putIfAbsent(validation.reflectionId, () => [])
        .add(validation);
  }
  final usable = reflections
      .where((item) => validationByReflection[item.id]?.isNotEmpty ?? false)
      .toList();
  final groups = <List<KaiStructuredReflection>>[];
  for (final reflection in usable) {
    final terms = _terms(reflection.provisionalLesson);
    List<KaiStructuredReflection>? target;
    for (final group in groups) {
      if (_terms(group.first.provisionalLesson).intersection(terms).length >=
          2) {
        target = group;
        break;
      }
    }
    (target ?? (groups..add(<KaiStructuredReflection>[])).last).add(reflection);
  }
  final eventById = {for (final event in events) event.id: event};
  return groups
      .map((group) {
        final groupValidations = group
            .expand((item) => validationByReflection[item.id]!)
            .toList(growable: false);
        final supporting = <String>{};
        final contradicting = <String>{};
        for (final reflection in group) {
          final resolutions = validationByReflection[reflection.id]!;
          final supported = resolutions.any(
            (item) => item.resolution != KaiReflectionResolution.rejected,
          );
          (supported ? supporting : contradicting).addAll(reflection.eventIds);
          for (final validation in resolutions) {
            (validation.resolution == KaiReflectionResolution.rejected
                    ? contradicting
                    : supporting)
                .addAll(validation.outcomeEventIds);
          }
        }
        final contexts = <String>{};
        for (final id in {...supporting, ...contradicting}) {
          contexts.addAll(
            (eventById[id]?.tags ?? const [])
                .map(_contextKey)
                .whereType<String>(),
          );
        }
        return KaiSchemaEvidenceCluster(
          reflections: group,
          validations: groupValidations,
          supportingEventIds: supporting.toList()..sort(),
          contradictingEventIds: contradicting.toList()..sort(),
          contextKeys: contexts.where((item) => item.isNotEmpty).toList()
            ..sort(),
        );
      })
      .where((cluster) => cluster.isEligible)
      .toList(growable: false);
}

class KaiSchemaConsolidator {
  KaiSchemaConsolidator._();
  static final KaiSchemaConsolidator instance = KaiSchemaConsolidator._();

  Future<bool> processOne(String personaId) async {
    final results = await Future.wait<Object?>([
      KaiStructuredReflectionService.instance.recent(personaId, limit: 100),
      KaiStructuredReflectionService.instance
          .recentValidations(personaId, limit: 150),
      KaiLifeEventService.instance.recent(personaId, limit: 300),
    ]);
    final clusters = schemaEvidenceClusters(
      reflections: results[0] as List<KaiStructuredReflection>,
      validations: results[1] as List<KaiReflectionValidation>,
      events: results[2] as List<KaiLifeEvent>,
    );
    for (final cluster in clusters) {
      final receipt = KaiDb.instance
          .ref('kai/$personaId/schema_consolidations/${cluster.fingerprint}');
      if ((await receipt.get()).exists) continue;
      final raw = await LocalLLMService().complete(
        system: _prompt,
        user: jsonEncode({
          'lessons': cluster.reflections
              .map((item) => item.provisionalLesson)
              .toList(),
          'validationFindings':
              cluster.validations.map((item) => item.finding).toList(),
          'contexts': cluster.contextKeys,
        }),
        maxTokens: 180,
        jsonMode: true,
      );
      if (raw == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final schema = parseConsolidatedSchema(
        raw,
        revisionId: 'schema_revision_$now',
        evidence: cluster,
        createdAt: now,
      );
      if (schema == null) return false;
      final admission = await KaiSelfSchemaService.instance.append(
        personaId,
        schema,
        availableEventIds:
            (results[2] as List<KaiLifeEvent>).map((item) => item.id).toSet(),
        availableReflectionIds: (results[0] as List<KaiStructuredReflection>)
            .map((item) => item.id)
            .toSet(),
      );
      if (!admission.admitted) return false;
      await receipt.set({'schemaRevisionId': schema.id, 'createdAt': now});
      return true;
    }
    return false;
  }

  static const _prompt = '''
Return JSON only. Phrase one conditional self-schema from the supplied validated
lessons. Do not claim identity, diagnosis, or certainty. Required:
{"schemaKey":"lower_snake_case","domain":"competence|relationship|integrity|curiosity|continuity|care|play","proposition":"I tend to...","conditions":["when..."],"status":"active|contextual"}.
Use active only when multiple supplied contexts genuinely differ.''';
}

KaiSelfSchemaRevision? parseConsolidatedSchema(
  String raw, {
  required String revisionId,
  required KaiSchemaEvidenceCluster evidence,
  required int createdAt,
}) {
  try {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final value = jsonDecode(text);
    if (value is! Map) return null;
    final statusName = value['status']?.toString() ?? '';
    final status = statusName == 'active'
        ? KaiSelfSchemaStatus.active
        : statusName == 'contextual'
            ? KaiSelfSchemaStatus.contextual
            : null;
    if (status == null) return null;
    final contexts = evidence.contextKeys;
    return KaiSelfSchemaRevision(
      id: revisionId,
      schemaKey: value['schemaKey']?.toString() ?? '',
      domain: value['domain']?.toString() ?? '',
      proposition: value['proposition']?.toString() ?? '',
      conditions: value['conditions'] is List
          ? (value['conditions'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      contextKeys: status == KaiSelfSchemaStatus.contextual
          ? contexts.take(1).toList()
          : contexts,
      evidenceFor: evidence.supportingEventIds,
      evidenceAgainst: evidence.contradictingEventIds,
      reflectionIds:
          evidence.reflections.map((item) => item.id).toList(growable: false),
      confidence: schemaConfidence(
        supportingEvents: evidence.supportingEventIds.length,
        contradictingEvents: evidence.contradictingEventIds.length,
        contextCount: contexts.length,
      ),
      status: status,
      createdAt: createdAt,
    );
  } catch (_) {
    return null;
  }
}

Set<String> _terms(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((item) => item.length >= 5 && !_stop.contains(item))
    .toSet();

const _stop = {
  'before',
  'after',
  'should',
  'could',
  'would',
  'learned',
  'lesson',
  'when'
};

String? _contextKey(String raw) {
  final tag = raw.trim().toLowerCase();
  if (tag.startsWith('context:') && tag.length > 8) return tag.substring(8);
  // Compatibility for the small vocabulary used by existing producers.
  const contexts = {
    'coding',
    'planning',
    'relationship',
    'conversation',
    'creative',
    'research',
    'care',
    'play',
  };
  return contexts.contains(tag) ? tag : null;
}
