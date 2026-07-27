// Current motives are temporary, competing pressures—not personality or truth.
library;

enum KaiMotiveKind {
  goal,
  valueExpression,
  care,
  curiosity,
  continuity,
  repair
}

class KaiMotive {
  final String id;
  final KaiMotiveKind kind;
  final String aim;
  final List<String> sourceIds;
  final List<String> contextTerms;
  final double activation;
  final double selfEndorsement;
  final double uncertainty;
  final int formedAt;
  final int expiresAt;

  const KaiMotive({
    required this.id,
    required this.kind,
    required this.aim,
    required this.sourceIds,
    this.contextTerms = const [],
    required this.activation,
    required this.selfEndorsement,
    required this.uncertainty,
    required this.formedAt,
    required this.expiresAt,
  });
}

class KaiMotiveField {
  final KaiMotive? foreground;
  final List<KaiMotive> background;
  final List<String> conflicts;

  const KaiMotiveField({
    required this.foreground,
    required this.background,
    required this.conflicts,
  });
}

bool admissibleMotive(KaiMotive motive, {required int now}) {
  if (!RegExp(r'^[A-Za-z0-9_-]{3,120}$').hasMatch(motive.id) ||
      motive.aim.trim().length < 8 ||
      motive.sourceIds.isEmpty ||
      motive.formedAt <= 0 ||
      motive.expiresAt <= motive.formedAt ||
      motive.expiresAt <= now) {
    return false;
  }
  if (motive.activation < 0.1 ||
      motive.activation > 0.9 ||
      motive.selfEndorsement < 0 ||
      motive.selfEndorsement > 0.9 ||
      motive.uncertainty < 0.1 ||
      motive.uncertainty > 0.95) {
    return false;
  }
  return motive.sourceIds.every((id) =>
      id.startsWith('goal:') ||
      id.startsWith('value:') ||
      id.startsWith('event:') ||
      id.startsWith('schema:'));
}

KaiMotiveField resolveMotiveField(
  Iterable<KaiMotive> motives, {
  required String currentContext,
  required int now,
  double moodBias = 0,
}) {
  final terms = currentContext
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length > 2)
      .toSet();
  final admitted = motives
      .where((motive) => admissibleMotive(motive, now: now))
      .map((motive) {
    final overlap = motive.contextTerms
        .map((term) => term.toLowerCase())
        .where(terms.contains)
        .length;
    final relevance = (overlap * 0.08).clamp(0, 0.24);
    // Affect may tint attention but is intentionally too weak to invent or
    // reverse a motive.
    final affect = moodBias.clamp(-0.05, 0.05);
    final score = motive.activation * 0.55 +
        motive.selfEndorsement * 0.25 +
        relevance -
        motive.uncertainty * 0.12 +
        affect;
    return (motive: motive, score: score);
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  if (admitted.isEmpty) {
    return const KaiMotiveField(
      foreground: null,
      background: [],
      conflicts: [],
    );
  }
  final foreground = admitted.first.motive;
  final background =
      admitted.skip(1).take(3).map((item) => item.motive).toList();
  final conflicts = <String>[];
  for (final item in background) {
    if (_opposes(foreground, item)) {
      conflicts.add('${foreground.id}<->${item.id}');
    }
  }
  return KaiMotiveField(
    foreground: foreground,
    background: background,
    conflicts: conflicts,
  );
}

bool _opposes(KaiMotive a, KaiMotive b) {
  const pairs = {
    'speed|accuracy',
    'explore|finish',
    'protect|disclose',
    'persist|rest',
    'repair|withdraw',
  };
  final aTerms = a.aim.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
  final bTerms = b.aim.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
  return pairs.any((pair) {
    final parts = pair.split('|');
    return (aTerms.contains(parts[0]) && bTerms.contains(parts[1])) ||
        (aTerms.contains(parts[1]) && bTerms.contains(parts[0]));
  });
}
