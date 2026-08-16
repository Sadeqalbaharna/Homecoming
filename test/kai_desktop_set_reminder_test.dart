// Brief 017 — `set_reminder` on the desktop workbench creates a Core promise.
//
// Everything here runs the PRODUCTION path: the real ToolExecutorService.execute
// switch, the real KaiDesktopReminderTool, the real KaiCoreClient, against a
// real KaiCoreServer in a temp directory. Nothing re-implements the wall-clock
// conversion or the deterministic id — a test that recomputed those would only
// prove the copy agrees with the copy.
//
// The MethodChannel is mocked purely to OBSERVE it: the desktop path must never
// reach it, and the Android path must reach it with the argument map untouched.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_capability_broker.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_desktop_reminder_tool.dart';
import 'package:homecoming_app/services/core/kai_scheduled_commitment.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

const _channel = MethodChannel('com.homecoming.app/kai_tools');

/// Bahrain 2026-09-01 09:00 → 06:00Z.
const _year = 2026;
const _month = 9;
const _day = 1;
const _hour = 9;
const _minute = 0;
final _expectedUtc = DateTime.utc(2026, 9, 1, 6);
const _expectedWall = '2026-09-01T09:00:00';

const _text = 'chase the Gulf Air invoice';

class _Clock {
  DateTime now = DateTime.utc(2026, 8, 8, 12);
  DateTime call() => now;
}

/// Every MethodChannel call this test saw. Desktop must add nothing to it.
final List<MethodCall> _channelCalls = [];

class _Fixture {
  _Fixture(this.clock, this.server, this.client);

  final _Clock clock;
  final KaiCoreServer server;
  final KaiCoreClient client;

  Future<List<Map<String, dynamic>>> commitments() => client.commitments();
}

Future<_Fixture> _fixture(String name, {KaiCoreClient? override}) async {
  final directory = Directory.systemTemp.createTempSync('kai_reminder_$name');
  final clock = _Clock();
  final server =
      KaiCoreServer(dataDirectory: directory, port: 0, clock: clock.call);
  await server.start();
  final real = KaiCoreClient(endpoint: server.endpoint!);

  ToolExecutorService.debugIsDesktopPlatform = true;
  ToolExecutorService.debugDesktopReminderTool = KaiDesktopReminderTool(
    client: override ?? real,
    now: clock.call,
  );

  addTearDown(() async {
    ToolExecutorService.resetDesktopReminderSeamForTesting();
    real.close();
    override?.close();
    await server.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return _Fixture(clock, server, real);
}

Map<String, dynamic> _args({
  Object? message = _text,
  Object? year = _year,
  Object? month = _month,
  Object? day = _day,
  Object? hour = _hour,
  Object? minute = _minute,
}) =>
    <String, dynamic>{
      'message': message,
      'year': year,
      'month': month,
      'day': day,
      'hour': hour,
      'minute': minute,
    };

Future<String> _run(Map<String, dynamic> args) =>
    ToolExecutorService().execute('set_reminder', args);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The widgets test binding installs an HttpOverrides that answers every
    // request with a canned 400. We need a real loopback socket to a real Core,
    // so it is removed — the binding itself is only here for the MethodChannel.
    HttpOverrides.global = null;
    _channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      _channelCalls.add(call);
      return 'native reminder set';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    ToolExecutorService.resetDesktopReminderSeamForTesting();
  });

  group('the manifest', () {
    test('the desktop workbench offers set_reminder on every route', () {
      // The FINAL request manifest, not the global schema list.
      for (final route in [
        'fastChat',
        'tool',
        'coding',
        'emotional',
        'contemplate',
      ]) {
        for (final confidence in [0.0, 0.9]) {
          final names = ToolExecutorService.toolNames(
            ToolExecutorService.toolsForRoute(route,
                confidence: confidence, hasWorkspace: true),
          );
          expect(names, contains('set_reminder'),
              reason: '$route @ $confidence — "remind me to push this at 5" '
                  'is a normal thing to say mid-task');
        }
      }
    });

    test('the other native device tools are still absent on desktop', () {
      final names = ToolExecutorService.toolNames(
        ToolExecutorService.toolDefinitions,
      ).toSet();
      for (final absent in [
        'set_alarm',
        'set_timer',
        'read_calendar',
        'create_calendar_event',
        'open_app',
        'send_whatsapp',
        'send_sms',
        'call_contact',
        'navigate_to',
        'play_music',
        'read_notifications',
        'read_screen',
      ]) {
        expect(names, isNot(contains(absent)),
            reason: 'no plugin exists for $absent here');
      }
      expect(ToolExecutorService.androidOnlyTools,
          isNot(contains('set_reminder')));
    });

    test('goggles-off surfaces receive no tool manifest at all', () {
      for (final context in [
        KaiSurfaceContext.messenger,
        KaiSurfaceContext.arPublic(
            guestId: 'guest-1', consent: KaiGuestConsent.service),
      ]) {
        final manifest = KaiCapabilityBroker.forContext(context);
        expect(manifest.allowsGeneralTools, isFalse, reason: '$context');
        expect(manifest.exposesToolManifest, isFalse, reason: '$context');
      }
      // Desktop is the one that does.
      expect(
        KaiCapabilityBroker.forContext(KaiSurfaceContext.desktop)
            .allowsGeneralTools,
        isTrue,
      );
    });
  });

  group('creating the promise', () {
    test('stores the exact record and reaches no MethodChannel', () async {
      final f = await _fixture('create');

      final reply = await _run(_args());
      expect(reply, contains(_expectedWall));

      final record = (await f.commitments()).single;
      expect(record['personaId'], 'truekai');
      expect(record['text'], _text, reason: 'byte-for-byte');
      expect(record['dueAt'], _expectedUtc.toIso8601String());
      expect(record['dueWallClock'], _expectedWall);
      expect(record['dueWallOffsetMinutes'], 180);
      expect(record['status'], 'scheduled');
      expect(record['audience'], 'work');
      expect(
        record['commitmentId'],
        KaiScheduledCommitment.deterministicId(
          personaId: 'truekai',
          text: _text,
          dueAtUtc: _expectedUtc,
        ),
      );

      expect(_channelCalls, isEmpty,
          reason: 'the desktop path must never touch the missing plugin');
    });

    test('an identical retry returns the same record and adds nothing',
        () async {
      final f = await _fixture('retry');
      await _run(_args());
      final first = (await f.commitments()).single;

      await _run(_args());
      final all = await f.commitments();

      expect(all, hasLength(1), reason: 'one promise, however many attempts');
      expect(all.single['commitmentId'], first['commitmentId']);
      expect(all.single['createdAt'], first['createdAt']);
    });

    test('different text or a different instant is a different promise',
        () async {
      final f = await _fixture('distinct');
      await _run(_args());
      await _run(_args(message: 'a completely different errand'));
      await _run(_args(hour: 10));

      final all = await f.commitments();
      expect(all, hasLength(3));
      expect(all.map((r) => r['commitmentId']).toSet(), hasLength(3));
    });

    test('the text is stored byte-for-byte, outer whitespace included',
        () async {
      // NOTHING on this path rewrites the promise — not the tool, not Core.
      //
      // An earlier version of this test asserted that Core trimmed the edges
      // and called that acceptable. It was not: "stored and later delivered
      // byte-for-byte" is the invariant the whole vertical slice rests on, and
      // a silent edit is still an edit however small. Core's commitment
      // admission now uses `trim()` only to decide whether anything was said.
      const awkward = '  Ring Ahmed\nabout the "gas line" — 2× before 9:00  ';
      final f = await _fixture('exact_text');
      await _run(_args(message: awkward));
      expect((await f.commitments()).single['text'], awkward,
          reason: 'every character, including the ones at the edges');
    });

    test('whitespace-only text is still refused', () async {
      // Preserving whitespace must not become accepting emptiness.
      final f = await _fixture('whitespace_only');
      for (final blank in ['   ', '\n\n', '\t', ' \r\n ']) {
        final reply = await _run(_args(message: blank));
        expect(reply, isNot(contains('Reminder set for')), reason: blank);
      }
      expect(await f.commitments(), isEmpty);
    });

    test('the length limit measures the original, not a trimmed copy',
        () async {
      // Otherwise 2000 characters of text plus padding would slip past a check
      // that measured something shorter than what gets stored.
      final f = await _fixture('length_limit');
      final justOver = ' ${'x' * 2000} ';
      expect(justOver.length, 2002);
      final reply = await _run(_args(message: justOver));
      expect(reply, isNot(contains('Reminder set for')));
      expect(await f.commitments(), isEmpty);

      final justUnder = ' ${'x' * 1998} ';
      expect(justUnder.length, 2000);
      await _run(_args(message: justUnder));
      expect((await f.commitments()).single['text'], justUnder);
    });

    test('string and whole-number arguments are accepted', () async {
      final f = await _fixture('coercion');
      await _run(_args(year: '2026', month: 9.0, day: '1', hour: 9, minute: 0));
      final record = (await f.commitments()).single;
      expect(record['dueAt'], _expectedUtc.toIso8601String());
      expect(record['dueWallClock'], _expectedWall);
    });
  });

  group('honest refusals leave nothing behind', () {
    /// The executor turns a thrown tool failure into text for the model rather
    /// than rethrowing, so what matters is that the text is not a receipt.
    /// "No success language before Core confirms" is the actual invariant.
    void expectNoReceipt(String reply, {required String because}) {
      expect(reply, isNot(contains('Reminder set for')), reason: because);
      expect(reply.toLowerCase(), isNot(contains('done.')), reason: because);
    }

    Future<void> expectRefused(
      _Fixture f,
      Map<String, dynamic> args, {
      required String because,
    }) async {
      expectNoReceipt(await _run(args), because: because);
      expect(await f.commitments(), isEmpty, reason: because);
      expect(_channelCalls, isEmpty, reason: because);
    }

    test('empty, missing, fractional, impossible and out-of-range input',
        () async {
      final f = await _fixture('invalid');
      await expectRefused(f, _args(message: '   '), because: 'blank text');
      await expectRefused(f, _args(message: null), because: 'no text');
      await expectRefused(f, _args(year: null), because: 'missing year');
      await expectRefused(f, _args(minute: 30.5), because: 'fractional minute');
      await expectRefused(f, _args(month: 13), because: 'month 13');
      await expectRefused(f, _args(month: 2, day: 30), because: '30 February');
      await expectRefused(f, _args(hour: 24), because: 'hour 24');
      await expectRefused(f, _args(minute: 60), because: 'minute 60');
      await expectRefused(f, _args(year: 'soon'), because: 'not a number');
    });

    test('a time that has already passed', () async {
      final f = await _fixture('past');
      f.clock.now = DateTime.utc(2026, 12, 1);
      expectNoReceipt(await _run(_args()), because: 'already passed');
      expect(await f.commitments(), isEmpty);
    });

    test('an unreachable core produces no success and no record', () async {
      final dead = KaiCoreClient(
        endpoint: Uri.parse('http://127.0.0.1:1'),
        timeout: const Duration(milliseconds: 200),
      );
      final f = await _fixture('core_down', override: dead);

      expectNoReceipt(await _run(_args()), because: 'core unreachable');
      expect(await f.commitments(), isEmpty);

      // And the retry, once Core is back, is safe and creates exactly one.
      ToolExecutorService.debugDesktopReminderTool = KaiDesktopReminderTool(
        client: f.client,
        now: f.clock.call,
      );
      await _run(_args());
      expect(await f.commitments(), hasLength(1));
    });

    test('a Core rejection is surfaced, not swallowed', () async {
      final f = await _fixture('rejected');
      // Occupy the deterministic id with a conflicting intent, so Core refuses.
      final id = KaiScheduledCommitment.deterministicId(
        personaId: 'truekai',
        text: _text,
        dueAtUtc: _expectedUtc,
      );
      await f.client.createCommitment(
        commitmentId: id,
        personaId: 'somebody-else',
        text: _text,
        dueAt: _expectedUtc,
        dueWallClock: _expectedWall,
        dueWallOffsetMinutes: 180,
      );

      expectNoReceipt(await _run(_args()), because: 'core refused');
      expect((await f.commitments()).single['personaId'], 'somebody-else',
          reason: 'the stored record is untouched');
    });
  });

  group('the Android path is unchanged', () {
    test('mobile still calls setReminder with the exact argument map',
        () async {
      // Platform authority says this is not a desktop.
      ToolExecutorService.debugIsDesktopPlatform = false;
      ToolExecutorService.debugDesktopReminderTool = KaiDesktopReminderTool(
        client: KaiCoreClient(endpoint: Uri.parse('http://127.0.0.1:1')),
        now: () => DateTime.utc(2026, 8, 8),
      );

      final args = _args();
      final reply = await _run(args);

      expect(_channelCalls, hasLength(1));
      expect(_channelCalls.single.method, 'setReminder');
      expect(
        Map<String, dynamic>.from(_channelCalls.single.arguments as Map),
        args,
        reason: 'the argument map is forwarded untouched',
      );
      expect(reply, contains('native reminder set'));
    });
  });
}
