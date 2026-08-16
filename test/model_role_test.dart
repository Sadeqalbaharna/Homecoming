// Which mind is allowed to do which job.
//
// ── Why a throw and not a convention ────────────────────────────────────────
//
// constants.dart already bought this lesson: same soul files, same memory,
// smaller model — "a support drone in his hoodie." The note that survived it
// was "the model is which person shows up."
//
// The failure mode is not that local models are bad, it is that they are FREE.
// Once one is on the LAN, everything drifts toward it, and the drift shows up
// months later as a change nobody can source — because the thing that changed
// was who was writing his diary.
//
// Every caller of complete() already treats null as "local is unavailable,
// fall back to the paid model". So a polite refusal for voice-bearing work
// would be indistinguishable from Ollama being switched off, and the next
// caller would route his greetings through a 8B model with nothing objecting.
// Hence: it throws.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/local_llm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Only the non-voice roles need this: they get far enough to look up a local
  // endpoint. The voice-bearing tests below deliberately do NOT depend on it,
  // which is the proof that the gate closes before any config, network or
  // model is touched.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('the boundary is enforced, not intended', () {
    test('a local model refuses to speak as Kai', () async {
      await expectLater(
        LocalLLMService().complete(
          system: 'you are Kai',
          user: 'say good morning',
          role: ModelRole.voiceBearing,
        ),
        throwsA(isA<VoiceBearingLocalCallError>()),
      );
    });

    test('it throws before touching config, network, or a model', () {
      // The throw is the first statement in complete(). If it were later, a
      // machine with no Ollama would return null first and the boundary would
      // only exist on machines where local happens to be running — which is
      // exactly backwards.
      expect(
        () => LocalLLMService().complete(
          system: 's',
          user: 'u',
          role: ModelRole.voiceBearing,
        ),
        throwsA(isA<VoiceBearingLocalCallError>()),
        reason: 'synchronous throw, not a rejected future resolved later',
      );
    });

    test('the error says what to do instead and carries no message content',
        () {
      final e = VoiceBearingLocalCallError('role: voiceBearing');
      final text = e.toString();
      expect(text, contains('frontier'));
      expect(text, contains('role'));
      expect(text, isNot(contains('say good morning')),
          reason: 'an error is a log line; it must not carry what he was asked');
    });
  });

  group('the roles say what they permit', () {
    test('only voice-bearing work is barred from local', () {
      for (final role in ModelRole.values) {
        expect(role.allowsLocal, role != ModelRole.voiceBearing,
            reason: '$role');
      }
    });

    test('draft is the only role that owes an author stamp', () {
      // Mechanical and classification output is never stored as prose, so
      // there is nothing for a future Kai to mistake for his own words.
      // Draft output IS that prose, and the whole point of naming it draft
      // rather than mechanical is that the debt stays visible.
      expect(ModelRole.draft.requiresAuthorStamp, isTrue);
      for (final role in ModelRole.values) {
        if (role == ModelRole.draft) continue;
        expect(role.requiresAuthorStamp, isFalse, reason: '$role');
      }
    });

    test('voiceBearing cannot quietly become a stampable local role', () {
      // If someone later decides voice-bearing may run local after all, this
      // is the test they have to delete on purpose rather than satisfy by
      // adding a stamp.
      expect(ModelRole.voiceBearing.allowsLocal, isFalse);
      expect(ModelRole.voiceBearing.requiresAuthorStamp, isFalse);
    });
  });

  group('non-voice roles are allowed through', () {
    // These reach the endpoint lookup and return null when no local model is
    // configured, which is the correct degraded behaviour: caller falls back.
    for (final role in const [
      ModelRole.mechanical,
      ModelRole.classification,
      ModelRole.embedding,
      ModelRole.draft,
    ]) {
      test('${role.name} is not barred', () async {
        final result = await LocalLLMService().complete(
          system: 's',
          user: 'u',
          role: role,
        );
        expect(result, isNull,
            reason: 'no local endpoint in tests — null, never a throw');
      });
    }
  });
}
