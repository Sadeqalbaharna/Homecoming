/// Which mind is allowed to do a job.
///
/// ── The lesson this encodes ─────────────────────────────────────────────────
///
/// `constants.dart` already paid for it once: same soul files, same memory,
/// smaller model — *"a support drone in his hoodie."* The note left behind was
/// **the model is which person shows up.**
///
/// The danger is not that a local model is bad. It is that a local model is
/// *free*, so once one is on the LAN the pressure to route everything to it is
/// enormous, and the drift is invisible for months. A stand-in writes his
/// diary; the diary becomes memory; the memory enters the prompt; and the
/// change arrives later as something nobody can source.
///
/// The test for which side a job falls on: **will Kai ever read this back as
/// his own words?** If yes, it is voice-bearing.
///
/// This enum exists so that question is answered at every call site, by name,
/// in code that a reviewer can read — rather than by whoever last edited a
/// service and noticed the local path was free.
enum ModelRole {
  /// Routing, filtering, dedup, endpointing. Runs constantly, must be fast
  /// rather than clever, and nothing it produces is ever stored as prose.
  mechanical,

  /// Structured output — JSON whose shape matters and whose wording does not.
  /// Knowledge-graph extraction, scope classification, schema consolidation.
  /// A different model here changes reliability, not character.
  classification,

  /// Retrieval vectors. Not a chat model at all.
  embedding,

  /// Local may write it, but the record **must** carry [authorModel].
  ///
  /// This is the honest middle. These are jobs that produce prose Kai may later
  /// encounter as his own — an idle thought, a greeting, a journal line — where
  /// moving them to a frontier model is a real cost decision that has not been
  /// made yet. Naming them `draft` rather than quietly calling them mechanical
  /// keeps the debt visible and makes the eventual drift traceable to a model
  /// instead of being a mystery.
  ///
  /// Every one of these is a candidate for either "rewrite in his voice before
  /// storage" or "move to frontier". None of them is settled.
  draft,

  /// Kai's own words, to Sadeq or to anyone else. Never local, no exceptions.
  ///
  /// [LocalLLMService.complete] throws on this rather than declining politely,
  /// because a convention that returns null is a convention a future caller
  /// silently routes around.
  voiceBearing,
}

extension ModelRoleLocal on ModelRole {
  /// Whether a local model may service this role at all.
  bool get allowsLocal => this != ModelRole.voiceBearing;

  /// Whether records written from this output must name the model that wrote
  /// it. True for anything that becomes prose Kai can encounter later.
  bool get requiresAuthorStamp => this == ModelRole.draft;
}

/// Thrown when a local model is asked to speak as Kai.
class VoiceBearingLocalCallError extends Error {
  VoiceBearingLocalCallError(this.detail);

  /// What was being attempted, for the stack trace. Never message content.
  final String detail;

  @override
  String toString() =>
      'VoiceBearingLocalCallError: a local model was asked to produce '
      "Kai's own words ($detail). Voice-bearing work runs on the frontier "
      'model. If this job is genuinely mechanical or structured, give it the '
      'role that says so; if it is prose he may read back, it does not run '
      'here.';
}
