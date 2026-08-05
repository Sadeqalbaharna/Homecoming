// Tests for command_guard.dart
//
// These lean deliberately toward the DENIALS. Anyone can write a guard that
// permits the happy path; the value is entirely in what it refuses — and a
// security boundary that isn't tested exhaustively isn't one to trust.

import 'package:test/test.dart';
import '../lib/command_guard.dart';

void main() {
  // A representative policy: read and draft operations are free, one
  // consequential action is gated, everything else is unlisted.
  const policy = CommandPolicy(
    allowed: [
      ['user'],
      ['products', 'list'],
      ['products', 'view'],
      ['products', 'create'],
      ['products', 'update'],
      ['products', 'unpublish'],
      ['files', 'upload'],
      ['sales', 'list'],
    ],
    requiresApproval: [
      ['products', 'publish'],
    ],
    dangerNotes: {
      'refund': 'moves money back to a customer',
      'admin': 'account administration',
      'delete': 'destructive and irreversible',
    },
  );

  group('default deny', () {
    const unlisted = [
      ['sales', 'refund', 'abc'],
      ['payouts', 'list'],
      ['licenses', 'disable', 'key'],
      ['auth', 'login'],
      ['products', 'delete', 'x'],
      ['admin', 'users', 'suspend'],
      ['emails', 'send'],
      ['webhooks', 'create'],
      ['subscribers', 'list'],
    ];

    for (final cmd in unlisted) {
      test('denied: ${cmd.join(' ')}', () {
        expect(guardCommand(cmd, policy).verdict, GuardVerdict.denied);
      });
    }

    test('a command invented tomorrow is denied today', () {
      expect(guardCommand(['quantum', 'transfer', 'all'], policy).verdict,
          GuardVerdict.denied);
    });

    test('empty and flags-only input denied', () {
      expect(guardCommand([], policy).verdict, GuardVerdict.denied);
      expect(guardCommand(['  ', '\t'], policy).verdict, GuardVerdict.denied);
      expect(guardCommand(['--json'], policy).verdict, GuardVerdict.denied);
    });
  });

  group('approval does not widen the boundary', () {
    test('approval unlocks exactly the gated command', () {
      expect(guardCommand(['products', 'publish', 'x'], policy).verdict,
          GuardVerdict.requiresApproval);
      expect(
          guardCommand(['products', 'publish', 'x'], policy, hasApproval: true)
              .isAllowed,
          isTrue);
    });

    test('approval never unlocks an unlisted command', () {
      expect(
          guardCommand(['sales', 'refund', 'x'], policy, hasApproval: true)
              .verdict,
          GuardVerdict.denied);
      expect(
          guardCommand(['admin', 'users', 'suspend'], policy, hasApproval: true)
              .verdict,
          GuardVerdict.denied);
    });
  });

  group('command versus data', () {
    test('a dangerous word in a VALUE does not block honest work', () {
      expect(
        guardCommand(
          ['products', 'create', '--name', 'Refund Policy Template'],
          policy,
        ).isAllowed,
        isTrue,
      );
    });

    test('the same word as a COMMAND is refused', () {
      expect(guardCommand(['sales', 'refund'], policy).verdict,
          GuardVerdict.denied);
    });

    test('values containing shell characters are still data', () {
      expect(
        guardCommand(['products', 'create', '--price', r'$49'], policy)
            .isAllowed,
        isTrue,
      );
    });
  });

  group('shell metacharacters in the command path', () {
    const attempts = [
      ['user', '&&', 'payouts', 'list'],
      ['user;', 'payouts'],
      ['user|cat'],
      ['products', '`whoami`'],
      ['user', '>', '/tmp/out'],
    ];

    for (final cmd in attempts) {
      test('denied: ${cmd.join(' ')}', () {
        expect(guardCommand(cmd, policy).verdict, GuardVerdict.denied);
      });
    }
  });

  group('elevation flags', () {
    test('--yes is blocked even on an allowed command', () {
      expect(guardCommand(['products', 'list', '--yes'], policy).verdict,
          GuardVerdict.denied);
    });

    test('--force and -y are blocked', () {
      expect(guardCommand(['products', 'update', '--force'], policy).verdict,
          GuardVerdict.denied);
      expect(guardCommand(['products', 'create', '-y'], policy).verdict,
          GuardVerdict.denied);
    });

    test('--yes is blocked even with approval', () {
      expect(
        guardCommand(['products', 'publish', 'x', '--yes'], policy,
                hasApproval: true)
            .verdict,
        GuardVerdict.denied,
      );
    });
  });

  group('allowed work proceeds', () {
    const fine = [
      ['user'],
      ['products', 'list', '--all'],
      ['products', 'create', '--name', 'Kit'],
      ['files', 'upload', 'bundle.zip'],
      ['sales', 'list', '--json'],
      ['products', 'unpublish', 'x'],
    ];

    for (final cmd in fine) {
      test('allowed: ${cmd.join(' ')}', () {
        expect(guardCommand(cmd, policy).isAllowed, isTrue);
      });
    }
  });

  group('determinism', () {
    test('same input always yields the same verdict', () {
      final verdicts = List.generate(
          50, (_) => guardCommand(['sales', 'refund', 'x'], policy).verdict);
      expect(verdicts.toSet().length, 1);
    });
  });
}
