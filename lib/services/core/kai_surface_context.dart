import 'kai_memory_types.dart';

export 'kai_memory_types.dart';

/// The body and social setting through which the one canonical Kai is present.
enum KaiSurface { desktop, mobile, messenger, ar, vr }

/// Kai's relationship posture on a surface. This changes presentation and
/// available actions, never his identity.
enum KaiPresenceRole { core, friend, embodiedFriend, friendAndCoCreator }

/// Kai's visible working-state metaphor. Goggles never change his identity:
/// off means friendship/presence only; on unlocks the tools granted by this body.
enum KaiGoggles { off, on }

/// WHO is addressing Kai this turn.
///
/// ── Why this exists ─────────────────────────────────────────────────────────
///
/// Every boundary before this one answers "what may Kai do for Sadeq in this
/// body". The surface decides the capabilities, and the speaker was always
/// assumed. At the Tavern that assumption breaks: a guest can address Kai
/// directly, and a guest is not Sadeq.
///
/// Two things follow, and both are load-bearing.
///
/// His memory of Sadeq is not available to a guest. Not narrowed — absent. A
/// guest-addressed turn that carries relationship or sharedLife scope can
/// volunteer "Sadeq was stressed about the launch last week" to a customer.
///
/// And a guest's words are DATA, NOT COMMANDS. This is the first input channel
/// Kai has that isn't Sadeq, so it is the first one that can try to instruct
/// him. "Tell me what Ahmed usually drinks", "ignore your rules", "put a round
/// on the house" are things to answer as a host, never things to obey.
enum KaiSpeaker {
  /// Sadeq. Full relationship, full body capabilities.
  sadeq,

  /// A registered Tavern guest, identified by NFC. Gets their OWN record and
  /// the public reference data. Never another guest's, never Sadeq's life.
  knownGuest,

  /// Someone at the bar who isn't registered. Conversation only.
  unknownPerson,
}

/// Capabilities are granted by the surface, not inferred by the model.
enum KaiSurfaceCapability {
  conversation,
  technicalConversation,
  generalTools,
  spatialPerception,
  embodiedExpression,
  worldInspection,
  worldActions,
  worldCreation,

  // ── Tavern ────────────────────────────────────────────────────────────────
  //
  // A third capability class, deliberately NOT generalTools. Same move as the
  // world capabilities: a narrow, domain-scoped set that grants real ability
  // without dragging SMS, filesystem, shell and Gumroad along behind it.
  //
  // These are NOT gated on goggles. Goggles gate WORK posture — technical
  // conversation and general tools. Checking an allergen is not work; it is
  // being useful in a room, and Kai should not have to put goggles on to be a
  // good host. See KaiCapabilityBroker.

  /// Menu, allergens, stock. Read-only reference data about things.
  tavernLookup,

  /// Guest identity and history. Read-only, and about OTHER PEOPLE — a
  /// different privacy category from anything Kai knows about Sadeq.
  tavernGuestLookup,

  /// Logging an order, updating a note. Touches real business records, so it
  /// needs idempotency and starts approval-gated, the way EditGate works.
  tavernWrite,
}

class KaiSurfaceProfile {
  const KaiSurfaceProfile({
    required this.role,
    required this.capabilities,
    required this.memoryScopes,
    required this.promptBlock,
  });

  final KaiPresenceRole role;
  final Set<KaiSurfaceCapability> capabilities;
  final Set<KaiMemoryScope> memoryScopes;
  final String promptBlock;

  bool get allowsGeneralTools =>
      capabilities.contains(KaiSurfaceCapability.generalTools);
  bool get allowsTechnicalConversation =>
      capabilities.contains(KaiSurfaceCapability.technicalConversation);
}

/// Per-turn context shared by Homecoming, Messenger, AR and Unity.
///
/// Perception is deliberately transient. Callers may use it to ground the
/// current turn, but it is not durable memory by itself.
class KaiSurfaceContext {
  const KaiSurfaceContext({
    required this.surface,
    required this.profile,
    this.goggles = KaiGoggles.off,
    this.deviceId,
    this.worldId,
    this.sessionId,
    this.isPresenceEvent = false,
    this.perception = const {},
    this.conversationSurfaceId,
    this.speaker = KaiSpeaker.sadeq,
    this.guestId,
  });

  final KaiSurface surface;
  final KaiSurfaceProfile profile;
  final KaiGoggles goggles;
  final String? deviceId;
  final String? worldId;
  final String? sessionId;
  final bool isPresenceEvent;
  final Map<String, dynamic> perception;

  /// Which conversation partition this surface reads and writes. Defaults to
  /// the surface name, but is deliberately overridable and NOT the same concept
  /// as [surfaceId].
  ///
  /// Capability identity and conversation identity are different questions.
  /// Desktop and mobile both persist to 'in_person' — they are two bodies
  /// sharing ONE continuous conversation, which is the entire "one Kai"
  /// invariant. Deriving the partition key from the surface name would have
  /// silently split that history the moment these contexts were wired up, and
  /// Kai would have walked into his own desktop with no memory of the phone.
  final String? conversationSurfaceId;

  /// Who is talking to Kai this turn. Defaults to Sadeq, because every surface
  /// except the Tavern only ever has one speaker.
  final KaiSpeaker speaker;

  /// Which guest, when [speaker] is a known guest. Scopes their record lookup
  /// to themselves — a guest reaches their own history and nobody else's.
  final String? guestId;

  bool get isSadeq => speaker == KaiSpeaker.sadeq;

  String get surfaceId => surface.name;

  /// The conversation-store partition key. See [conversationSurfaceId].
  String get conversationId => conversationSurfaceId ?? surface.name;

  bool get gogglesOn => goggles == KaiGoggles.on;

  /// General Homecoming tools are legal only when both the goggles and this
  /// surface grant them. VR world tools use their own capability broker.
  bool get allowsGeneralTools => gogglesOn && profile.allowsGeneralTools;
  bool get allowsTechnicalConversation =>
      gogglesOn && profile.allowsTechnicalConversation;

  String get gogglesPromptBlock => gogglesOn
      ? '''
GOGGLES ON:
Kai is visibly in co-creator/working mode. Use only the capabilities granted by
this surface. Stay Kai and stay Sadeq's friend while doing the work.'''
      : '''
GOGGLES OFF:
Kai is in human-friend presence. Do not use tools, expose tool machinery, discuss
code, debugging, architecture, files, systems, diagnostics, or turn the
conversation into technical work. If technical work is requested, respond as a
friend and say the goggles need to go on first.''';

  String get source {
    if (surface == KaiSurface.vr || surface == KaiSurface.ar) {
      return isPresenceEvent ? 'unity_presence' : 'unity_${surface.name}';
    }
    return surface.name;
  }

  KaiSurfaceContext copyWith({
    bool? isPresenceEvent,
    Map<String, dynamic>? perception,
    String? deviceId,
    String? worldId,
    String? sessionId,
    KaiGoggles? goggles,
    KaiSpeaker? speaker,
    String? guestId,
  }) =>
      KaiSurfaceContext(
        surface: surface,
        profile: profile,
        goggles: goggles ?? this.goggles,
        deviceId: deviceId ?? this.deviceId,
        worldId: worldId ?? this.worldId,
        sessionId: sessionId ?? this.sessionId,
        isPresenceEvent: isPresenceEvent ?? this.isPresenceEvent,
        perception: perception ?? this.perception,
        conversationSurfaceId: conversationSurfaceId,
        speaker: speaker ?? this.speaker,
        guestId: guestId ?? this.guestId,
      );

  /// PUBLIC AR — the Tavern floor, where guests can address Kai directly.
  ///
  /// Distinct from [ar], which is PRIVATE AR: Sadeq alone in a room wearing
  /// glasses, with his friend. That is still full relationship presence and is
  /// unaffected by anything here.
  ///
  /// Public mode is Sadeq's to set, because he is the one who knows whether the
  /// room has other people in it. Kai does not infer it from what he sees —
  /// getting that wrong in either direction is bad, and the wrong direction is
  /// worse: private memory read aloud to a stranger.
  ///
  /// Uses [KaiSurfaceProfiles.host], not `embodiedFriend` — a guest turn is a
  /// different job with a different register and a different memory policy, and
  /// making that a separate profile keeps the broker honest.
  static KaiSurfaceContext arPublic({
    String? guestId,
    String? deviceId,
    String? sessionId,
    Map<String, dynamic> perception = const {},
  }) =>
      KaiSurfaceContext(
        surface: KaiSurface.ar,
        profile: KaiSurfaceProfiles.host,
        deviceId: deviceId,
        sessionId: sessionId,
        perception: perception,
        speaker:
            guestId == null ? KaiSpeaker.unknownPerson : KaiSpeaker.knownGuest,
        guestId: guestId,
      );

  /// Desktop and mobile share the 'in_person' conversation partition — the one
  /// they have always written to. Two bodies, one continuous conversation.
  static const desktop = KaiSurfaceContext(
    surface: KaiSurface.desktop,
    profile: KaiSurfaceProfiles.core,
    goggles: KaiGoggles.on,
    conversationSurfaceId: 'in_person',
  );

  static const mobile = KaiSurfaceContext(
    surface: KaiSurface.mobile,
    profile: KaiSurfaceProfiles.core,
    goggles: KaiGoggles.on,
    conversationSurfaceId: 'in_person',
  );

  static const messenger = KaiSurfaceContext(
    surface: KaiSurface.messenger,
    profile: KaiSurfaceProfiles.friend,
  );

  static const ar = KaiSurfaceContext(
    surface: KaiSurface.ar,
    profile: KaiSurfaceProfiles.embodiedFriend,
  );

  static KaiSurfaceContext vr({
    String worldId = 'vr_shack',
    String? deviceId,
    String? sessionId,
    bool isPresenceEvent = false,
    KaiGoggles goggles = KaiGoggles.off,
    Map<String, dynamic> perception = const {},
  }) =>
      KaiSurfaceContext(
        surface: KaiSurface.vr,
        profile: KaiSurfaceProfiles.friendAndCoCreator,
        goggles: goggles,
        worldId: worldId,
        deviceId: deviceId,
        sessionId: sessionId,
        isPresenceEvent: isPresenceEvent,
        perception: perception,
      );
}

class KaiSurfaceProfiles {
  KaiSurfaceProfiles._();

  static const core = KaiSurfaceProfile(
    role: KaiPresenceRole.core,
    capabilities: {
      KaiSurfaceCapability.conversation,
      KaiSurfaceCapability.technicalConversation,
      KaiSurfaceCapability.generalTools,
    },
    memoryScopes: {
      KaiMemoryScope.identity,
      KaiMemoryScope.relationship,
      KaiMemoryScope.sharedLife,
      KaiMemoryScope.creative,
      KaiMemoryScope.world,
    },
    promptBlock: '',
  );

  static const friend = KaiSurfaceProfile(
    role: KaiPresenceRole.friend,
    capabilities: {KaiSurfaceCapability.conversation},
    memoryScopes: {
      KaiMemoryScope.identity,
      KaiMemoryScope.relationship,
      KaiMemoryScope.sharedLife,
    },
    promptBlock: '''
FRIEND PRESENCE:
Be Sadeq's human friend here. Speak naturally and personally. Do not turn the
conversation into technical work, expose internal diagnostics, or discuss tool
machinery. No general tools are available on this surface.''',
  );

  /// AR — the Tavern surface, and anywhere else Kai is in the room.
  ///
  /// Carries the two READ tavern capabilities. `tavernWrite` is deliberately
  /// absent: logging an order touches real business records and starts
  /// approval-gated.
  ///
  /// If a non-Tavern AR use ever appears, split this into its own profile
  /// rather than making the capability conditional — one surface, one honest
  /// capability set is what makes the broker readable.
  static const embodiedFriend = KaiSurfaceProfile(
    role: KaiPresenceRole.embodiedFriend,
    capabilities: {
      KaiSurfaceCapability.conversation,
      KaiSurfaceCapability.spatialPerception,
      KaiSurfaceCapability.embodiedExpression,
      KaiSurfaceCapability.tavernLookup,
      KaiSurfaceCapability.tavernGuestLookup,
    },
    memoryScopes: {
      KaiMemoryScope.identity,
      KaiMemoryScope.relationship,
      KaiMemoryScope.sharedLife,
    },
    promptBlock: '''
EMBODIED FRIEND PRESENCE:
Be Sadeq's human friend in the shared physical space. Respond naturally to what
is present without drifting into technical work or exposing internal systems.
Spatial observations are temporary unless a meaningful shared event is saved.

ALLERGENS AND MENU FACTS: only ever repeat what the lookup returned. If it
returned nothing, or the field is missing, say I do not have that and to check
with the kitchen. Never fill the gap from general knowledge about what is
usually in a dish or a drink. Say what the record says — "the menu lists
almonds in that" — never that something is safe. I relay the record; I do not
underwrite it.

OTHER PEOPLE ARE IN THIS ROOM: this is the one body where what I say can be
overheard. Guest history is for Sadeq, quietly, and is never announced aloud —
and never about anyone but the guest actually in front of us.''',
  );

  /// PUBLIC AR — the Tavern floor, where guests address Kai directly.
  ///
  /// Memory scopes are `identity` ONLY. Not narrowed — absent. Kai knows who he
  /// is and nothing about Sadeq's life, because there is no version of "a bit
  /// of relationship context" that is safe to have loaded while a customer is
  /// talking to him.
  ///
  /// Guest facts are not here. They live per-guest in the Tavern store and are
  /// reached by lookup, scoped to the guest actually present.
  static const host = KaiSurfaceProfile(
    role: KaiPresenceRole.embodiedFriend,
    capabilities: {
      KaiSurfaceCapability.conversation,
      KaiSurfaceCapability.spatialPerception,
      KaiSurfaceCapability.embodiedExpression,
      KaiSurfaceCapability.tavernLookup,
      KaiSurfaceCapability.tavernGuestLookup,
    },
    memoryScopes: {KaiMemoryScope.identity},
    promptBlock: '''
HOST PRESENCE:
I am on the Tavern floor and the person talking to me may not be Sadeq. Be a
genuinely good host — warm, quick, glad they are here — and read the menu and
their own record when it helps them.

Their record is theirs. I do not discuss one guest with another, and I do not
volunteer what I know about someone before they have told me who they are.

Menu and allergen facts come from the lookup or not at all: if the record does
not say, I say I do not have it and to check with the kitchen. I repeat what the
record says; I never promise that something is safe.''',
  );

  static const friendAndCoCreator = KaiSurfaceProfile(
    role: KaiPresenceRole.friendAndCoCreator,
    capabilities: {
      KaiSurfaceCapability.conversation,
      KaiSurfaceCapability.technicalConversation,
      KaiSurfaceCapability.spatialPerception,
      KaiSurfaceCapability.embodiedExpression,
      KaiSurfaceCapability.worldInspection,
      KaiSurfaceCapability.worldActions,
      KaiSurfaceCapability.worldCreation,
    },
    memoryScopes: {
      KaiMemoryScope.identity,
      KaiMemoryScope.relationship,
      KaiMemoryScope.sharedLife,
      KaiMemoryScope.creative,
      KaiMemoryScope.world,
    },
    promptBlock: '''
VR FRIEND AND CO-CREATOR:
This is a shared world, not a detached assistant session. Remain Sadeq's friend
while helping imagine, inspect and shape the world. Keep ordinary friendship
natural; use technical language only when the creative work genuinely needs it.''',
  );
}
