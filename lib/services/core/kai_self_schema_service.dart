// Conditional self-knowledge earned from multiple events and reflections.
library;

import 'kai_db.dart';

enum KaiSelfSchemaStatus { candidate, active, contextual, retired }

class KaiSelfSchemaRevision {
  final String id;
  final String schemaKey;
  final String domain;
  final String proposition;
  final List<String> conditions;
  final List<String> contextKeys;
  final List<String> evidenceFor;
  final List<String> evidenceAgainst;
  final List<String> reflectionIds;
  final double confidence;
  final KaiSelfSchemaStatus status;
  final int createdAt;
  final String supersedesRevisionId;

  const KaiSelfSchemaRevision({
    required this.id,
    required this.schemaKey,
    required this.domain,
    required this.proposition,
    required this.conditions,
    required this.contextKeys,
    required this.evidenceFor,
    this.evidenceAgainst = const [],
    required this.reflectionIds,
    required this.confidence,
    required this.status,
    required this.createdAt,
    this.supersedesRevisionId = '',
  });

  Map<String, dynamic> toMap() => {
        'schemaKey': schemaKey,
        'domain': domain,
        'proposition': proposition,
        'conditions': conditions,
        'contextKeys': contextKeys,
        'evidenceFor': evidenceFor,
        'evidenceAgainst': evidenceAgainst,
        'reflectionIds': reflectionIds,
        'confidence': confidence,
        'status': status.name,
        'createdAt': createdAt,
        'supersedesRevisionId': supersedesRevisionId,
        'schemaVersion': 1,
      };

  static KaiSelfSchemaRevision? fromMap(String id, Object? value) {
    if (value is! Map) return null;
    final statuses = KaiSelfSchemaStatus.values
        .where((candidate) => candidate.name == value['status']);
    if (statuses.isEmpty) return null;
    return KaiSelfSchemaRevision(
      id: id,
      schemaKey: (value['schemaKey'] as String?)?.trim() ?? '',
      domain: (value['domain'] as String?)?.trim() ?? '',
      proposition: (value['proposition'] as String?)?.trim() ?? '',
      conditions: _strings(value['conditions']),
      contextKeys: _strings(value['contextKeys']),
      evidenceFor: _strings(value['evidenceFor']),
      evidenceAgainst: _strings(value['evidenceAgainst']),
      reflectionIds: _strings(value['reflectionIds']),
      confidence:
          ((value['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      status: statuses.first,
      createdAt: (value['createdAt'] as num?)?.toInt() ?? 0,
      supersedesRevisionId:
          (value['supersedesRevisionId'] as String?)?.trim() ?? '',
    );
  }
}

class KaiSelfSchemaAdmission {
  final bool admitted;
  final String reason;
  const KaiSelfSchemaAdmission._(this.admitted, this.reason);
  const KaiSelfSchemaAdmission.admitted() : this._(true, 'admitted');
  const KaiSelfSchemaAdmission.refused(String reason) : this._(false, reason);
}

KaiSelfSchemaAdmission admitSelfSchema(
  KaiSelfSchemaRevision schema, {
  required Set<String> availableEventIds,
  required Set<String> availableReflectionIds,
}) {
  final safe = RegExp(r'^[A-Za-z0-9_-]{3,120}$');
  if (!safe.hasMatch(schema.id) || !safe.hasMatch(schema.schemaKey)) {
    return const KaiSelfSchemaAdmission.refused('invalid schema identifier');
  }
  if (schema.createdAt <= 0 ||
      schema.domain.trim().length < 3 ||
      schema.proposition.trim().length < 12 ||
      schema.conditions.isEmpty) {
    return const KaiSelfSchemaAdmission.refused('schema content is too thin');
  }
  if (schema.evidenceFor.toSet().length < 3 ||
      schema.reflectionIds.toSet().length < 2) {
    return const KaiSelfSchemaAdmission.refused(
      'durable schema requires three events and two reflections',
    );
  }
  if (schema.evidenceFor.any((id) => !availableEventIds.contains(id)) ||
      schema.evidenceAgainst.any((id) => !availableEventIds.contains(id))) {
    return const KaiSelfSchemaAdmission.refused('schema cites missing event');
  }
  if (schema.reflectionIds.any((id) => !availableReflectionIds.contains(id))) {
    return const KaiSelfSchemaAdmission.refused(
      'schema cites missing reflection',
    );
  }
  if (schema.confidence < 0.35 || schema.confidence > 0.85) {
    return const KaiSelfSchemaAdmission.refused(
      'schema confidence exceeds developmental bounds',
    );
  }
  if (schema.status == KaiSelfSchemaStatus.active &&
      schema.contextKeys.toSet().length < 2) {
    return const KaiSelfSchemaAdmission.refused(
      'general schema requires evidence across contexts',
    );
  }
  if (schema.status == KaiSelfSchemaStatus.contextual &&
      schema.contextKeys.length != 1) {
    return const KaiSelfSchemaAdmission.refused(
      'contextual schema must name exactly one context',
    );
  }
  return const KaiSelfSchemaAdmission.admitted();
}

double schemaConfidence({
  required int supportingEvents,
  required int contradictingEvents,
  required int contextCount,
}) {
  final total = supportingEvents + contradictingEvents;
  if (supportingEvents < 3 || total == 0) return 0;
  final evidenceRatio = supportingEvents / total;
  final diversity = (0.65 + contextCount.clamp(1, 3) * 0.1).clamp(0, 1);
  return (evidenceRatio * diversity).clamp(0.35, 0.85);
}

class KaiSelfSchemaService {
  KaiSelfSchemaService._();
  static final KaiSelfSchemaService instance = KaiSelfSchemaService._();

  String _path(String personaId) => 'kai/$personaId/self_schema_revisions';

  Future<KaiSelfSchemaAdmission> append(
    String personaId,
    KaiSelfSchemaRevision schema, {
    required Set<String> availableEventIds,
    required Set<String> availableReflectionIds,
  }) async {
    final admission = admitSelfSchema(
      schema,
      availableEventIds: availableEventIds,
      availableReflectionIds: availableReflectionIds,
    );
    if (!admission.admitted) return admission;
    try {
      final ref = KaiDb.instance.ref('${_path(personaId)}/${schema.id}');
      if ((await ref.get()).exists) {
        return const KaiSelfSchemaAdmission.refused(
          'schema revision already exists',
        );
      }
      await ref.set(schema.toMap());
      return const KaiSelfSchemaAdmission.admitted();
    } catch (_) {
      return const KaiSelfSchemaAdmission.refused('persistence failed');
    }
  }

  /// Latest revision per key. Retired schemas stay in history but leave self.
  static List<KaiSelfSchemaRevision> activeView(
    List<KaiSelfSchemaRevision> revisions,
  ) {
    final latest = <String, KaiSelfSchemaRevision>{};
    for (final revision in revisions) {
      final existing = latest[revision.schemaKey];
      if (existing == null || revision.createdAt > existing.createdAt) {
        latest[revision.schemaKey] = revision;
      }
    }
    final active = latest.values
        .where((item) =>
            item.status == KaiSelfSchemaStatus.active ||
            item.status == KaiSelfSchemaStatus.contextual)
        .toList();
    active.sort((a, b) => b.confidence.compareTo(a.confidence));
    return active;
  }
}

List<String> _strings(Object? value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const [];
