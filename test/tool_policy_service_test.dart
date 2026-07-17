// test/tool_policy_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_policy_service.dart';

void main() {
  // Deleting code was structurally impossible and nobody noticed, because
  // nothing had asked him to delete anything until it did.
  //
  // The validator treated any empty string as a missing argument. But
  // new_string: "" IS the delete. He tried to cut a dead 200-line widget, got
  // "Missing required argument(s): new_string", tried whitespace instead, got
  // told off again — "It rejected whitespace too. Good, whatever" — and settled
  // for replacing the fossil with a comment. That comment is in the file now.
  // He did the right work and the gate made him leave litter.
  group('an empty argument is not always a missing one', () {
    test('edit_file accepts new_string: "" — that is how you delete', () {
      final r = ToolPolicyService.validate('edit_file', const {
        'path': 'lib/main.dart',
        'old_string': 'void dead() {}',
        'new_string': '',
      });
      expect(r.ok, isTrue, reason: r.message);
    });

    test('…and whitespace-only, which is the same intent', () {
      final r = ToolPolicyService.validate('edit_file', const {
        'path': 'lib/main.dart',
        'old_string': 'void dead() {}',
        'new_string': '\n',
      });
      expect(r.ok, isTrue, reason: r.message);
    });

    test('but path is still strict', () {
      final r = ToolPolicyService.validate('edit_file', const {
        'path': '',
        'old_string': 'x',
        'new_string': 'y',
      });
      expect(r.ok, isFalse);
    });

    test('new_string missing entirely is still missing', () {
      // emptyOkArgs relaxes EMPTY, not ABSENT. A call with no new_string at all
      // is malformed and should say so.
      final r = ToolPolicyService.validate('edit_file', const {
        'path': 'lib/main.dart',
        'old_string': 'x',
      });
      expect(r.ok, isFalse);
      expect(r.message, contains('new_string'));
    });

    test('old_string is no longer required — range mode exists now', () {
      // The whole point of start_line/end_line is that he does NOT have to
      // paste the thing he is deleting. If the policy still demanded
      // old_string, range mode would be blocked before it ever ran.
      final r = ToolPolicyService.validate('edit_file', const {
        'path': 'lib/main.dart',
        'start_line': 1760,
        'end_line': 1911,
        'new_string': '',
      });
      expect(r.ok, isTrue, reason: r.message);
    });
  });

  group('ToolPolicyService', () {
    test('phone-body action is blocked from desktop before execution', () {
      final result = ToolPolicyService.validate('send_whatsapp', {
        'contact': 'Ahmed',
        'message': 'Running ten minutes late',
      });

      expect(result.ok, isFalse);
      expect(result.message, contains("phone body"));
    });

    test('desktop coding action requires its declared arguments', () {
      final missing = ToolPolicyService.validate('read_file', const {});

      expect(missing.ok, isFalse);
      expect(missing.message, contains('Missing required argument'));
      expect(missing.message, contains('path'));

      final complete = ToolPolicyService.validate('read_file', {
        'path': 'lib/main.dart',
      });

      expect(complete.ok, isTrue);
      expect(complete.message, isNull);
    });

    test('parallel safety rejects null, unknown, data-returning, and destructive tools', () {
      expect(ToolPolicyService.isParallelSafe(null), isFalse);
      expect(ToolPolicyService.isParallelSafe(''), isFalse);
      expect(ToolPolicyService.isParallelSafe('totally_fake_tool'), isFalse);
      expect(ToolPolicyService.isParallelSafe('read_file'), isFalse);
      expect(ToolPolicyService.isParallelSafe('control_device'), isTrue);
      expect(ToolPolicyService.isParallelSafe('run_command'), isFalse);
    });

    test('destructive tools keep approval/risk metadata', () {
      final policy = ToolPolicyService.policyFor('run_command');

      expect(policy, isNotNull);
      expect(policy!.risk, ToolRisk.destructive);
      expect(policy.needsUserApproval, isTrue);
      expect(policy.requiredArgs, contains('command'));
    });

    test('open_terminal is a desktop coding side effect without arguments', () {
      final policy = ToolPolicyService.policyFor('open_terminal');

      expect(policy, isNotNull);
      expect(policy!.risk, ToolRisk.sideEffect);
      expect(policy.capabilities, contains(ToolCapability.coding));
      expect(policy.requiredArgs, isEmpty);

      final result = ToolPolicyService.validate('open_terminal', const {});
      expect(result.ok, isTrue);
    });
  });
}
