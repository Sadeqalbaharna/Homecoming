// A differentiated relationship model. Closeness is never authorization.
library;

import 'kai_life_event_service.dart';

class KaiRelationshipModel {
  final double familiarity;
  final double epistemicTrust;
  final double emotionalSafety;
  final double reciprocity;
  final double repairConfidence;
  final double uncertainty;
  final List<String> evidenceEventIds;
  final int updatedAt;

  const KaiRelationshipModel({
    this.familiarity = 0.05,
    this.epistemicTrust = 0.1,
    this.emotionalSafety = 0.1,
    this.reciprocity = 0.05,
    this.repairConfidence = 0.05,
    this.uncertainty = 0.9,
    this.evidenceEventIds = const [],
    this.updatedAt = 0,
  });

  /// Deliberately no permission or authority field. Those remain exclusively
  /// in tool policy and explicit user consent, regardless of bond strength.
  Map<String, dynamic> toMap() => {
        'familiarity': familiarity,
        'epistemicTrust': epistemicTrust,
        'emotionalSafety': emotionalSafety,
        'reciprocity': reciprocity,
        'repairConfidence': repairConfidence,
        'uncertainty': uncertainty,
        'evidenceEventIds': evidenceEventIds,
        'updatedAt': updatedAt,
        'schemaVersion': 1,
      };
}

KaiRelationshipModel deriveRelationshipModel(
  Iterable<KaiLifeEvent> events, {
  KaiRelationshipModel seed = const KaiRelationshipModel(),
}) {
  var familiarity = seed.familiarity;
  var trust = seed.epistemicTrust;
  var safety = seed.emotionalSafety;
  var reciprocity = seed.reciprocity;
  var repair = seed.repairConfidence;
  var uncertainty = seed.uncertainty;
  var updatedAt = seed.updatedAt;
  final evidence = <String>[...seed.evidenceEventIds];
  final ordered = events
      .where((event) =>
          event.kind == KaiLifeEventKind.relationshipMoment &&
          event.relationshipDelta.isNotEmpty)
      .toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  for (final event in ordered) {
    double apply(double current, String key) {
      final signal = event.relationshipDelta[key] ?? 0;
      if (signal == 0) return current;
      // Losses update faster than gains; one warm exchange cannot create trust.
      final rate = signal < 0 ? 0.075 : 0.035;
      return (current + signal * rate).clamp(0.0, 1.0);
    }

    familiarity = apply(familiarity, 'familiarity');
    trust = apply(trust, 'epistemicTrust');
    safety = apply(safety, 'emotionalSafety');
    reciprocity = apply(reciprocity, 'reciprocity');
    repair = apply(repair, 'repairConfidence');
    uncertainty = (uncertainty - 0.025).clamp(0.15, 0.95);
    evidence.add(event.id);
    updatedAt = event.occurredAt > updatedAt ? event.occurredAt : updatedAt;
  }
  return KaiRelationshipModel(
    familiarity: familiarity,
    epistemicTrust: trust,
    emotionalSafety: safety,
    reciprocity: reciprocity,
    repairConfidence: repair,
    uncertainty: uncertainty,
    evidenceEventIds: evidence.toSet().toList(growable: false),
    updatedAt: updatedAt,
  );
}
