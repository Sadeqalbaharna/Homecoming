// test/tool_policy_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_policy_service.dart';

void main() {
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
