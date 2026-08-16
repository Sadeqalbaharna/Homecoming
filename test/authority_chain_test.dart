// Every action traces back to a sentence Sadeq wrote.
//
//   Omnipresent in what he sees. Free to speak. Acts only on authority that
//   traces back to you — deferred is fine, invented is not.
//
// The rule that makes it possible to hand a system real bank credentials is not
// "it is clever enough". It is that every single thing it did answers to a
// sentence you typed, and you can pull the thread.
//
// These tests are the enforcement. Before this, nothing in the tree recorded
// what authorised an action — the principle was true only because someone was
// watching.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/authority_chain.dart';

final t0 = DateTime.utc(2026, 8, 16, 9);

AuthorityLedger ledgerWithRoot({
  String id = 'root',
  String text = 'move 200 to savings',
  Set<String> scope = const <String>{},
  DateTime? expiresAt,
  int? maxActions,
}) {
  final l = AuthorityLedger();
  l.grantFromHuman(
    id: id,
    originText: text,
    at: t0,
    scope: scope,
    expiresAt: expiresAt,
    maxActions: maxActions,
  );
  return l;
}

void main() {
  group('only a human can start a chain', () {
    test('a root quotes what was actually said', () {
      final l = ledgerWithRoot(text: 'pay the electricity bill');
      expect(l.originTextFor('root'), 'pay the electricity bill');
    });

    test('an empty sentence is not authority', () {
      // The mechanism, not the documentation: there is no way to mint a root
      // without producing text claimed to be human, and that claim is
      // inspectable afterwards.
      expect(
        () => AuthorityLedger()
            .grantFromHuman(id: 'x', originText: '   ', at: t0),
        throwsArgumentError,
      );
    });

    test('an unknown authority refuses — there is no assume-fine path', () {
      final l = AuthorityLedger();
      final d = l.check(authorityId: 'invented', action: 'send_money', now: t0);
      expect(d.allowed, isFalse);
      expect(d.refusal, AuthorityRefusal.unknownAuthority);
    });

    test('a derived grant with no reachable root is refused', () {
      // This is the exact shape an invented authority would have: it looks like
      // a link in a chain and the chain never arrives at a sentence.
      final l = AuthorityLedger();
      l.derive(id: 'orphan', parentId: 'nothing', at: t0);
      final d = l.check(authorityId: 'orphan', action: 'send_money', now: t0);
      expect(d.allowed, isFalse);
      expect(d.refusal, AuthorityRefusal.parentRefused);
    });

    test('a cycle cannot reach a sentence, so it is not authority', () {
      final l = AuthorityLedger();
      l.derive(id: 'a', parentId: 'b', at: t0);
      l.derive(id: 'b', parentId: 'a', at: t0);
      expect(l.check(authorityId: 'a', action: 'x', now: t0).allowed, isFalse);
    });
  });

  group('deferred is fine, invented is not', () {
    test('a reminder firing hours later is still authorised', () {
      // "remind me at five" is the sentence. It fires at five with nobody
      // there. Under a literal no-action-without-a-prompt rule the whole
      // commitment ledger would be illegal; it is deferred, not invented.
      final l = ledgerWithRoot(text: 'remind me at five to call the landlord');
      l.defer(id: 'reminder', parentId: 'root', at: t0);
      final firing = t0.add(const Duration(hours: 8));
      final d =
          l.check(authorityId: 'reminder', action: 'notify', now: firing);
      expect(d.allowed, isTrue);
      expect(d.rootId, 'root');
      expect(l.originTextFor('reminder'),
          'remind me at five to call the landlord');
    });

    test('a sub-action inherits its parent, and the receipt still quotes you',
        () {
      final l = ledgerWithRoot(text: 'sort out my finances this month');
      l.derive(id: 'step1', parentId: 'root', at: t0);
      l.derive(id: 'step1a', parentId: 'step1', at: t0);
      final d = l.check(authorityId: 'step1a', action: 'write_ledger', now: t0);
      expect(d.allowed, isTrue);
      expect(d.rootId, 'root');
      expect(l.originTextFor('step1a'), 'sort out my finances this month');
    });
  });

  group('scope narrows going down and never widens', () {
    test('a child cannot add what its parent withheld', () {
      final l = ledgerWithRoot(scope: {'read_balance'});
      l.derive(id: 'child', parentId: 'root', at: t0, scope: {'send_money'});
      // The child asks for send_money; the root never permitted it. The
      // intersection is empty and the action is refused.
      expect(
        l.check(authorityId: 'child', action: 'send_money', now: t0).refusal,
        AuthorityRefusal.notInScope,
      );
    });

    test('a child may restrict further', () {
      final l = ledgerWithRoot(scope: {'read_balance', 'send_money'});
      l.derive(id: 'child', parentId: 'root', at: t0, scope: {'read_balance'});
      expect(l.check(authorityId: 'child', action: 'read_balance', now: t0).allowed,
          isTrue);
      expect(l.check(authorityId: 'child', action: 'send_money', now: t0).allowed,
          isFalse);
    });

    test('an unscoped root means a direct instruction — anything goes', () {
      final l = ledgerWithRoot();
      expect(l.check(authorityId: 'root', action: 'anything', now: t0).allowed,
          isTrue);
    });
  });

  group('revocation cascades, which is why breadth is safe to grant', () {
    test('killing a root stops everything descended from it', () {
      final l = ledgerWithRoot();
      l.defer(id: 'later', parentId: 'root', at: t0);
      l.derive(id: 'deep', parentId: 'later', at: t0);
      expect(l.check(authorityId: 'deep', action: 'x', now: t0).allowed, isTrue);

      l.revoke('root');
      expect(l.check(authorityId: 'deep', action: 'x', now: t0).allowed, isFalse,
          reason: 'a descendant of a dead authority is dead');
      expect(l.check(authorityId: 'root', action: 'x', now: t0).refusal,
          AuthorityRefusal.revoked);
    });

    test('revoking a branch leaves its siblings alone', () {
      final l = ledgerWithRoot();
      l.derive(id: 'a', parentId: 'root', at: t0);
      l.derive(id: 'b', parentId: 'root', at: t0);
      l.revoke('a');
      expect(l.check(authorityId: 'a', action: 'x', now: t0).allowed, isFalse);
      expect(l.check(authorityId: 'b', action: 'x', now: t0).allowed, isTrue);
    });
  });

  group('expiry and blast radius', () {
    test('an expired grant stops working', () {
      final l = ledgerWithRoot(expiresAt: t0.add(const Duration(hours: 1)));
      expect(l.check(authorityId: 'root', action: 'x', now: t0).allowed, isTrue);
      expect(
        l.check(
          authorityId: 'root',
          action: 'x',
          now: t0.add(const Duration(hours: 2)),
        ).refusal,
        AuthorityRefusal.expired,
      );
    });

    test('a budget on the root cannot be dodged by deriving', () {
      // "sort out my finances" is one sentence and fifty writes. Charging the
      // whole chain is what stops a child spending a parent's allowance twice.
      final l = ledgerWithRoot(maxActions: 2);
      l.derive(id: 'child', parentId: 'root', at: t0);
      l.recordSpend('child');
      l.recordSpend('child');
      expect(l.spent('root'), 2, reason: 'the root paid for both');
      expect(l.check(authorityId: 'child', action: 'x', now: t0).refusal,
          AuthorityRefusal.parentRefused);
      expect(l.check(authorityId: 'root', action: 'x', now: t0).refusal,
          AuthorityRefusal.exhausted);
    });
  });

  group('the receipt answers the question people actually ask', () {
    test('why did you move that money returns the sentence, not a paraphrase',
        () {
      final l = ledgerWithRoot(text: 'move 200 to savings on payday');
      l.defer(id: 'payday', parentId: 'root', at: t0);
      final d = l.check(
        authorityId: 'payday',
        action: 'send_money',
        now: t0.add(const Duration(days: 12)),
      );
      expect(d.allowed, isTrue);
      expect(l.originTextFor(d.rootId!), 'move 200 to savings on payday');
    });

    test('a refusal names its reason without inventing one', () {
      final l = AuthorityLedger();
      expect(
        l.check(authorityId: 'nope', action: 'x', now: t0).reasonCode,
        'unknownAuthority',
      );
    });
  });
}
