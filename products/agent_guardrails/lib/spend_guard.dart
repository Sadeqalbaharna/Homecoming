// spend_guard.dart — bound an agent turn by money, not by round count.
//
// ── Why round limits are the wrong tool ─────────────────────────────────────
//
// The usual safety valve on an agent loop is a maximum iteration count: stop
// after 20 rounds. It is the wrong measure twice over.
//
// It stops useful work. An agent making genuine progress on round 21 is cut off
// mid-task for no reason connected to anything you care about.
//
// And it fails to stop expensive work. Cost per round is not constant — every
// round re-sends the whole conversation, so spend grows QUADRATICALLY. A long
// system prompt plus accumulated tool output means round 20 can cost many times
// round 1. Twenty rounds is not a budget; it is a number that feels safe.
//
// What you actually care about is money and progress. So bound the turn by
// tokens spent, and detect the pathological case directly: the same call, with
// the same arguments, over and over. That is being stuck, which is different
// from working slowly.
//
// Pure Dart. Zero dependencies.
library;

/// Why a turn stopped. Distinguishing these matters — "finished" and "ran out
/// of money" and "went in circles" need different responses.
enum StopReason {
  /// Still within budget and making progress.
  none,

  /// The token budget for this turn is exhausted.
  budgetExhausted,

  /// The same call with identical arguments repeated — stuck, not working.
  loopDetected,

  /// A hard ceiling on iterations, retained only as a backstop against
  /// pathological cases the other two miss.
  iterationCeiling,
}

class SpendGuard {
  /// Total tokens (input + output) permitted for one turn.
  ///
  /// Size this against the cost you are willing to pay for ONE completed task,
  /// not against a round count. Because spend is quadratic, a budget that feels
  /// generous often fires far earlier than expected — measure before trusting.
  final int tokenBudget;

  /// How many identical consecutive calls constitute a loop. Two repeats (three
  /// identical calls) is a reasonable default: one repeat can be a legitimate
  /// retry after a transient failure.
  final int loopThreshold;

  /// Backstop only. Deliberately high — this should almost never be what stops
  /// a turn, and if it regularly is, the other limits are misconfigured.
  final int maxIterations;

  SpendGuard({
    this.tokenBudget = 1000000,
    this.loopThreshold = 2,
    this.maxIterations = 400,
  });

  int _tokensUsed = 0;
  int _iterations = 0;
  String? _lastSignature;
  int _repeats = 0;

  int get tokensUsed => _tokensUsed;
  int get iterations => _iterations;

  /// Fraction of the budget consumed, 0.0–1.0+. Useful for surfacing a live
  /// cost meter — spend the user cannot see is spend they cannot object to.
  double get budgetFraction =>
      tokenBudget <= 0 ? 0 : _tokensUsed / tokenBudget;

  /// Record one model call. Returns the reason to stop, or [StopReason.none].
  ///
  /// [signature] should uniquely identify the action taken — typically the tool
  /// name plus its serialised arguments. Pass null for turns that produced text
  /// rather than an action; text is never a loop.
  StopReason record({
    required int inputTokens,
    required int outputTokens,
    String? signature,
  }) {
    _iterations++;
    _tokensUsed += inputTokens + outputTokens;

    if (signature != null) {
      if (signature == _lastSignature) {
        _repeats++;
        if (_repeats >= loopThreshold) return StopReason.loopDetected;
      } else {
        _lastSignature = signature;
        _repeats = 0;
      }
    }

    if (_tokensUsed > tokenBudget) return StopReason.budgetExhausted;
    if (_iterations >= maxIterations) return StopReason.iterationCeiling;
    return StopReason.none;
  }

  /// A sentence explaining the stop, suitable for showing a user or feeding
  /// back to the model so it can respond to the real constraint.
  String explain(StopReason reason) => switch (reason) {
        StopReason.none => 'Within budget.',
        StopReason.budgetExhausted =>
          'Turn stopped at $_tokensUsed tokens (budget $tokenBudget). '
              'Stopping to let a human decide rather than quietly spending more.',
        StopReason.loopDetected =>
          'Same call repeated ${_repeats + 1}x with identical arguments — '
              'that is stuck, not working. Retrying will not change the result.',
        StopReason.iterationCeiling =>
          'Hit the iteration backstop at $_iterations. If this fires often, the '
              'token budget is set too high to be doing its job.',
      };

  void reset() {
    _tokensUsed = 0;
    _iterations = 0;
    _lastSignature = null;
    _repeats = 0;
  }
}
