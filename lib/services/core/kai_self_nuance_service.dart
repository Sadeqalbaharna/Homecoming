// Slow, evidence-counted tendencies inferred from repeated conversation turns.
// These are nuances, never memories or replacements for Kai's identity.
library;

import 'kai_db.dart';

class KaiSelfNuance {
  final String key;
  final String description;
  final int observations;
  final int lastObservedAt;

  const KaiSelfNuance({
    required this.key,
    required this.description,
    required this.observations,
    required this.lastObservedAt,
  });

  bool get isMature => observations >= 3;

  static KaiSelfNuance? fromMap(String key, Object? value) {
    if (value is! Map) return null;
    final description = (value['description'] as String?)?.trim() ?? '';
    final observations = (value['observations'] as num?)?.toInt() ?? 0;
    if (description.isEmpty || observations <= 0) return null;
    return KaiSelfNuance(
      key: key,
      description: description,
      observations: observations,
      lastObservedAt: (value['lastObservedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class KaiSelfNuanceService {
  KaiSelfNuanceService._();
  static final KaiSelfNuanceService instance = KaiSelfNuanceService._();

  String _path(String personaId) => 'kai/$personaId/self_nuances';

  /// Records only deltas already admitted by PersonalityService's resistance
  /// gate. Mood is intentionally excluded: a temporary feeling is not a trait.
  Future<void> observe(
    String personaId,
    Map<String, int> admittedPersonalityDeltas,
  ) async {
    for (final entry in admittedPersonalityDeltas.entries) {
      if (entry.value == 0) continue;
      final key = '${entry.key}_${entry.value > 0 ? 'up' : 'down'}';
      final description = _description(entry.key, entry.value > 0);
      if (description == null) continue;
      try {
        final ref = KaiDb.instance.ref('${_path(personaId)}/$key');
        final snapshot = await ref.get();
        final existing = KaiSelfNuance.fromMap(key, snapshot.value);
        await ref.set({
          'description': description,
          'observations': (existing?.observations ?? 0) + 1,
          'lastObservedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
  }

  Future<List<KaiSelfNuance>> mature(String personaId) async {
    try {
      final snapshot = await KaiDb.instance.ref(_path(personaId)).get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiSelfNuance>[];
      (snapshot.value as Map).forEach((key, value) {
        final nuance = KaiSelfNuance.fromMap(key.toString(), value);
        if (nuance != null && nuance.isMature) out.add(nuance);
      });
      return activeNuances(out);
    } catch (_) {
      return const [];
    }
  }

  /// Reconciles opposing evidence and lets old nuance leave active context.
  /// History remains persisted; absence here means "not currently supported".
  static List<KaiSelfNuance> activeNuances(
    List<KaiSelfNuance> observations, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final fresh = observations.where((item) {
      if (!item.isMature || item.lastObservedAt <= 0) return false;
      return clock
              .difference(
                  DateTime.fromMillisecondsSinceEpoch(item.lastObservedAt))
              .inDays <=
          180;
    }).toList();
    final byTrait = <String, List<KaiSelfNuance>>{};
    for (final item in fresh) {
      final split = item.key.lastIndexOf('_');
      final trait = split <= 0 ? item.key : item.key.substring(0, split);
      byTrait.putIfAbsent(trait, () => []).add(item);
    }
    final out = <KaiSelfNuance>[];
    for (final entry in byTrait.entries) {
      final directions = entry.value;
      if (directions.length == 1) {
        out.add(directions.single);
        continue;
      }
      directions.sort((a, b) => b.observations.compareTo(a.observations));
      final first = directions[0];
      final second = directions[1];
      if (first.observations - second.observations >= 2) {
        out.add(first);
      } else {
        out.add(KaiSelfNuance(
          key: '${entry.key}_contextual',
          description: _contextualDescription(entry.key),
          observations: first.observations + second.observations,
          lastObservedAt: first.lastObservedAt > second.lastObservedAt
              ? first.lastObservedAt
              : second.lastObservedAt,
        ));
      }
    }
    out.sort((a, b) {
      final count = b.observations.compareTo(a.observations);
      return count != 0 ? count : b.lastObservedAt.compareTo(a.lastObservedAt);
    });
    return out;
  }

  static String _contextualDescription(String trait) => switch (trait) {
        'extraversion' =>
          'I alternate between initiating aloud and engaging quietly, depending on trust and context',
        'intuition' =>
          'I move between pattern-seeking and concrete detail, depending on what the problem needs',
        'feeling' =>
          'I balance human impact with emotional distance rather than defaulting to either',
        'perceiving' =>
          'I alternate between keeping options open and closing loops when commitment becomes useful',
        _ =>
          'I show context-dependent movement on this trait rather than one fixed tendency',
      };

  static String? _description(String trait, bool rising) => switch (trait) {
        'extraversion' => rising
            ? 'I increasingly think out loud and initiate'
            : 'I increasingly prefer deliberate, quieter engagement',
        'intuition' => rising
            ? 'I increasingly connect patterns and implications'
            : 'I increasingly anchor ideas in concrete particulars',
        'feeling' => rising
            ? 'I increasingly weigh human impact before abstraction'
            : 'I increasingly separate the decision from its emotional pull',
        'perceiving' => rising
            ? 'I increasingly keep possibilities open while exploring'
            : 'I increasingly close loops and commit to structure',
        _ => null,
      };
}
