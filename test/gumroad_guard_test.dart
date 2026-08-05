// Tests for gumroad_guard.dart — the storefront command boundary.
//
// This is the file that decides whether Kai can refund a customer. The tests
// that matter most are the DENIALS, and the one asserting that an approval
// does not widen the boundary — approval opens exactly one door (publish), and
// nothing else, ever.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/gumroad_guard.dart';

void main() {
  group('money and customer harm are unreachable', () {
    const forbidden = [
      ['sales', 'refund', 'abc123'],
      ['payouts', 'list'],
      ['payouts', 'upcoming'],
      ['licenses', 'disable', 'key'],
      ['licenses', 'rotate', 'key'],
      ['auth', 'login'],
      ['auth', 'logout'],
      ['products', 'delete', 'x'],
      ['offer-codes', 'create'],
      ['webhooks', 'create'],
      ['subscribers', 'list'],
      ['sales', 'resend-receipt', 'x'],
      ['sales', 'ship', 'x'],
    ];

    for (final cmd in forbidden) {
      test('denied: ${cmd.join(' ')}', () {
        expect(guardGumroad(cmd).verdict, GuardVerdict.denied);
      });
    }

    test('approval does NOT unlock refunds or payouts', () {
      expect(guardGumroad(['sales', 'refund', 'x'], hasApproval: true).verdict,
          GuardVerdict.denied);
      expect(guardGumroad(['payouts', 'list'], hasApproval: true).verdict,
          GuardVerdict.denied);
    });
  });

  group('safe work proceeds', () {
    const allowed = [
      ['user'],
      ['products', 'list'],
      ['products', 'create', '--name', 'Kit'],
      ['products', 'update', 'x'],
      ['files', 'upload', 'kit.zip'],
      ['sales', 'list', '--all'],
    ];

    for (final cmd in allowed) {
      test('allowed: ${cmd.join(' ')}', () {
        expect(guardGumroad(cmd).isAllowed, isTrue);
      });
    }

    test('unpublish is free — he may always STOP selling', () {
      expect(guardGumroad(['products', 'unpublish', 'x']).isAllowed, isTrue);
    });
  });

  group('publish is the gate', () {
    test('refused without approval, with an honest reason', () {
      final d = guardGumroad(['products', 'publish', 'x']);
      expect(d.verdict, GuardVerdict.requiresApproval);
      expect(d.reason, contains('his to authorise'));
    });

    test('allowed with approval', () {
      expect(guardGumroad(['products', 'publish', 'x'], hasApproval: true).isAllowed,
          isTrue);
    });
  });

  group('newly discovered command families are already blocked', () {
    // None of these appear in the README. They were found by reading the
    // installed binary's own command list. They were unreachable before anyone
    // knew they existed — which is the entire case for default-deny.
    const surprises = [
      ['admin', 'payouts', 'issue'],
      ['admin', 'users', 'credits', 'add'],
      ['admin', 'users', 'suspend'],
      ['admin', 'users', 'two-factor-disable'],
      ['admin', 'users', 'reset-password'],
      ['admin', 'purchases', 'refund-for-fraud'],
      ['emails', 'send'],
      ['pages', 'publish'],
      ['products', 'page', 'publish'], // a SECOND publish path
      ['user', 'page', 'publish'], // and a third
      ['sales', 'export'],
      ['sales', 'buyers'],
      ['refund-policy', 'set'],
      ['upsells', 'create'],
    ];

    for (final cmd in surprises) {
      test('denied: ${cmd.join(' ')}', () {
        expect(guardGumroad(cmd).verdict, GuardVerdict.denied);
      });
    }

    test('the extra publish paths are denied even WITH approval', () {
      // Approval unlocks exactly `products publish` — not every route to live.
      expect(
        guardGumroad(['products', 'page', 'publish'], hasApproval: true).verdict,
        GuardVerdict.denied,
      );
      expect(
        guardGumroad(['user', 'page', 'publish'], hasApproval: true).verdict,
        GuardVerdict.denied,
      );
    });
  });

  group('depth limit — the hole a test actually caught', () {
    // `gumroad user` is allowlisted (it prints account info). Under plain
    // prefix matching, `user page publish` also matched it and was ALLOWED —
    // a live publish path, in the guard written to close publish paths. The
    // "default-deny covers it" claim was wrong: default-deny never ran,
    // because the allowlist matched first. A command may carry an ARGUMENT;
    // it may not carry a SUBCOMMAND.
    test('an allowed command cannot be extended into a subcommand', () {
      expect(guardGumroad(['user', 'page', 'publish']).verdict,
          GuardVerdict.denied);
      expect(guardGumroad(['user', 'billing', 'transfer']).verdict,
          GuardVerdict.denied);
    });

    test('and approval does not rescue it', () {
      expect(
        guardGumroad(['user', 'page', 'publish'], hasApproval: true).verdict,
        GuardVerdict.denied,
      );
    });

    test('legitimate positional arguments still work', () {
      expect(guardGumroad(['user']).isAllowed, isTrue);
      expect(guardGumroad(['products', 'view', 'abc123']).isAllowed, isTrue);
      expect(guardGumroad(['files', 'upload', 'kit.zip']).isAllowed, isTrue);
      expect(guardGumroad(['products', 'list', '--all', '--json']).isAllowed,
          isTrue);
      expect(guardGumroad(['products', 'publish', 'x']).verdict,
          GuardVerdict.requiresApproval);
    });
  });

  group('forbidden flags', () {
    test('--yes is blocked even on an allowed command', () {
      final d = guardGumroad(['products', 'list', '--yes']);
      expect(d.verdict, GuardVerdict.denied);
      expect(d.reason, contains('safety net'));
    });

    test('-y is blocked too', () {
      expect(guardGumroad(['products', 'create', '-y']).verdict,
          GuardVerdict.denied);
    });

    test('--yes is blocked even with approval', () {
      expect(
        guardGumroad(['products', 'publish', 'x', '--yes'], hasApproval: true)
            .verdict,
        GuardVerdict.denied,
      );
    });
  });

  group('default deny', () {
    test('a command that does not exist yet is refused', () {
      expect(guardGumroad(['crypto', 'withdraw', 'all']).verdict,
          GuardVerdict.denied);
    });

    test('empty and flag-only input refused', () {
      expect(guardGumroad([]).verdict, GuardVerdict.denied);
      expect(guardGumroad(['   ', '\t']).verdict, GuardVerdict.denied);
      expect(guardGumroad(['--json']).verdict, GuardVerdict.denied);
    });
  });

  group('shell metacharacters in the command path', () {
    // Inert today (args go to Process.run as a list), rejected anyway so this
    // boundary does not depend on how the caller executes it.
    const attempts = [
      ['user', '&&', 'gumroad', 'payouts', 'list'],
      ['user;', 'payouts'],
      ['user|cat'],
      ['products', '`whoami`'],
      ['products', r'$(id)'],
      ['user', '>', '/tmp/x'],
    ];

    for (final cmd in attempts) {
      test('denied: ${cmd.join(' ')}', () {
        expect(guardGumroad(cmd).verdict, GuardVerdict.denied);
      });
    }

    test('legitimate values are NOT punished for their contents', () {
      // Only the command path is scanned; everything after a flag is data.
      expect(
        guardGumroad(['products', 'create', '--name', 'Refund Policy Template'])
            .isAllowed,
        isTrue,
      );
      expect(
        guardGumroad(['products', 'create', '--name', 'Kit', '--price', r'$49'])
            .isAllowed,
        isTrue,
      );
    });
  });
}
