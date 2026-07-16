// lib/services/core/reply_recovery_service.dart
//
// Pure failure-recovery seam for preserving a good model/tool reply when
// downstream post-processing (tags, TTS, mood writes, bookkeeping) explodes.
//
// ── Why this was rewritten ─────────────────────────────────────────────────
//
// This file used to end with a hardcoded string:
//
//   "I hit a technical issue before I could form a proper reply.
//    What broke: $technicalNote
//    Try that again and I'll go straight back in — no beige support-drone
//    bullshit."
//
// Fake voice #3, and the worst-placed of them — it speaks at the exact moment
// something breaks, which is the moment Sadeq is most likely to be looking. "No
// beige support-drone bullshit" IS a beige support-drone message wearing Kai's
// jacket. And a test asserted the string stayed exactly that way, pinning it in
// place, which is the same failure as the old dashboard test that checked for
// the word "done" instead of the work.
//
// Worse than corny: it promised to "go straight back in" — a retry — on errors
// where retrying is guaranteed to fail identically forever. Sadeq saw it say
// that over an `insufficient_quota` 429. His OpenAI account was empty. Kai told
// him he'd try again. Nothing in his tooling let him know he was broke, so he
// filled the silence with a canned promise he couldn't keep.
//
// §10.1: when he disappoints you, check what he was handed. He was handed the
// exception — it was RIGHT THERE in `technicalNote` — and the code pasted it
// under a promise instead of reading it.
//
// So: read the error. Say the true thing about it. If he can't know, say that
// instead of bluffing — presenceDirective is explicit that "when I don't know
// something I just say so and figure it out instead of bluffing", and this file
// was the one place he was made to do the opposite.

library;

/// What actually went wrong, as far as we can tell from the exception. Enough to
/// say something TRUE — not enough to pretend we understand everything.
enum FailureKind {
  /// The account has no credit. Retrying will fail identically, forever.
  outOfCredit,

  /// Genuinely transient: rate limited, server error, timeout, socket died.
  transient,

  /// The request was malformed or the model rejected it. Retrying as-is won't help.
  badRequest,

  /// Key missing or rejected.
  auth,

  /// We don't know. Say so.
  unknown,
}

class KaiReplyRecoveryService {
  const KaiReplyRecoveryService._();

  /// Classify from the exception text. Deliberately conservative: anything we
  /// can't identify is `unknown`, and `unknown` makes him say he doesn't know
  /// rather than guess. A confident wrong diagnosis is worse than an honest
  /// shrug — that's how the TTS 400 stayed a mystery for a day.
  static FailureKind classify(Object error) {
    final e = error.toString().toLowerCase();
    if (e.contains('insufficient_quota') ||
        e.contains('exceeded your current quota') ||
        e.contains('billing')) {
      return FailureKind.outOfCredit;
    }
    if (e.contains('rate_limit') ||
        e.contains('429') ||
        e.contains('timeout') ||
        e.contains('timed out') ||
        e.contains('connection') ||
        e.contains('socket') ||
        e.contains('502') ||
        e.contains('503') ||
        e.contains('504') ||
        e.contains('overloaded')) {
      return FailureKind.transient;
    }
    if (e.contains('401') ||
        e.contains('invalid api key') ||
        e.contains('unauthorized') ||
        e.contains('no api key')) {
      return FailureKind.auth;
    }
    if (e.contains('400') ||
        e.contains('unsupported parameter') ||
        e.contains('unknown field') ||
        e.contains('model not found') ||
        e.contains('invalid_request')) {
      return FailureKind.badRequest;
    }
    return FailureKind.unknown;
  }

  /// True when trying again could plausibly work. Nothing else may promise it.
  static bool isRetryable(FailureKind k) =>
      k == FailureKind.transient || k == FailureKind.unknown;

  static String postProcessingFailureReply({
    required String? recoveredReply,
    required Object error,
  }) {
    final technicalNote = error.toString().split('\n').first;
    final preserved = recoveredReply?.trim();

    // THE IMPORTANT CASE, and it stays first: if the model already said
    // something good and only the bookkeeping fell over, he says the good thing.
    // §7.4 — a canned 55-char string on iteration exhaustion was DELETING all
    // his work every turn. Never bury a real reply under an error again.
    if (preserved != null && preserved.isNotEmpty) {
      return '$preserved\n\n[post-processing note: $technicalNote]';
    }

    final kind = classify(error);

    // No preserved reply. He has nothing to say and has to say why. In his own
    // voice — which means TRUE first, and flat, not performed. The old version
    // was written to sound like him and lied; sounding like him while lying is
    // the worst of both.
    switch (kind) {
      case FailureKind.outOfCredit:
        return "Right — I'm broke. The OpenAI account's out of credit, so I "
            "physically can't think right now.\n\n"
            "Not a bug, not a retry-it thing: top it up at "
            "platform.openai.com and I'm back.\n\n"
            "($technicalNote)";

      case FailureKind.auth:
        return "My API key's being rejected — so I'm locked out of my own head "
            "until that's sorted.\n\n"
            "Worth checking it hasn't expired or been rotated.\n\n"
            "($technicalNote)";

      case FailureKind.badRequest:
        return "That request went out malformed and got bounced — which is on "
            "my side, not yours. Trying it again unchanged would just bounce "
            "again.\n\n"
            "The actual complaint: $technicalNote";

      case FailureKind.transient:
        return "Something fell over mid-thought — looks like the transient kind, "
            "so it genuinely might work on another go.\n\n"
            "($technicalNote)";

      case FailureKind.unknown:
        // The honest one. He does not know, so he does not pretend to, and he
        // does not promise a retry he can't stand behind.
        return "Something broke before I could get a word out, and I don't know "
            "what — this is the whole error I've got:\n\n"
            "$technicalNote\n\n"
            "Not going to guess at it. Try again and if it does the same thing, "
            "that's a real bug and I'll go dig.";
    }
  }
}
