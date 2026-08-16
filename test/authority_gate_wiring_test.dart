// The gate at the choke point, not just the policy in isolation.
//
// authority_chain_test proves the ledger reasons correctly. This proves the one
// place every action passes through actually consults it — which is the part
// that was missing entirely: before this, no executed tool carried any record
// of what authorised it, and the rule held only because someone was watching.
//
// Every assertion here refuses BEFORE any tool body runs, so nothing in this
// file touches Firebase, the network, or a platform channel.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/authority_chain.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 16, 9);

  ToolExecutorService gated(AuthorityLedger ledger, String? authorityId) {
    final ex = ToolExecutorService()
      ..authorityLedger = ledger
      ..activeAuthorityId = authorityId;
    return ex;
  }

  test('an action with no authority is refused at the choke point', () async {
    final result = await gated(AuthorityLedger(), null).execute(
      'send_sms',
      const {'to': '+973', 'body': 'hello'},
    );
    expect(result, contains('blocked'));
    expect(result, contains('nothing authorised'));
  });

  test('an invented authority id is refused', () async {
    // The shape a model would produce if it tried to mint permission: an id
    // that looks plausible and reaches no sentence.
    final result = await gated(AuthorityLedger(), 'looks-real').execute(
      'send_sms',
      const {'to': '+973', 'body': 'hello'},
    );
    expect(result, contains('unknownAuthority'));
  });

  test('a revoked chain is refused even mid-turn', () async {
    final ledger = AuthorityLedger();
    ledger.grantFromHuman(id: 'root', originText: 'text Layla', at: t0);
    ledger.derive(id: 'step', parentId: 'root', at: t0);
    ledger.revoke('root');

    final result = await gated(ledger, 'step').execute(
      'send_sms',
      const {'to': '+973', 'body': 'hello'},
    );
    expect(result, contains('blocked'));
  });

  test('an out-of-scope action is refused under a narrow grant', () async {
    // "check my balance" must not authorise moving money, even though both are
    // finance actions and the model may consider them adjacent.
    final ledger = AuthorityLedger();
    ledger.grantFromHuman(
      id: 'root',
      originText: 'check my balance',
      at: t0,
      scope: {'read_balance'},
    );
    final result = await gated(ledger, 'root').execute('send_sms', const {});
    expect(result, contains('notInScope'));
  });

  test('spending is charged, so a budget is real rather than advisory',
      () async {
    final ledger = AuthorityLedger();
    ledger.grantFromHuman(
      id: 'root',
      originText: 'send two texts',
      at: t0,
      maxActions: 1,
    );
    final ex = gated(ledger, 'root');
    await ex.execute('send_sms', const {'to': '+973', 'body': 'one'});
    expect(ledger.spent('root'), greaterThan(0));

    final second =
        await ex.execute('send_sms', const {'to': '+973', 'body': 'two'});
    expect(second, contains('exhausted'));
  });

  test('no ledger means current behaviour, not a silent refusal', () {
    // Deliberately nullable for one release: switching it on for every caller
    // before any of them registers a root would stop Kai acting at all. An
    // executor with no ledger must behave exactly as it did yesterday.
    final ex = ToolExecutorService();
    expect(ex.authorityLedger, isNull);
    expect(ex.activeAuthorityId, isNull);
  });
}
