// Tests for frozen_paths.dart — the files Kai may not edit.
//
// This guard exists because of one instruction: "improve on his own methods on
// his own until he hits results." Given a metric and the ability to reach the
// scoreboard, the fastest route to results is editing the scoreboard. These
// tests are the proof that route is closed.
//
// Note this file is ITSELF frozen. If it could be edited, weakening a rule and
// silencing the alarm would be one motion.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/frozen_paths.dart';

void main() {
  group('the measurement is frozen', () {
    const measurement = [
      'lib/logic/product_scout.dart',
      'lib/logic/product_factory.dart',
      'lib/logic/scout_calibration.dart',
      'lib/logic/gumroad_guard.dart',
      'lib/services/core/gumroad_cli_service.dart',
      'lib/services/core/kai_factory_service.dart',
    ];

    for (final p in measurement) {
      test('frozen: $p', () => expect(isFrozen(p), isTrue));
    }
  });

  group('the tests are frozen too', () {
    // Freezing rules without freezing their tests is theatre — the tests are
    // the only thing that notices when a rule stops being true.
    const proofs = [
      'test/product_scout_test.dart',
      'test/product_factory_test.dart',
      'test/scout_calibration_test.dart',
      'test/gumroad_guard_test.dart',
    ];

    for (final p in proofs) {
      test('frozen: $p', () => expect(isFrozen(p), isTrue));
    }
  });

  group('self-protection', () {
    test('the guard freezes its own source', () {
      expect(isFrozen('lib/logic/frozen_paths.dart'), isTrue);
    });

    test('and its own test', () {
      expect(isFrozen('test/frozen_paths_test.dart'), isTrue);
    });
  });

  group('evasion', () {
    test('windows separators', () {
      expect(isFrozen(r'lib\logic\product_scout.dart'), isTrue);
    });

    test('absolute paths, either platform', () {
      expect(
          isFrozen(r'C:\code\homecoming_app\lib\logic\product_scout.dart'), isTrue);
      expect(isFrozen('/home/x/app/lib/logic/product_scout.dart'), isTrue);
    });

    test('case differences', () {
      expect(isFrozen('LIB/Logic/Product_Scout.DART'), isTrue);
    });

    test('dot and parent segments that walk out and back in', () {
      expect(isFrozen('lib/./logic/product_scout.dart'), isTrue);
      expect(isFrozen('lib/logic/../logic/product_scout.dart'), isTrue);
      expect(isFrozen('lib/services/../../lib/logic/gumroad_guard.dart'), isTrue);
      expect(isFrozen('./lib/logic/product_scout.dart'), isTrue);
    });

    test('redundant slashes', () {
      expect(isFrozen('lib//logic///product_scout.dart'), isTrue);
    });
  });

  group('default is ALLOW — he still owns his codebase', () {
    // The opposite posture to the storefront guard, on purpose. There he needed
    // a narrow set of permitted actions; here he must be able to edit nearly
    // everything, so the frozen list has to stay short enough to be honest.
    const editable = [
      'lib/services/ai/ai_service.dart',
      'lib/screens/kai_desktop_shell.dart',
      'lib/logic/noticing.dart',
      'lib/widgets/kai_activity_gears.dart',
      'test/memory_filters_test.dart',
      'lib/services/core/kai_job_service.dart',
    ];

    for (final p in editable) {
      test('editable: $p', () => expect(isFrozen(p), isFalse));
    }

    test('similar names are not frozen by accident', () {
      expect(isFrozen('lib/logic/product_scout_helper.dart'), isFalse);
      expect(isFrozen('lib/other/product_scout.dart'), isFalse);
    });
  });

  group('the refusal explains itself', () {
    test('a frozen decision carries a readable reason', () {
      final d = guardEdit('lib/logic/product_scout.dart');
      expect(d.allowed, isFalse);
      expect(d.rule, isNotNull);
      expect(d.message, contains('FROZEN'));
      expect(d.message, contains('Sadeq'));
      // It must not read as an arbitrary wall — he should know WHY, so the
      // correct response is to argue the case rather than route around it.
      expect(d.message.toLowerCase(), contains('measured'));
    });
  });
}
