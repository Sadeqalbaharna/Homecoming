import 'kai_router_service.dart';
import 'kai_surface_context.dart';

export 'kai_memory_types.dart';

/// Transport-only presence seeds are not autobiographical events.
bool shouldFormMemoryForTurn(KaiSurfaceContext? context) =>
    context?.isPresenceEvent != true;

class KaiMemoryAccessPolicy {
  const KaiMemoryAccessPolicy({
    required this.allowedScopes,
    this.worldId,
    this.allowAllWorlds = false,
    this.allowTechnicalContent = false,
  });

  final Set<KaiMemoryScope> allowedScopes;
  final String? worldId;
  final bool allowAllWorlds;
  final bool allowTechnicalContent;

  bool allows({required KaiMemoryScope scope, String? memoryWorldId}) {
    if (!allowedScopes.contains(scope)) return false;
    if (scope != KaiMemoryScope.world) return true;
    if (allowAllWorlds) return true;
    return worldId != null && worldId == memoryWorldId;
  }

  /// Scope answers where a memory may travel; this answers whether its subject
  /// belongs in the current posture. A relationship memory can still contain a
  /// pasted debugging exchange, so goggles-off must enforce both boundaries.
  bool allowsContent(String text) =>
      allowTechnicalContent ||
      (!looksLikeTechnicalContent(text) &&
          !text
              .toLowerCase()
              .contains('goggles off, friend. i’m keeping the work talk'));

  /// Full access, for offline tests and local tooling that has no surface.
  ///
  /// Named rather than reachable by omission. The old fail-open path was the
  /// `null` branch of [forContext], which meant "I forgot to pass a context"
  /// and "I deliberately want everything" were the same expression. Now the
  /// second one has to be typed out, and it says so.
  ///
  /// Never use this on a request path. A request has a body; the body decides.
  static const trustedCore = KaiMemoryAccessPolicy(
    allowAllWorlds: true,
    allowTechnicalContent: true,
    allowedScopes: {
      KaiMemoryScope.identity,
      KaiMemoryScope.relationship,
      KaiMemoryScope.sharedLife,
      KaiMemoryScope.creative,
      KaiMemoryScope.world,
      KaiMemoryScope.episodic,
      KaiMemoryScope.ephemeral,
      KaiMemoryScope.privateCore,
      KaiMemoryScope.legacyUnscoped,
    },
  );

  static KaiMemoryAccessPolicy forContext(KaiSurfaceContext? context) {
    // Someone other than Sadeq is talking. His memory is not narrowed here, it
    // is ABSENT — there is no amount of relationship or shared-life context
    // that is safe to have loaded while a customer is in the conversation. One
    // retrieval of "he was stressed about the launch last week" said warmly to
    // the wrong person is not recoverable.
    //
    // Checked before the surface, so no profile can widen it by accident.
    if (context != null && !context.isSadeq) {
      return const KaiMemoryAccessPolicy(
        allowedScopes: {KaiMemoryScope.identity},
      );
    }

    // A missing surface has no authority — the same rule KaiCapabilityBroker
    // now applies, and these two were disagreeing.
    //
    // This branch used to grant EVERY scope plus allowTechnicalContent, which
    // made it the most permissive policy in the system. Its sibling one file
    // over had already been inverted to fail closed, so a caller with no
    // context got no tools and his entire private memory. Backwards: the memory
    // is the more sensitive of the two, and a leak there is not recoverable.
    //
    // Nothing in lib/ relies on it. The one production caller passes a real
    // surface, and no background service queries memory at all. If a future
    // caller needs recall, it names the body it is speaking from.
    if (context == null) {
      return const KaiMemoryAccessPolicy(allowedScopes: {});
    }

    if (context.surface == KaiSurface.desktop ||
        context.surface == KaiSurface.mobile) {
      return KaiMemoryAccessPolicy(
        allowAllWorlds: true,
        allowTechnicalContent: context.allowsTechnicalConversation,
        allowedScopes: {
          KaiMemoryScope.identity,
          KaiMemoryScope.relationship,
          KaiMemoryScope.sharedLife,
          KaiMemoryScope.creative,
          KaiMemoryScope.world,
          KaiMemoryScope.episodic,
          KaiMemoryScope.privateCore,
          KaiMemoryScope.legacyUnscoped,
        },
      );
    }

    if (context.surface == KaiSurface.vr && context.gogglesOn) {
      return KaiMemoryAccessPolicy(
        worldId: context.worldId,
        allowTechnicalContent: true,
        allowedScopes: const {
          KaiMemoryScope.identity,
          KaiMemoryScope.relationship,
          KaiMemoryScope.sharedLife,
          KaiMemoryScope.creative,
          KaiMemoryScope.world,
        },
      );
    }

    return const KaiMemoryAccessPolicy(
      allowedScopes: {
        KaiMemoryScope.identity,
        KaiMemoryScope.relationship,
        KaiMemoryScope.sharedLife,
      },
    );
  }
}

/// Conservative lexical guard for context supplied to a friend-presence turn.
/// This is not a general topic classifier; it blocks unmistakable implementation
/// language before that text reaches the model. Ambiguous everyday words are
/// deliberately excluded to preserve ordinary conversation.
bool looksLikeTechnicalContent(String text) {
  final lower = text.toLowerCase();
  const unmistakable = <String>[
    'api key',
    'authentication',
    'firebase',
    'database',
    'repository',
    'codebase',
    'code area',
    'related code',
    'touching code',
    'source code',
    'debugging',
    'debug ',
    'architecture',
    'implementation detail',
    'technical implementation',
    'calibration phrase',
    'checksum',
    'hot restart',
    'stack trace',
    'exception',
    'memory embedding',
    'restore logic',
    'chat history',
    'desktop messenger',
    'phone messenger',
    'messenger ui',
    'storage/restore',
    'restore mismatch',
    'patched restore',
    'startup issue',
    'startup noise',
    'patch the',
    'patching the',
    'flutter',
  ];
  if (unmistakable.any(lower.contains)) return true;

  final signals = <RegExp>[
    RegExp(r'\b(?:code|coding|technical|server|backend|frontend)\b'),
    RegExp(r'\b(?:file|files|folder|folders)\b'),
    RegExp(r'\b(?:build|compile|deploy|patch|refactor)\b'),
    RegExp(r'\b(?:function|class|method|query|schema)\b'),
  ];
  return signals.where((signal) => signal.hasMatch(lower)).length >= 2;
}

/// The current knowledge graph is global, so only globally safe memories may
/// enter it. Creative/world/private material remains in the scoped vector store
/// until the graph itself carries equivalent scope metadata.
bool shouldExtractIntoSharedKnowledgeGraph({
  required KaiMemoryScope scope,
  required String userText,
  required String kaiReply,
}) {
  const sharedScopes = {
    KaiMemoryScope.identity,
    KaiMemoryScope.relationship,
    KaiMemoryScope.sharedLife,
  };
  return sharedScopes.contains(scope) &&
      !looksLikeTechnicalContent('$userText\n$kaiReply');
}

/// Final fail-closed boundary for visible friend-presence speech.
///
/// Providers are filtered upstream, but model output is still untrusted. Keep
/// safe personal paragraphs from a mixed reply and discard implementation
/// paragraphs before display, speech, and memory formation.
const kaiGogglesOffWorkBoundary =
    'Goggles off, friend. I’m keeping the work talk for when we put them on.';

String sanitizeGogglesOffReply(
  String reply, {
  String? userText,
}) {
  final lower = reply.toLowerCase();
  final mixesBoundaryWithWork = lower.contains('goggles') &&
      RegExp(r'\b(?:work|working|fix|fixing|startup|project|machinery|code|technical|implementation)\b')
          .hasMatch(lower);
  // A boundary-shaped sentence in Kai's reply is not proof that Sadeq asked
  // for work. The model may mention the goggles while correcting a previous
  // misunderstanding, or retrieved conversation may prime that wording. Only
  // collapse to the stock boundary when the current input is actually
  // technical. Callers without the input retain the conservative legacy rule.
  if (mixesBoundaryWithWork &&
      (userText == null || looksLikeTechnicalContent(userText))) {
    return kaiGogglesOffWorkBoundary;
  }
  if (!looksLikeTechnicalContent(reply)) return reply;

  final safe = reply
      .split(RegExp(r'\n\s*\n'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !looksLikeTechnicalContent(part))
      .where((part) => !(part.length < 100 && part.endsWith(':')))
      .toList(growable: false);

  if (safe.isNotEmpty) return safe.join('\n\n');

  // Models often answer a personal idea and an implementation thought in one
  // paragraph. Paragraph-only filtering made one technical sentence poison the
  // entire human reply. Salvage complete personal sentences before falling back
  // to the boundary; this keeps friend mode conversational without leaking the
  // machinery that happened to share its paragraph.
  final safeSentences = reply
      .split(RegExp(r'(?<=[.!?])\s+|\n+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !looksLikeTechnicalContent(part))
      .where((part) =>
          !part.toLowerCase().contains('goggles off, friend') &&
          !part.toLowerCase().contains('goggles need to go on'))
      .toList(growable: false);
  if (safeSentences.isNotEmpty) return safeSentences.join(' ');

  return kaiGogglesOffWorkBoundary;
}

KaiMemoryScope scopeForTurn({
  required KaiSurfaceContext? context,
  required KaiRoute route,
  KaiRoute? requestedRoute,
  String? userText,
  String? kaiReply,
}) {
  if (context == null) return KaiMemoryScope.privateCore;

  // A guest conversation is not Kai's life. It is never relationship material,
  // however warm it was — that record belongs to the guest, in the Tavern
  // store, not in the history of his friendship with Sadeq. Checked first so
  // the emotional rule below cannot promote a stranger's turn.
  if (!context.isSadeq) return KaiMemoryScope.ephemeral;

  // The capability broker may collapse a forbidden coding/tool request to
  // fastChat so Kai can answer safely. That presentation route must not rewrite
  // the subject into relationship memory. Otherwise the request and any
  // accidental technical wording in the refusal become readable on Messenger.
  // Preserve the original request classification solely for memory isolation.
  if (!context.gogglesOn &&
      (requestedRoute == KaiRoute.coding || requestedRoute == KaiRoute.tool)) {
    return KaiMemoryScope.privateCore;
  }
  if (!context.gogglesOn &&
      looksLikeTechnicalContent('${userText ?? ''}\n${kaiReply ?? ''}')) {
    return KaiMemoryScope.privateCore;
  }

  // A genuine emotional moment is relationship material in any body, including
  // AR. Checked first so the rule below cannot swallow it.
  if (route == KaiRoute.emotional) return KaiMemoryScope.relationship;

  // AR narrates a room that contains OTHER PEOPLE. Left as relationship — which
  // is what goggles-off produced — "that's Ahmed, third visit, walnut allergy"
  // became Kai's durable personal memory and surfaced on Messenger as though it
  // were something from his own life. Third-party data does not belong in the
  // record of his friendship with Sadeq.
  //
  // Guest facts live per-guest in the Tavern store and are reached by lookup,
  // not by recall. The conversation around them is transient by design — which
  // is what the embodiedFriend profile already promises: "spatial observations
  // are temporary unless a meaningful shared event is saved."
  if (context.surface == KaiSurface.ar) return KaiMemoryScope.ephemeral;

  if (!context.gogglesOn) return KaiMemoryScope.relationship;
  if (context.surface == KaiSurface.vr) {
    // Intent routing cannot see the content of Kai's eventual answer. A casual
    // recall question can still produce an implementation secret, so scope the
    // completed exchange rather than trusting the question classification alone.
    if (looksLikeTechnicalContent('${userText ?? ''}\n${kaiReply ?? ''}')) {
      return KaiMemoryScope.creative;
    }
    // The shared EXPERIENCE travels with him; the work of building does not.
    // A VR session is both — "we built the loft and he lost it at the crooked
    // window" belongs on Messenger; "the lighting rig needs a second pass"
    // does not.
    //
    // This previously returned `creative` unconditionally. `creative` is
    // granted to core and goggles-on VR only, so EVERY VR memory was stranded
    // inside VR: leave the Shack, open Messenger, and the afternoon you just
    // spent together was gone. That is the one-Kai invariant failing in the
    // one place the whole surface model exists to protect, and it is the
    // reason Day 7 step 8 could not have passed.
    //
    // This is NOT the KaiVrMemoryPair two-record write. That pair is
    // experience + ARTIFACT, and no artifact exists until Unity world actions
    // are wired — writing the same conversation text under two scopes would be
    // duplication with two visibilities, not two records. The real pair lands
    // with the world-action event, keyed by eventId.
    //
    // Known limitation: this inherits KaiRouterService's keyword coverage.
    // "let's put a window here" hits 'design' → contemplate → creative, so a
    // genuinely memorable moment can still be scoped too narrow. It fails
    // CLOSED, which is the correct direction to be wrong in — an experience
    // that didn't travel is recoverable, a leaked one is not.
    return route == KaiRoute.fastChat
        ? KaiMemoryScope.relationship
        : KaiMemoryScope.creative;
  }
  // ── The fail-open default, inverted ─────────────────────────────────────────
  //
  // This used to be `if (route == fastChat) return sharedLife`. Read it against
  // what fastChat actually means: KaiRouterService returns fastChat when NOTHING
  // MATCHED. It is the router's shrug, not a finding of personal content.
  //
  // So the rule said "anything I could not classify is shared life" — and
  // sharedLife is Messenger-visible. Every reads-side control in this file is
  // conservative and fails closed; the write side was optimistic and failed
  // open, on the one branch that runs for every ordinary desktop turn. A
  // technical question phrased without a keyword the router knows became
  // readable on the friend surface, permanently, with no event to notice.
  //
  // The router was never built as a security boundary. It is a latency
  // optimisation that picks a prompt shape, and its keyword list is openly
  // under-inclusive — 'why did that break' matches nothing at all.
  //
  // Now: privateCore unless something positive says otherwise. An absent signal
  // is not evidence of intimacy.
  return KaiMemoryScope.privateCore;
}

/// The scope decision, plus whether anything is allowed to widen it.
///
/// [scope] is always safe to persist as-is. [marginal] means only that a
/// classifier MAY promote this turn to [promotion]; it never means the closed
/// answer was wrong. A caller that ignores this whole type entirely still
/// behaves correctly, just more privately — which is the property that makes it
/// safe to put a model anywhere near this decision.
class KaiMemoryScopeDecision {
  const KaiMemoryScopeDecision({
    required this.scope,
    required this.reasonCode,
    this.marginal = false,
    this.promotion,
  });

  /// The fail-closed scope. Persist this if anything at all goes wrong.
  final KaiMemoryScope scope;

  /// Why, for the audit line. Never contains message content.
  final String reasonCode;

  /// True when a memory-worthiness classifier is permitted to run.
  final bool marginal;

  /// The only scope a classifier may promote this turn to. Null when none.
  final KaiMemoryScope? promotion;
}

/// Whether a turn is even eligible for promotion, and to what.
///
/// Deliberately narrow: the margin is exactly the branch the old fail-open rule
/// used to cover — Sadeq, goggles on, non-technical, unroutable. Everything the
/// pure function already decides positively (an emotional turn, a guest turn, a
/// VR experience, anything technical) is returned closed and un-promotable, so
/// no model call can revisit a decision that was already made on evidence.
KaiMemoryScopeDecision scopeDecisionForTurn({
  required KaiSurfaceContext? context,
  required KaiRoute route,
  KaiRoute? requestedRoute,
  String? userText,
  String? kaiReply,
}) {
  final scope = scopeForTurn(
    context: context,
    route: route,
    requestedRoute: requestedRoute,
    userText: userText,
    kaiReply: kaiReply,
  );

  // Anything that did not land on the inverted default was decided by a
  // positive rule. Leave it alone.
  if (scope != KaiMemoryScope.privateCore) {
    return KaiMemoryScopeDecision(scope: scope, reasonCode: 'positive_rule');
  }
  if (context == null) {
    return const KaiMemoryScopeDecision(
      scope: KaiMemoryScope.privateCore,
      reasonCode: 'no_surface',
    );
  }
  if (!context.isSadeq) {
    return const KaiMemoryScopeDecision(
      scope: KaiMemoryScope.privateCore,
      reasonCode: 'not_sadeq',
    );
  }
  // Technical material is closed on evidence, not on absence. A classifier does
  // not get to argue with it — that is the leak this whole file exists to stop.
  if (looksLikeTechnicalContent('${userText ?? ''}\n${kaiReply ?? ''}')) {
    return const KaiMemoryScopeDecision(
      scope: KaiMemoryScope.privateCore,
      reasonCode: 'technical_content',
    );
  }
  if (requestedRoute == KaiRoute.coding || requestedRoute == KaiRoute.tool) {
    return const KaiMemoryScopeDecision(
      scope: KaiMemoryScope.privateCore,
      reasonCode: 'work_intent',
    );
  }
  // Only an unroutable, non-technical turn from Sadeq reaches the margin.
  if (route == KaiRoute.fastChat) {
    return const KaiMemoryScopeDecision(
      scope: KaiMemoryScope.privateCore,
      reasonCode: 'unrouted_margin',
      marginal: true,
      promotion: KaiMemoryScope.sharedLife,
    );
  }
  return const KaiMemoryScopeDecision(
    scope: KaiMemoryScope.privateCore,
    reasonCode: 'routed_work',
  );
}
