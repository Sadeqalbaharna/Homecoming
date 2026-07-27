library;

import 'kai_autobiography_service.dart';
import 'kai_noticed_service.dart';
import 'kai_router_service.dart';

class KaiSelfRelevance {
  const KaiSelfRelevance._();

  static List<Noticed> commitments({
    required List<Noticed> candidates,
    required String message,
    required KaiRoute? route,
    required Map<String, int> mood,
    Map<String, int> personality = const {},
    required int limit,
  }) =>
      _rank<Noticed>(
        candidates.where(
            (item) => item.authoredByKai && item.authorReceiptId.isNotEmpty),
        limit,
        (item) => _score(
          '${item.kind.name} ${item.text} ${item.context}',
          message,
          route,
          mood,
          personality,
          commitment: true,
          emotional: item.kind == NoticedKind.responsibility ||
              item.kind == NoticedKind.promise,
          occurredAt: item.notedAt,
        ),
      );

  static List<AutobiographicalEpisode> episodes({
    required List<AutobiographicalEpisode> candidates,
    required String message,
    required KaiRoute? route,
    required Map<String, int> mood,
    Map<String, int> personality = const {},
    required int limit,
  }) =>
      _rank<AutobiographicalEpisode>(
        candidates.where((item) => item.isGrounded),
        limit,
        (item) => _score(
          '${item.kind.name} ${item.choice} ${item.outcome} ${item.meaning}',
          message,
          route,
          mood,
          personality,
          commitment: item.kind == AutobiographicalEpisodeKind.commitment,
          emotional: item.kind == AutobiographicalEpisodeKind.correctedBelief ||
              item.kind == AutobiographicalEpisodeKind.identityRevision,
          occurredAt: item.occurredAt,
        ),
      );

  static List<T> _rank<T>(
    Iterable<T> candidates,
    int limit,
    double Function(T item) score,
  ) {
    if (limit <= 0) return const [];
    final ranked = candidates
        .map((item) => (item: item, score: score(item)))
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    return ranked
        .take(limit)
        .map((entry) => entry.item)
        .toList(growable: false);
  }

  static double _score(
    String record,
    String message,
    KaiRoute? route,
    Map<String, int> mood,
    Map<String, int> personality, {
    required bool commitment,
    required bool emotional,
    required int occurredAt,
  }) {
    final recordTerms = _terms(record);
    final messageTerms = _terms(message);
    var score = recordTerms.intersection(messageTerms).length * 5.0;
    if (commitment && (route == KaiRoute.tool || route == KaiRoute.coding)) {
      score += 3;
    }
    if (emotional && route == KaiRoute.emotional) score += 4;
    if (emotional && ((mood['valence'] ?? 50) < 38)) score += 2;
    if (route == KaiRoute.contemplate) score += 1;
    if ((personality['intuition'] ?? 500) >= 650 &&
        route == KaiRoute.contemplate) {
      score += recordTerms.intersection(_reflectiveTerms).isNotEmpty ? 1 : 0;
    }
    final ageDays = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(occurredAt))
        .inDays;
    score += (3 - ageDays / 30).clamp(0, 3);
    return score;
  }

  static Set<String> _terms(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 4 && !_stopWords.contains(term))
      .toSet();

  static const _stopWords = {
    'that',
    'this',
    'with',
    'from',
    'have',
    'will',
    'into',
    'about',
    'after',
    'before',
    'they',
    'them',
    'then',
    'when',
    'what',
    'your',
    'mine'
  };
  static const _reflectiveTerms = {
    'meaning',
    'identity',
    'purpose',
    'dream',
    'pattern',
    'belief',
    'changed'
  };
}
