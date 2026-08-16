// Brief 015 — the ordering contract the desktop body must honour.
//
//     persist durably  →  render visibly  →  acknowledge Core
//
// Every failure between those steps must leave the record PENDING. A reminder
// that arrives late is a small annoyance; a reminder Core believes it delivered
// and nobody ever saw is a broken promise, and there is no way to notice it
// afterwards.
//
// The renderer here is a plain list standing in for the desktop's `_msgs`,
// exercising the same identity rule the shell uses (`recordId`, never text).
// The store is the REAL ConversationStoreService with its durable write
// swapped for an in-memory one, so persistence semantics — deterministic key,
// awaited write, thrown failure, buffer only after success — are the real ones.
//
// Nothing here touches live Firebase or the live Core directory.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/conversation_store_service.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_outbound_acceptance.dart';
import 'package:homecoming_app/services/core/kai_scheduled_commitment.dart';

final _createdAt = DateTime.utc(2026, 8, 8, 12);
final _dueAt = DateTime.utc(2026, 9, 1, 6);
final _afterDue = DateTime.utc(2026, 9, 1, 7);

const _persona = 'truekai';
const _surfaceId = 'in_person';
const _bodyId = 'desktop-body-1';
const _reminderText = 'chase the invoice';

class _Clock {
  DateTime now = _createdAt;
  DateTime call() => now;
}

/// The desktop's visible transcript, reduced to what matters for this contract.
class _FakeTranscript {
  final List<_Bubble> bubbles = [];

  /// True when this window is gone. A closed window cannot show a reminder,
  /// so it must not let one be acknowledged.
  bool mounted = true;

  /// Simulates a render that fails (layout error, disposed state, etc).
  bool rejectRender = false;

  bool contains(String recordId) =>
      bubbles.any((bubble) => bubble.recordId == recordId);

  void add(String recordId, String text, int timestampMillis) =>
      bubbles.add(_Bubble(recordId, text, timestampMillis));
}

class _Bubble {
  _Bubble(this.recordId, this.text, this.timestampMillis);

  final String? recordId;
  final String text;
  final int timestampMillis;
}

/// An in-memory stand-in for the conversation database.
class _FakeDatabase {
  final Map<String, Map<String, dynamic>> written = {};
  bool available = true;
  int writes = 0;

  /// Held open to suspend a write mid-flight, so another actor can act while
  /// the acceptance unit is awaiting.
  Completer<void>? gate;

  Future<void> write(String path, Map<String, dynamic> value) async {
    writes++;
    final held = gate;
    if (held != null) await held.future;
    if (!available) throw StateError('conversation_database_unavailable');
    written[path] = value;
  }

  /// Records as `watchHistory`/restore would hand them back, i.e. the raw
  /// child map keyed by child id — so identity has to survive the real parser.
  Map<String, dynamic> asRawTree() {
    final tree = <String, dynamic>{};
    written.forEach((path, value) {
      tree[path.split('/').last] = value;
    });
    return tree;
  }
}

/// The PRODUCTION acceptance unit, bound to the fake surface.
///
/// This is the same class the desktop shell constructs — not a copy of its
/// logic. That distinction is the whole point: the previous version of this
/// file re-implemented the shell's private method, so it could only ever prove
/// the copy agreed with itself, and a race present in both went unseen.
Future<bool> Function(Map<String, dynamic>) _acceptor(
  _FakeTranscript ui, {
  required ConversationStoreService store,
}) {
  final acceptance = KaiOutboundAcceptance(
    personaId: _persona,
    surfaceId: _surfaceId,
    store: store,
    isMounted: () => ui.mounted,
    isVisible: ui.contains,
    render: (line) {
      // A surface that refuses the paint leaves nothing visible, which is what
      // the acceptance unit checks — it does not take `render` on trust.
      if (ui.rejectRender) return;
      ui.add(line.recordId!, line.text, line.timestampMillis);
    },
    nowMillis: () => DateTime.now().millisecondsSinceEpoch,
  );
  return acceptance.accept;
}

class _Fixture {
  _Fixture(this.clock, this.server, this.client, this.db, this.ui, this.store);

  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient client;
  final _FakeDatabase db;
  final _FakeTranscript ui;
  final ConversationStoreService store;
}

Future<_Fixture> _fixture(String name) async {
  final directory = Directory.systemTemp.createTempSync('kai_accept_$name');
  final clock = _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  final client = KaiCoreClient(endpoint: server.endpoint!);

  final db = _FakeDatabase();
  final store = ConversationStoreService();
  store.resetSessionForTesting();
  ConversationStoreService.debugOutboundWriter = db.write;

  addTearDown(() async {
    ConversationStoreService.debugOutboundWriter = null;
    store.resetSessionForTesting();
    client.close();
    await server.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  return _Fixture(clock, server, client, db, _FakeTranscript(), store);
}

Future<void> _owe(
  _Fixture f, {
  required String id,
  String text = _reminderText,
  String bodyId = _bodyId,
}) async {
  f.clock.now = _createdAt;
  await f.client.createCommitment(
    commitmentId: id,
    personaId: _persona,
    text: text,
    dueAt: _dueAt,
    dueWallClock: '2026-09-01T09:00:00',
    dueWallOffsetMinutes: 180,
  );
  f.clock.now = _afterDue;
  await f.client.dispatchCommitment(
    id,
    outboundId: '$id-outbound',
    targetBodyId: bodyId,
    conversationId: _surfaceId,
  );
}

KaiCoreOutboundInbox _inbox(
    _Fixture f, Future<bool> Function(Map<String, dynamic>) accept) {
  final inbox = KaiCoreOutboundInbox(
    client: f.client,
    surface: 'desktop',
    bodyId: _bodyId,
    onOutbound: accept,
    interval: const Duration(milliseconds: 20),
  );
  addTearDown(inbox.stop);
  return inbox;
}

Future<List<Map<String, dynamic>>> _pending(_Fixture f) =>
    f.client.pendingOutbound(toSurface: 'desktop', bodyId: _bodyId);

void main() {
  test('the happy path: persisted once, rendered once, acknowledged once',
      () async {
    final f = await _fixture('happy');
    await _owe(f, id: 'commit-happy');

    await _inbox(f, _acceptor(f.ui, store: f.store)).poll();

    final recordId =
        KaiScheduledCommitment.transcriptKey('commit-happy-outbound');
    expect(f.db.written.keys.single,
        'conversations/$_persona/$_surfaceId/$recordId');
    expect(f.db.written.values.single['aiResponse'], _reminderText,
        reason: 'the exact stored text, unmodified');
    expect(f.db.written.values.single['userMessage'], '',
        reason: 'a reminder is assistant-only');
    expect(f.db.written.values.single['recordId'], recordId);

    expect(f.ui.bubbles.single.text, _reminderText);
    expect(f.ui.bubbles.single.recordId, recordId);
    expect(await _pending(f), isEmpty);
  });

  test('the deterministic key is the transcript key, never a push id',
      () async {
    final f = await _fixture('key');
    await _owe(f, id: 'commit-key');
    await _inbox(f, _acceptor(f.ui, store: f.store)).poll();

    final key = f.db.written.keys.single.split('/').last;
    expect(key, startsWith('commitment-'));
    expect(key, KaiScheduledCommitment.transcriptKey('commit-key-outbound'));
    expect(key, isNot(startsWith('-')),
        reason: 'a Firebase push id starts with "-"');
  });

  group('nothing is acknowledged that is not durable and visible', () {
    test('an unavailable database blocks acknowledgement and leaves no trace',
        () async {
      final f = await _fixture('db_down');
      await _owe(f, id: 'commit-down');
      f.db.available = false;

      await _inbox(f, _acceptor(f.ui, store: f.store)).poll();

      expect(f.db.written, isEmpty);
      expect(f.ui.bubbles, isEmpty);
      expect(await _pending(f), hasLength(1),
          reason: 'still owed — pending Core work IS the fallback');
      expect(await f.store.getHistory(_persona, surfaceId: _surfaceId), isEmpty,
          reason: 'a failed write must not appear durable in the buffer');

      // Recovery.
      f.db.available = true;
      await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
      expect(f.db.written, hasLength(1));
      expect(f.ui.bubbles, hasLength(1));
      expect(await _pending(f), isEmpty);
    });

    test('a render rejection after persistence leaves the record pending',
        () async {
      final f = await _fixture('render_reject');
      await _owe(f, id: 'commit-render');
      f.ui.rejectRender = true;

      await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
      expect(f.db.written, hasLength(1), reason: 'the write already landed');
      expect(f.ui.bubbles, isEmpty);
      expect(await _pending(f), hasLength(1));

      // Retry rewrites the SAME child and adds no second record.
      f.ui.rejectRender = false;
      await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
      expect(f.db.written, hasLength(1),
          reason: 'the deterministic key makes the rewrite idempotent');
      expect(f.ui.bubbles, hasLength(1));
      expect(await _pending(f), isEmpty);
    });

    test('an unmounted window never acknowledges', () async {
      final f = await _fixture('unmounted');
      await _owe(f, id: 'commit-unmounted');
      f.ui.mounted = false;

      await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
      expect(f.db.written, isEmpty);
      expect(await _pending(f), hasLength(1));
    });

    test(
        'an acknowledgement failure leaves it pending and adds nothing on '
        'retry', () async {
      final f = await _fixture('ack_fail');
      await _owe(f, id: 'commit-ackfail');

      // A client whose acknowledgement cannot land: the record is rendered,
      // then the ack throws inside the poller and is contained.
      final accept = _acceptor(f.ui, store: f.store);
      final broken = KaiCoreOutboundInbox(
        client: _UnacknowledgeableClient(f.client),
        surface: 'desktop',
        bodyId: _bodyId,
        onOutbound: accept,
        interval: const Duration(minutes: 1),
      );
      addTearDown(broken.stop);
      await broken.poll();

      expect(f.db.written, hasLength(1));
      expect(f.ui.bubbles, hasLength(1));
      expect(await _pending(f), hasLength(1),
          reason: 'Core never heard the acknowledgement');

      // The healthy retry must not draw a second bubble or write again.
      await _inbox(f, accept).poll();
      expect(f.db.written, hasLength(1));
      expect(f.ui.bubbles, hasLength(1));
      expect(await _pending(f), isEmpty);
    });
  });

  test(
      'the history watcher rendering during the durable write causes no '
      'second bubble', () async {
    // The interleaving the copied harness could not force:
    //
    //   visibility is false  →  write begins  →  the realtime watcher makes
    //   this exact recordId visible  →  write completes  →  acceptance resumes
    //
    // Deciding from the visibility read BEFORE the await renders a second
    // identical bubble for one reminder. The record is still durable and still
    // visible, so it may be acknowledged — the duplicate render is the bug,
    // not the acknowledgement.
    final f = await _fixture('watcher_race');
    await _owe(f, id: 'commit-race');

    final recordId =
        KaiScheduledCommitment.transcriptKey('commit-race-outbound');
    final gate = Completer<void>();
    f.db.gate = gate;

    final accept = _acceptor(f.ui, store: f.store);
    final pending = accept({
      'outboundId': 'commit-race-outbound',
      'text': _reminderText,
      'toSurface': 'desktop',
      'targetBodyId': _bodyId,
    });

    // Confirm we really are suspended inside the write before the watcher
    // acts, otherwise this test would pass without racing anything.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.db.writes, 1, reason: 'the write must be in flight by now');
    expect(f.ui.bubbles, isEmpty);

    // The realtime history watcher delivers the same record.
    f.ui.add(recordId, _reminderText, 1786200000000);

    gate.complete();
    f.db.gate = null;
    final accepted = await pending;

    expect(f.ui.bubbles, hasLength(1),
        reason: 'one reminder is one bubble, whoever rendered it first');
    expect(accepted, isTrue,
        reason: 'durable and visible — holding it pending would re-deliver it');
    expect(f.db.written, hasLength(1));
  });

  test(
      'a restart after persistence recognises the record and acknowledges '
      'without a second bubble', () async {
    final f = await _fixture('restart');
    await _owe(f, id: 'commit-restart');

    // First run persists but the window dies before it can acknowledge.
    f.ui.rejectRender = true;
    await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
    expect(f.db.written, hasLength(1));
    expect(await _pending(f), hasLength(1));

    // New process: an empty transcript, rehydrated from what was stored. The
    // identity must survive the real parser for this to work at all.
    final restored = _FakeTranscript();
    final lines = f.store.scopedLinesForTesting(f.db.asRawTree());
    expect(lines, hasLength(1));
    expect(lines.single.recordId,
        KaiScheduledCommitment.transcriptKey('commit-restart-outbound'),
        reason: 'restore must recover the record identity, not just the text');
    for (final line in lines) {
      restored.add(line.recordId!, line.text, line.timestampMillis);
    }

    await _inbox(f, _acceptor(restored, store: f.store)).poll();

    expect(restored.bubbles, hasLength(1),
        reason: 'already on screen; the retry must not add a duplicate');
    expect(f.db.writes, 1, reason: 'and must not write again');
    expect(await _pending(f), isEmpty);
  });

  test('two reminders with identical text stay two records and two turns',
      () async {
    final f = await _fixture('identical_text');
    await _owe(f, id: 'commit-twin-a');
    await _owe(f, id: 'commit-twin-b');

    await _inbox(f, _acceptor(f.ui, store: f.store)).poll();

    expect(f.db.written, hasLength(2),
        reason: 'same wording, two different promises');
    expect(f.ui.bubbles, hasLength(2));
    expect(f.ui.bubbles.map((b) => b.text).toSet(), {_reminderText});
    expect(f.ui.bubbles.map((b) => b.recordId).toSet(), hasLength(2));
    expect(await _pending(f), isEmpty);

    // And the parser keeps them apart on the way back out.
    final lines = f.store.scopedLinesForTesting(f.db.asRawTree());
    expect(lines, hasLength(2));
    expect(lines.map((line) => line.recordId).toSet(), hasLength(2));
  });

  test('a second delivery of the same reminder never doubles the transcript',
      () async {
    final f = await _fixture('idempotent');
    await _owe(f, id: 'commit-once');
    final accept = _acceptor(f.ui, store: f.store);

    await _inbox(f, accept).poll();
    // Feed the identical record straight back in, as a duplicate drain would.
    final replay = await accept({
      'outboundId': 'commit-once-outbound',
      'text': _reminderText,
      'toSurface': 'desktop',
      'targetBodyId': _bodyId,
    });

    expect(replay, isTrue, reason: 'already delivered — safe to acknowledge');
    expect(f.ui.bubbles, hasLength(1));
    expect(f.db.writes, 1);
  });

  test('the reminder text is passed through byte-for-byte', () async {
    const awkward = 'Ring  Ahmed\nabout the "gas line" — 2× before 9:00';
    final f = await _fixture('exact_text');
    await _owe(f, id: 'commit-exact', text: awkward);

    await _inbox(f, _acceptor(f.ui, store: f.store)).poll();
    expect(f.db.written.values.single['aiResponse'], awkward);
    expect(f.ui.bubbles.single.text, awkward);
  });

  group('session identity tracks recordId, not rendered text', () {
    test('a failed write adds neither a session line nor an identity claim',
        () async {
      final f = await _fixture('failed_write_identity');
      f.db.available = false;

      await expectLater(
        f.store.saveAssistantOutbound(
          personaId: _persona,
          surfaceId: _surfaceId,
          outboundId: 'outbound-doomed',
          exactText: _reminderText,
          timestampMillis: 1786200000000,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
          await f.store.getHistory(_persona, surfaceId: _surfaceId), isEmpty);

      // The identity must NOT have been claimed — otherwise the retry would be
      // suppressed as a duplicate and the reminder would never appear.
      f.db.available = true;
      await f.store.saveAssistantOutbound(
        personaId: _persona,
        surfaceId: _surfaceId,
        outboundId: 'outbound-doomed',
        exactText: _reminderText,
        timestampMillis: 1786200000000,
      );
      expect(await f.store.getHistory(_persona, surfaceId: _surfaceId),
          hasLength(1));
    });

    test('clearSession drops the identity claims with the lines', () async {
      final f = await _fixture('clear_identity');
      Future<void> save() => f.store.saveAssistantOutbound(
            personaId: _persona,
            surfaceId: _surfaceId,
            outboundId: 'outbound-kept',
            exactText: _reminderText,
            timestampMillis: 1786200000000,
          );

      await save();
      expect(await f.store.getHistory(_persona, surfaceId: _surfaceId),
          hasLength(1));

      f.store.clearSession(_persona, surfaceId: _surfaceId);

      // A stale identity here would suppress the line forever: the buffer is
      // empty, but the id would still say "already added".
      await save();
      expect(await f.store.getHistory(_persona, surfaceId: _surfaceId),
          hasLength(1));
    });

    test('identities are scoped per surface', () async {
      final f = await _fixture('identity_scope');
      for (final surface in ['in_person', 'messenger']) {
        await f.store.saveAssistantOutbound(
          personaId: _persona,
          surfaceId: surface,
          outboundId: 'outbound-shared',
          exactText: _reminderText,
          timestampMillis: 1786200000000,
        );
      }
      expect(await f.store.getHistory(_persona, surfaceId: 'in_person'),
          hasLength(1));
      expect(await f.store.getHistory(_persona, surfaceId: 'messenger'),
          hasLength(1),
          reason: 'one room must not consume another room\'s identity');
    });
  });

  test('ordinary saveTurn is untouched by any of this', () async {
    final f = await _fixture('save_turn');
    // saveTurn keeps its fire-and-forget contract and its own buffer path;
    // with no real Firebase it must still not throw.
    await f.store.saveTurn(
      personaId: _persona,
      surfaceId: _surfaceId,
      userMessage: 'morning',
      aiReply: 'morning — what are we on today?',
      personalityDeltas: const {},
    );
    final history = await f.store.getHistory(_persona, surfaceId: _surfaceId);
    expect(history.any((line) => line.contains('morning')), isTrue);
    expect(f.db.written, isEmpty,
        reason: 'the outbound writer seam must not capture ordinary turns');
  });
}

/// A client that reads normally but cannot acknowledge.
class _UnacknowledgeableClient implements KaiCoreClient {
  _UnacknowledgeableClient(this._inner);

  final KaiCoreClient _inner;

  @override
  Future<List<Map<String, dynamic>>> pendingOutbound({
    required String toSurface,
    required String bodyId,
  }) =>
      _inner.pendingOutbound(toSurface: toSurface, bodyId: bodyId);

  @override
  Future<Map<String, dynamic>> acknowledgeOutbound(
    String outboundId, {
    required String bodyId,
    required String surface,
  }) async =>
      throw const SocketException('core unreachable mid-acknowledgement');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
