// Reply recovery — does he preserve the work, and does he tell the truth?
//
// The old version of this file asserted:
//
//     expect(recovered, contains('no beige support-drone bullshit'));
//
// Read that again. It pinned a hardcoded string in place and called it a test.
// Same failure as the old dashboard test that asserted the source contained
// '7 / 7 layers complete' — it checked the WORD, not the work, and passed
// happily while the thing it described was false.
//
// What matters here isn't which words he uses. It's whether what he says is
// TRUE. So that's what these test: the reply survives, and the diagnosis matches
// the error — especially that he never promises a retry on something that can
// never succeed.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/reply_recovery_service.dart';

void main() {
  group('the answer survives the bookkeeping', () {
    // §7.4: a canned 55-char string on iteration exhaustion was DELETING all his
    // work, every turn. This is the case that must never regress.
    test('preserves a completed reply when post-processing fails', () {
      final recovered = KaiReplyRecoveryService.postProcessingFailureReply(
        recoveredReply: 'Here is the useful answer.',
        error: Exception('TTS exploded\nstack trace noise'),
      );

      expect(recovered, startsWith('Here is the useful answer.'));
      expect(recovered, contains('[post-processing note: Exception: TTS exploded]'));
      expect(recovered, isNot(contains('stack trace noise')));
    });

    test('a real reply is never buried under an error, whatever the error', () {
      for (final err in [
        Exception('insufficient_quota'),
        Exception('429 rate_limit_exceeded'),
        Exception('401 invalid api key'),
        Exception('who knows'),
      ]) {
        final r = KaiReplyRecoveryService.postProcessingFailureReply(
          recoveredReply: 'The answer.',
          error: err,
        );
        expect(r, startsWith('The answer.'),
            reason: 'his work outranks the error report, always');
      }
    });
  });

  group('he reads the error instead of guessing', () {
    test('classifies an empty account as out of credit', () {
      // The real one Sadeq hit. Kai told him he'd "go straight back in" — on an
      // error that would fail identically forever.
      expect(
        KaiReplyRecoveryService.classify(Exception(
            'DioException: You exceeded your current quota, insufficient_quota')),
        FailureKind.outOfCredit,
      );
    });

    test('a rate limit is transient, an empty wallet is not', () {
      expect(KaiReplyRecoveryService.classify(Exception('rate_limit_exceeded')),
          FailureKind.transient);
      expect(KaiReplyRecoveryService.classify(Exception('insufficient_quota')),
          FailureKind.outOfCredit);
      // Both are HTTP 429 and they mean opposite things. This is the distinction
      // the whole file exists to get right.
    });

    test('auth, bad request, timeout', () {
      expect(KaiReplyRecoveryService.classify(Exception('401 unauthorized')),
          FailureKind.auth);
      expect(
          KaiReplyRecoveryService.classify(
              Exception('400 unsupported parameter: max_tokens')),
          FailureKind.badRequest);
      expect(KaiReplyRecoveryService.classify(Exception('connection timed out')),
          FailureKind.transient);
    });

    test('unknown stays unknown — he does not invent a diagnosis', () {
      expect(KaiReplyRecoveryService.classify(Exception('splorked the frobnicator')),
          FailureKind.unknown);
    });
  });

  group('he never promises a retry he cannot keep', () {
    test('out of credit is not retryable', () {
      expect(KaiReplyRecoveryService.isRetryable(FailureKind.outOfCredit), isFalse);
      expect(KaiReplyRecoveryService.isRetryable(FailureKind.auth), isFalse);
      expect(KaiReplyRecoveryService.isRetryable(FailureKind.badRequest), isFalse);
    });

    test('transient and unknown are worth another go', () {
      expect(KaiReplyRecoveryService.isRetryable(FailureKind.transient), isTrue);
      expect(KaiReplyRecoveryService.isRetryable(FailureKind.unknown), isTrue);
    });

    test('the out-of-credit message says the true thing and points at billing', () {
      final r = KaiReplyRecoveryService.postProcessingFailureReply(
        recoveredReply: null,
        error: Exception('insufficient_quota: You exceeded your current quota'),
      );
      expect(r.toLowerCase(), contains('credit'));
      expect(r.toLowerCase(), contains('platform.openai.com'));
      // The exact lie the old string told, on this exact error.
      expect(r.toLowerCase(), isNot(contains('try that again and')),
          reason: 'retrying an empty wallet fails identically, forever');
    });

    test('an unknown failure admits it rather than bluffing', () {
      final r = KaiReplyRecoveryService.postProcessingFailureReply(
        recoveredReply: '   ',
        error: StateError('model call failed'),
      );
      // presenceDirective: "when I don't know something I just say so and figure
      // it out instead of bluffing". This file was the one place he was made to
      // do the opposite.
      expect(r.toLowerCase(), contains("don't know"));
      expect(r, contains('Bad state: model call failed'),
          reason: 'the real error reaches Sadeq — it is the only useful part');
    });

    test('the error is always surfaced, never swallowed', () {
      for (final err in [
        Exception('insufficient_quota'),
        Exception('401 unauthorized'),
        Exception('400 unsupported parameter'),
        Exception('connection timed out'),
        Exception('mystery'),
      ]) {
        final r = KaiReplyRecoveryService.postProcessingFailureReply(
          recoveredReply: null,
          error: err,
        );
        expect(r, contains(err.toString().split('\n').first),
            reason: 'the technical note is the thing that lets Sadeq fix it');
      }
    });
  });
}
