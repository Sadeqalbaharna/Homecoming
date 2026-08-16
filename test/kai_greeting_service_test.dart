import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_greeting_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('overnight greeting cannot leak an ordinary private inner thought', () {
    expect(
      KaiGreetingService.debugShareableGreetingThought({
        'text': 'I am still thinking about the two Kai headers.',
        'origin': 'model_generated',
      }),
      isNull,
    );
  });

  test('overnight greeting accepts only explicit genuine shareable thought', () {
    expect(
      KaiGreetingService.debugShareableGreetingThought({
        'text': 'A small thought worth sharing.',
        'origin': 'model_generated',
        'shareable': true,
      }),
      'A small thought worth sharing.',
    );
    expect(
      KaiGreetingService.debugShareableGreetingThought({
        'text': 'A canned fallback.',
        'origin': 'model_generated',
        'shareable': true,
        'synthetic': true,
      }),
      isNull,
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Kai greeting keeps debug/boot counters out of spoken greetings', () async {
    final line = await KaiGreetingService.build('test-kai');
    final lower = line.toLowerCase();

    expect(line, isNot(contains('Waking #')));
    expect(lower, isNot(contains('awakening')));
    expect(lower, isNot(contains('still kicking')));
    expect(lower, isNot(contains('for me and')));
  });

  test('Kai greeting mode selection is social-context first', () {
    expect(
      KaiGreetingService.debugChooseMode(const Duration(minutes: 3), true),
      GreetingMode.quickReturn,
    );
    expect(
      KaiGreetingService.debugChooseMode(const Duration(hours: 4), true),
      GreetingMode.sameDayResume,
    );
    expect(
      KaiGreetingService.debugChooseMode(const Duration(hours: 30), true),
      GreetingMode.nextDayReturn,
    );
    expect(
      KaiGreetingService.debugChooseMode(const Duration(days: 5), true),
      GreetingMode.longGapReturn,
    );
    expect(
      KaiGreetingService.debugChooseMode(const Duration(hours: 30), false),
      GreetingMode.coldStart,
    );
  });

  test('Kai greeting filters garbage placeholder topics', () {
    for (final bad in ['ideas', 'answer', 'chat', 'conversation', 'stuff', 'things']) {
      expect(KaiGreetingService.debugUsableFocus(bad), isFalse, reason: bad);
    }

    expect(
      KaiGreetingService.debugUsableFocus('finishing the Kai Smarter Project layers'),
      isTrue,
    );
  });

  test('Kai greeting does not fabricate continuity from vague threads', () {
    expect(KaiGreetingService.debugThreadLine('ideas', const []), isEmpty);
    expect(KaiGreetingService.debugThreadLine('answer', const []), isEmpty);

    final useful = KaiGreetingService.debugThreadLine(
      'de-robotifying Kai greetings',
      const [],
    );
    expect(useful, isNotEmpty);
    expect(useful.toLowerCase(), contains('greeting'));
  });

  test('Kai greeting remembers last opener to avoid exact repeated openers', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kai_greeting.test-kai.opener', 'Hey');

    final line = await KaiGreetingService.build('test-kai');

    // Cold-start has several opener choices. The anti-repeat picker removes the
    // last opener when alternatives exist, so it should not start with stale text.
    expect(line, isNot(startsWith('Hey.')));
  });
}
