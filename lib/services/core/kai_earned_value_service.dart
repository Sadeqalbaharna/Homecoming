// Values are inferred from repeated costly choices, never declared from prose.
library;

import 'kai_db.dart';
import 'kai_life_event_service.dart';

enum KaiEarnedValueStatus { active, contextual, retired }

class KaiEarnedValueRevision {
  final String id;
  final String valueKey;
  final String statement;
  final List<String> contextKeys;
  final List<String> evidenceFor;
  final List<String> evidenceAgainst;
  final int totalChoiceCost;
  final double confidence;
  final KaiEarnedValueStatus status;
  final int createdAt;
  final String supersedesRevisionId;

  const KaiEarnedValueRevision({
    required this.id,
    required this.valueKey,
    required this.statement,
    required this.contextKeys,
    required this.evidenceFor,
    this.evidenceAgainst = const [],
    required this.totalChoiceCost,
    required this.confidence,
    required this.status,
    required this.createdAt,
    this.supersedesRevisionId = '',
  });

  Map<String, dynamic> toMap() => {
        'valueKey': valueKey,
        'statement': statement,
        'contextKeys': contextKeys,
        'evidenceFor': evidenceFor,
        'evidenceAgainst': evidenceAgainst,
        'totalChoiceCost': totalChoiceCost,
        'confidence': confidence,
        'status': status.name,
        'createdAt': createdAt,
        'supersedesRevisionId': supersedesRevisionId,
        'schemaVersion': 1,
      };

  static KaiEarnedValueRevision? fromMap(String id, Object? raw) {
    if (raw is! Map) return null;
    final statuses = KaiEarnedValueStatus.values
        .where((candidate) => candidate.name == raw['status']);
    if (statuses.isEmpty) return null;
    return KaiEarnedValueRevision(
      id: id,
      valueKey: raw['valueKey']?.toString().trim() ?? '',
      statement: raw['statement']?.toString().trim() ?? '',
      contextKeys: _strings(raw['contextKeys']),
      evidenceFor: _strings(raw['evidenceFor']),
      evidenceAgainst: _strings(raw['evidenceAgainst']),
      totalChoiceCost: (raw['totalChoiceCost'] as num?)?.toInt() ?? 0,
      confidence: ((raw['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      status: statuses.first,
      createdAt: (raw['createdAt'] as num?)?.toInt() ?? 0,
      supersedesRevisionId:
          raw['supersedesRevisionId']?.toString().trim() ?? '',
    );
  }
}

class KaiEarnedValueAdmission {
  final bool admitted;
  final String reason;
  const KaiEarnedValueAdmission._(this.admitted, this.reason);
  const KaiEarnedValueAdmission.admitted() : this._(true, 'admitted');
  const KaiEarnedValueAdmission.refused(String reason) : this._(false, reason);
}

KaiEarnedValueAdmission admitEarnedValue(
  KaiEarnedValueRevision value, {
  required Map<String, KaiLifeEvent> availableEvents,
}) {
  final safe = RegExp(r'^[a-z0-9_]{3,64}$');
  if (!RegExp(r'^[A-Za-z0-9_-]{3,120}$').hasMatch(value.id) ||
      !safe.hasMatch(value.valueKey)) {
    return const KaiEarnedValueAdmission.refused('invalid value identifier');
  }
  if (value.statement.trim().length < 12 || value.createdAt <= 0) {
    return const KaiEarnedValueAdmission.refused('value content is too thin');
  }
  final supporting = value.evidenceFor
      .toSet()
      .map((id) => availableEvents[id])
      .whereType<KaiLifeEvent>()
      .toList();
  if (supporting.length != value.evidenceFor.toSet().length) {
    return const KaiEarnedValueAdmission.refused('value cites missing event');
  }
  if (supporting.length < 3 ||
      supporting.any((event) =>
          event.kind != KaiLifeEventKind.choice ||
          !event.valueSignals.contains(value.valueKey) ||
          event.choice.trim().length < 8 ||
          event.foregoneAlternative.trim().length < 8 ||
          event.choiceCost < 1)) {
    return const KaiEarnedValueAdmission.refused(
      'value requires three explicit costly choices',
    );
  }
  final actualCost =
      supporting.fold<int>(0, (sum, event) => sum + event.choiceCost);
  if (actualCost < 6 || value.totalChoiceCost != actualCost) {
    return const KaiEarnedValueAdmission.refused('choice cost is insufficient');
  }
  if (value.evidenceAgainst.any((id) => !availableEvents.containsKey(id))) {
    return const KaiEarnedValueAdmission.refused('counterevidence is missing');
  }
  if (value.confidence < 0.35 || value.confidence > 0.8) {
    return const KaiEarnedValueAdmission.refused(
      'value confidence exceeds developmental bounds',
    );
  }
  if (value.status == KaiEarnedValueStatus.active &&
      value.contextKeys.toSet().length < 2) {
    return const KaiEarnedValueAdmission.refused(
      'active value requires choices across contexts',
    );
  }
  if (value.status == KaiEarnedValueStatus.contextual &&
      value.contextKeys.length != 1) {
    return const KaiEarnedValueAdmission.refused(
      'contextual value must remain context-bound',
    );
  }
  return const KaiEarnedValueAdmission.admitted();
}

double earnedValueConfidence({
  required int choiceCount,
  required int totalCost,
  required int contradictionCount,
  required int contextCount,
}) {
  if (choiceCount < 3 || totalCost < 6) return 0;
  final evidence = choiceCount / (choiceCount + contradictionCount);
  final repetition = (0.48 + choiceCount.clamp(3, 6) * 0.035);
  final cost = (totalCost.clamp(6, 20) / 20) * 0.12;
  final diversity = contextCount.clamp(1, 3) * 0.035;
  return (evidence * (repetition + cost + diversity)).clamp(0.35, 0.8);
}

class KaiEarnedValueService {
  KaiEarnedValueService._();
  static final KaiEarnedValueService instance = KaiEarnedValueService._();

  String _path(String personaId) => 'kai/$personaId/earned_value_revisions';

  /// Deterministically consolidates one mature value. The language model has
  /// no role here: behavior, alternatives, cost, and context are sufficient.
  Future<bool> consolidateOne(String personaId) async {
    final events = await KaiLifeEventService.instance.recent(
      personaId,
      limit: 400,
    );
    final candidates = earnedValueCandidates(
      events,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    for (final candidate in candidates) {
      final receipt = KaiDb.instance.ref(
        'kai/$personaId/value_consolidations/${candidate.id}',
      );
      if ((await receipt.get()).exists) continue;
      final admission = await append(
        personaId,
        candidate,
        availableEvents: {for (final event in events) event.id: event},
      );
      if (!admission.admitted) return false;
      await receipt.set({
        'valueRevisionId': candidate.id,
        'createdAt': candidate.createdAt,
      });
      return true;
    }
    return false;
  }

  Future<KaiEarnedValueAdmission> append(
    String personaId,
    KaiEarnedValueRevision value, {
    required Map<String, KaiLifeEvent> availableEvents,
  }) async {
    final admission = admitEarnedValue(value, availableEvents: availableEvents);
    if (!admission.admitted) return admission;
    try {
      final ref = KaiDb.instance.ref('${_path(personaId)}/${value.id}');
      if ((await ref.get()).exists) {
        return const KaiEarnedValueAdmission.refused(
          'value revision already exists',
        );
      }
      await ref.set(value.toMap());
      return const KaiEarnedValueAdmission.admitted();
    } catch (_) {
      return const KaiEarnedValueAdmission.refused('persistence failed');
    }
  }
}

List<KaiEarnedValueRevision> earnedValueCandidates(
  List<KaiLifeEvent> events, {
  required int createdAt,
}) {
  final byValue = <String, List<KaiLifeEvent>>{};
  for (final event in events) {
    if (event.kind != KaiLifeEventKind.choice ||
        event.choiceCost < 1 ||
        event.foregoneAlternative.trim().length < 8) {
      continue;
    }
    for (final raw in event.valueSignals) {
      final key =
          raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      if (RegExp(r'^[a-z0-9_]{3,64}$').hasMatch(key)) {
        byValue.putIfAbsent(key, () => []).add(event);
      }
    }
  }
  final out = <KaiEarnedValueRevision>[];
  for (final entry in byValue.entries) {
    final choices = entry.value;
    final cost = choices.fold<int>(0, (sum, event) => sum + event.choiceCost);
    final contexts = <String>{};
    for (final event in choices) {
      contexts.addAll(event.tags
          .where((tag) => tag.toLowerCase().startsWith('context:'))
          .map((tag) => tag.substring(8).trim().toLowerCase())
          .where((tag) => tag.isNotEmpty));
    }
    if (choices.length < 3 || cost < 6 || contexts.isEmpty) continue;
    final evidence = choices.map((event) => event.id).toList()..sort();
    final counter = events
        .where((event) => event.tags
            .map((tag) => tag.toLowerCase())
            .contains('countervalue:${entry.key}'))
        .map((event) => event.id)
        .toSet()
        .toList()
      ..sort();
    final fingerprint =
        _boundedFingerprint('${entry.key}|${evidence.join('|')}');
    final label = entry.key.replaceAll('_', ' ');
    final sortedContexts = contexts.toList()..sort();
    out.add(KaiEarnedValueRevision(
      id: 'value_$fingerprint',
      valueKey: entry.key,
      statement:
          'I have repeatedly chosen $label when an easier alternative was available.',
      contextKeys: contexts.length > 1 ? sortedContexts : [contexts.first],
      evidenceFor: evidence,
      evidenceAgainst: counter,
      totalChoiceCost: cost,
      confidence: earnedValueConfidence(
        choiceCount: choices.length,
        totalCost: cost,
        contradictionCount: counter.length,
        contextCount: contexts.length,
      ),
      status: contexts.length > 1
          ? KaiEarnedValueStatus.active
          : KaiEarnedValueStatus.contextual,
      createdAt: createdAt,
    ));
  }
  out.sort((a, b) => b.confidence.compareTo(a.confidence));
  return out;
}

String _boundedFingerprint(String value) {
  var hash = 0xcbf29ce484222325;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

List<String> _strings(Object? value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const [];
