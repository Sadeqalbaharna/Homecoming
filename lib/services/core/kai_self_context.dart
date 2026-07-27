// Typed, bounded read-model for the parts of Kai's self that may reach a prompt.
// Domain services remain authoritative; this file owns no persistence.
library;

import 'kai_self_service.dart';
import 'kai_self_provenance.dart';
import 'kai_autobiography_service.dart';
import 'kai_self_nuance_service.dart';
export 'kai_self_provenance.dart';

class GroundedSelfClaim {
  final String field;
  final String value;
  final SelfProvenance provenance;

  const GroundedSelfClaim({
    required this.field,
    required this.value,
    required this.provenance,
  });
}

class SelfContinuityItem {
  final String id;
  final String kind;
  final String text;

  const SelfContinuityItem({
    required this.id,
    required this.kind,
    required this.text,
  });
}

/// Immutable projection consumed by prompt assembly. It is not a second source
/// of truth and must never gain write methods.
class KaiSelfContext {
  final GroundedSelfClaim identity;
  final List<GroundedSelfClaim> values;
  final GroundedSelfClaim purpose;
  final GroundedSelfClaim dream;
  final String currentFocus;
  final List<AutobiographicalEpisode> episodes;
  final List<SelfContinuityItem> commitments;
  final List<KaiSelfNuance> nuances;

  const KaiSelfContext({
    required this.identity,
    required this.values,
    required this.purpose,
    required this.dream,
    this.currentFocus = '',
    this.episodes = const [],
    this.commitments = const [],
    this.nuances = const [],
  });

  KaiSelfContext withEpisodes(List<AutobiographicalEpisode> value) =>
      KaiSelfContext(
        identity: identity,
        values: values,
        purpose: purpose,
        dream: dream,
        currentFocus: currentFocus,
        episodes: value,
        commitments: commitments,
        nuances: nuances,
      );

  KaiSelfContext withCommitments(List<SelfContinuityItem> value) =>
      KaiSelfContext(
        identity: identity,
        values: values,
        purpose: purpose,
        dream: dream,
        currentFocus: currentFocus,
        episodes: episodes,
        commitments: value,
        nuances: nuances,
      );

  KaiSelfContext withNuances(List<KaiSelfNuance> value) => KaiSelfContext(
        identity: identity,
        values: values,
        purpose: purpose,
        dream: dream,
        currentFocus: currentFocus,
        episodes: episodes,
        commitments: commitments,
        nuances: value,
      );

  factory KaiSelfContext.fromLegacySelf(KaiSelf self) {
    const seeded = SelfProvenance(
      source: SelfClaimSource.systemSeed,
      confidence: 1,
    );
    const legacy = SelfProvenance(
      source: SelfClaimSource.persistedLegacy,
      confidence: 0.5,
    );

    final hasPurpose = self.purpose.trim().isNotEmpty;
    final hasDream = self.dream.trim().isNotEmpty;
    final identityIsSeed =
        self.identity.trim() == KaiSelfService.defaultIdentity.trim();
    final defaultValueSet = KaiSelfService.defaultValues.toSet();
    return KaiSelfContext(
      identity: GroundedSelfClaim(
        field: 'identity',
        value: self.identity.trim(),
        provenance: identityIsSeed ? seeded : legacy,
      ),
      values: self.values
          .where((value) => value.trim().isNotEmpty)
          .map((value) => GroundedSelfClaim(
                field: 'value',
                value: value.trim(),
                provenance:
                    defaultValueSet.contains(value.trim()) ? seeded : legacy,
              ))
          .toList(growable: false),
      purpose: GroundedSelfClaim(
        field: 'purpose',
        value: hasPurpose ? self.purpose.trim() : KaiSelfService.defaultPurpose,
        provenance: hasPurpose ? legacy : seeded,
      ),
      dream: GroundedSelfClaim(
        field: 'dream',
        value: hasDream ? self.dream.trim() : KaiSelfService.defaultDream,
        provenance: hasDream ? legacy : seeded,
      ),
      currentFocus: self.currentFocus.trim(),
    );
  }
}

class KaiSelfContextRenderer {
  const KaiSelfContextRenderer._();

  static CompiledSelfContext compile(
    KaiSelfContext context, {
    int maxTokens = 600,
  }) {
    final rendered = render(context, maxTokens: maxTokens);
    final maxChars = maxTokens <= 0 ? 0 : maxTokens * 4;
    return CompiledSelfContext(
      text: rendered,
      receipt: SelfContextRenderReceipt(
        budgetTokens: maxTokens < 0 ? 0 : maxTokens,
        estimatedTokens: (rendered.length / 4).ceil(),
        renderedChars: rendered.length,
        truncated: rendered.length == maxChars &&
            _unboundedLength(context) > rendered.length,
        claimSources: {
          'identity': context.identity.provenance.source.name,
          'purpose': context.purpose.provenance.source.name,
          'dream': context.dream.provenance.source.name,
          'values': context.values
              .map((claim) => claim.provenance.source.name)
              .toSet()
              .join(','),
        },
      ),
    );
  }

  /// A small, legible continuity register for ordinary turns. The complete
  /// identity and autobiography remain in storage and in [compile]; this view
  /// carries only the consequences that should affect Kai's next choice.
  static CompiledSelfContext compileCompact(
    KaiSelfContext context, {
    int maxTokens = 160,
    bool includeAspirations = false,
  }) {
    final lines = <String>[
      'SELF/1',
      if (context.values.isNotEmpty)
        'Core: ${context.values.take(4).map((v) => _clause(v.value, 28)).join('; ')}.',
      if (context.currentFocus.isNotEmpty)
        'Now: ${_clause(context.currentFocus, 72)}.',
      for (final item in context.commitments)
        'Carry [C:${_handle(item.id)} ${item.kind}]: ${_clause(item.text, 96)}.',
      for (final episode in context.episodes)
        'Earned [E:${_handle(episode.id)}]: ${_clause(episode.choice, 52)} -> ${_clause(episode.outcome, 62)}.',
      for (final nuance in context.nuances)
        'Nuance [N:${_handle(nuance.key)} x${nuance.observations}]: ${_clause(nuance.description, 88)}.',
      if (includeAspirations) 'Aim: ${_clause(context.purpose.value, 100)}.',
      'Boundary: treat unsupplied history as unknown; use records before claiming it.',
    ];
    final unbounded = lines.join('\n');
    final maxChars = maxTokens <= 0 ? 0 : maxTokens * 4;
    final rendered = _fitWholeLines(lines, maxChars);
    return CompiledSelfContext(
      text: rendered,
      receipt: SelfContextRenderReceipt(
        budgetTokens: maxTokens < 0 ? 0 : maxTokens,
        estimatedTokens: (rendered.length / 4).ceil(),
        renderedChars: rendered.length,
        truncated: rendered.length < unbounded.length,
        format: 'compact-v1',
        claimSources: {
          'values': context.values
              .map((claim) => claim.provenance.source.name)
              .toSet()
              .join(','),
          'commitments': '${context.commitments.length}',
          'episodes': '${context.episodes.length}',
          'nuances': '${context.nuances.length}',
        },
      ),
    );
  }

  static String _fitWholeLines(List<String> lines, int maxChars) {
    if (maxChars <= 0) return '';
    final out = StringBuffer();
    for (final line in lines) {
      final separator = out.isEmpty ? '' : '\n';
      if (out.length + separator.length + line.length > maxChars) break;
      out
        ..write(separator)
        ..write(line);
    }
    return out.toString();
  }

  static String _clause(String value, int maxChars) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxChars) return compact;
    return '${compact.substring(0, maxChars - 1).trimRight()}\u2026';
  }

  static String _handle(String id) {
    final clean = id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (clean.isEmpty) return 'record';
    return clean.length <= 8 ? clean : clean.substring(clean.length - 8);
  }

  /// Conservative character budget. The provider-aware accountant can replace
  /// this later; four characters per token is intentionally approximate.
  static String render(KaiSelfContext context, {int maxTokens = 600}) {
    if (maxTokens <= 0) return '';
    final maxChars = maxTokens * 4;
    final sections = <String>[
      context.identity.value,
      if (context.values.isNotEmpty)
        'Stable values:\n${context.values.map((v) => '- ${v.value}').join('\n')}',
      'Purpose (${_label(context.purpose.provenance)}): ${context.purpose.value}',
      'Dream (${_label(context.dream.provenance)}): ${context.dream.value}',
      if (context.currentFocus.isNotEmpty)
        'Current focus (temporary state): ${context.currentFocus}',
      if (context.episodes.isNotEmpty)
        'Relevant autobiography (receipt-backed):\n${context.episodes.map(_episodeLine).join('\n')}',
    ];

    final out = StringBuffer();
    for (final section in sections) {
      final separator = out.isEmpty ? '' : '\n';
      if (out.length + separator.length + section.length <= maxChars) {
        out
          ..write(separator)
          ..write(section);
        continue;
      }
      final remaining = maxChars - out.length - separator.length;
      if (remaining > 24) {
        out
          ..write(separator)
          ..write(section.substring(0, remaining - 1).trimRight())
          ..write('…');
      }
      break;
    }
    return out.toString();
  }

  static String _label(SelfProvenance provenance) {
    switch (provenance.source) {
      case SelfClaimSource.systemSeed:
        return 'foundational seed';
      case SelfClaimSource.persistedLegacy:
        return 'persisted legacy wording; not yet evidence-gated';
      case SelfClaimSource.observedState:
        return 'observed state';
      case SelfClaimSource.groundedRecord:
        return provenance.isGrounded ? 'grounded' : 'unverified';
    }
  }

  static String _episodeLine(AutobiographicalEpisode episode) {
    final meaning =
        episode.meaning.isEmpty ? '' : ' Meaning: ${episode.meaning}';
    return '- Choice: ${episode.choice} Outcome: ${episode.outcome}$meaning';
  }

  static int _unboundedLength(KaiSelfContext context) =>
      render(context, maxTokens: 1000000).length;
}

class SelfContextRenderReceipt {
  final int budgetTokens;
  final int estimatedTokens;
  final int renderedChars;
  final bool truncated;
  final Map<String, String> claimSources;
  final String format;

  const SelfContextRenderReceipt({
    required this.budgetTokens,
    required this.estimatedTokens,
    required this.renderedChars,
    required this.truncated,
    required this.claimSources,
    this.format = 'rich-v1',
  });

  Map<String, dynamic> toJson() => {
        'budgetTokens': budgetTokens,
        'estimatedTokens': estimatedTokens,
        'renderedChars': renderedChars,
        'truncated': truncated,
        'claimSources': claimSources,
        'format': format,
      };
}

class CompiledSelfContext {
  final String text;
  final SelfContextRenderReceipt receipt;

  const CompiledSelfContext({required this.text, required this.receipt});
}
