// Gateway security tests for Tavern Kai AR channel.
//
// Tests that can run without a live Firebase connection or OpenAI key:
//   • tavernAr mode fails closed when no session token is provided
//   • POST /v1/tavern/provision validates and stores the session
//   • GET /v1/tavern/bootstrap returns the provisioned session
//   • POST /v1/tavern/end clears the session and audio state
//   • /v1/tavern/bootstrap returns 404 before provisioning
//   • Token with wrong persona scope is rejected at provision time
//
// Tests that require Firebase emulator / network:
//   • Revocation check hits the correct RTDB path (see emulator/ test files)
//
// NOTE: These tests start a real HTTP server on a random loopback port.
// AIService is instantiated but its sendMessage() is never called — only
// Tavern management endpoints (provision/bootstrap/end) are exercised here.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/ai_service.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';
import 'package:homecoming_app/services/embodiment/kai_embodiment_gateway_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Test fixtures ──���──────────────────────────────────────────────────────────

const _testSecret = 'gateway-test-hmac-secret-32bytes!';
const _wrongSecret = 'wrong-secret';
const _now = 1700000000000;
const _ttlMs = 15 * 60 * 1000;
const _guestUid = 'uid_gateway_test_guest';
const _visitId = 'visit_gw_test';
const _tableId = 'T04';

String _buildToken({
  String guestUid = _guestUid,
  String visitId = _visitId,
  String tableId = _tableId,
  String personaScope = 'tavern_kai',
  int? exp,
  String secret = _testSecret,
}) {
  final expMs = exp ?? DateTime.now().millisecondsSinceEpoch + _ttlMs;
  final payload = jsonEncode({
    'sessionId': 'gw-test-session-id',
    'guestUid': guestUid,
    'visitId': visitId,
    'tableId': tableId,
    'personaScope': personaScope,
    'capabilities': ['conversation', 'menu_query'],
    'iat': _now,
    'exp': expMs,
    'nonce': 'gw-test-nonce',
  });
  final payloadB64 = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  final hmac = Hmac(sha256, utf8.encode(secret));
  final sig = base64Url.encode(hmac.convert(utf8.encode(payloadB64)).bytes).replaceAll('=', '');
  return '$payloadB64.$sig';
}

// ── Helpers ──────���────────────────────────────────────────────────────────────

Map<String, String> get _loopbackAuth => const {'Authorization': 'Bearer dev-test-token'};

Future<http.Response> _post(Uri base, String path, Map<String, dynamic> body) =>
    http.post(
      base.resolve(path),
      headers: {
        ..._loopbackAuth,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

Future<http.Response> _get(Uri base, String path) =>
    http.get(base.resolve(path), headers: _loopbackAuth);

// ── Tests ─────────────────���───────────────────────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // TestWidgetsFlutterBinding installs an HttpOverride that returns 400 for
    // all requests. This test suite starts a real loopback HTTP server and
    // issues real requests to it, so we must undo that override.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  late KaiEmbodimentGatewayService gateway;
  late Uri base;

  setUp(() async {
    gateway = KaiEmbodimentGatewayService.ar;
    // Start in personalAr mode first (no HMAC secret needed from env).
    await gateway.start(
      ai: AIService(),
      channelSurface: KaiSurface.ar,
      port: 0, // random free port
      token: 'dev-test-token',
      allowUnauthenticatedLoopback: false,
    );
    // Override mode + secret directly for testing without env var.
    gateway.setTavernSecretForTesting(_testSecret, TavernGatewayMode.tavernAr);
    base = gateway.endpoint!;
  });

  tearDown(() => gateway.stop());

  // ── Provision ──────────────────────────────────────────────────────────────

  group('POST /v1/tavern/provision', () {
    test('accepts a valid signed token and returns the session summary', () async {
      final token = _buildToken();
      final resp = await _post(base, '/v1/tavern/provision', {'sessionToken': token});

      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body) as Map;
      expect(body['provisioned'], isTrue);
      expect(body['sessionId'], isNotNull);
      expect(body['tableId'], _tableId);
    });

    test('rejects token with wrong HMAC signature', () async {
      final token = _buildToken(secret: _wrongSecret);
      final resp = await _post(base, '/v1/tavern/provision', {'sessionToken': token});

      expect(resp.statusCode, 400);
      final body = jsonDecode(resp.body) as Map;
      expect(body['error'], 'invalid_session_token');
      expect(body['reason'], 'invalid_signature');
    });

    test('rejects token with wrong persona scope', () async {
      final token = _buildToken(personaScope: 'personal_kai');
      final resp = await _post(base, '/v1/tavern/provision', {'sessionToken': token});

      expect(resp.statusCode, 400);
      final body = jsonDecode(resp.body) as Map;
      expect(body['reason'], 'wrong_persona_scope');
    });

    test('rejects expired token', () async {
      // Token expired 1ms ago (relative to the fixed _now, but real system
      // clock is used in provision — so build a token that's already expired).
      final expiredToken = _buildToken(exp: 1); // epoch 1ms — definitely expired
      final resp = await _post(base, '/v1/tavern/provision', {'sessionToken': expiredToken});

      expect(resp.statusCode, 400);
      final body = jsonDecode(resp.body) as Map;
      expect(body['reason'], 'expired');
    });

    test('requires authorization', () async {
      final token = _buildToken();
      final resp = await http.post(
        base.resolve('/v1/tavern/provision'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionToken': token}),
      );
      expect(resp.statusCode, 401);
    });
  });

  // ── Bootstrap ───────────────────────────────��──────────────────────────────

  group('GET /v1/tavern/bootstrap', () {
    test('returns 404 before any session is provisioned', () async {
      final resp = await _get(base, '/v1/tavern/bootstrap');
      expect(resp.statusCode, 404);
      expect(jsonDecode(resp.body)['error'], 'no_active_session');
    });

    test('returns the provisioned session after provision succeeds', () async {
      final token = _buildToken();
      await _post(base, '/v1/tavern/provision', {'sessionToken': token});

      final resp = await _get(base, '/v1/tavern/bootstrap');
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body) as Map;
      expect(body['sessionToken'], isNotNull);
      expect(body['tableId'], _tableId);
      expect(body['guestUid'], _guestUid);
      expect(body['personaScope'], 'tavern_kai');
      expect(body['capabilities'], contains('conversation'));
      // Must not contain personal_kai capabilities
      expect(body['capabilities'], isNot(contains('personal_kai')));
    });

    test('requires authorization', () async {
      final resp = await http.get(base.resolve('/v1/tavern/bootstrap'));
      expect(resp.statusCode, 401);
    });
  });

  // ── End session ──────��─────────────────────────────────────────────────────

  group('POST /v1/tavern/end', () {
    test('clears the provisioned session', () async {
      final token = _buildToken();
      await _post(base, '/v1/tavern/provision', {'sessionToken': token});

      // Confirm session exists
      expect((await _get(base, '/v1/tavern/bootstrap')).statusCode, 200);

      // End it
      final resp = await _post(base, '/v1/tavern/end', {});
      expect(resp.statusCode, 200);
      expect(jsonDecode(resp.body)['cleared'], isTrue);

      // Confirm session is gone
      expect((await _get(base, '/v1/tavern/bootstrap')).statusCode, 404);
    });

    test('end on an already-empty gateway returns cleared:false', () async {
      final resp = await _post(base, '/v1/tavern/end', {});
      expect(resp.statusCode, 200);
      expect(jsonDecode(resp.body)['cleared'], isFalse);
    });
  });

  // ── Fail-closed in tavernAr mode ───��───────────────────────────────────────

  group('/v1/turn fail-closed in tavernAr mode', () {
    final turnBody = jsonEncode({
      'surface': 'ar',
      'utterance': 'Hello',
      'personaId': 'truekai',
      'sessionId': 'session-1',
      'deviceId': 'unity-ar-test',
      'conversationId': 'conv-1',
      'mode': 'conversational',
      'correlationId': 'corr-1',
    });

    test('turn without X-Tavern-Session-Token header is rejected with 401', () async {
      final resp = await http.post(
        base.resolve('/v1/turn'),
        headers: {
          ..._loopbackAuth,
          'Content-Type': 'application/json',
        },
        body: turnBody,
      );
      expect(resp.statusCode, 401);
      expect(jsonDecode(resp.body)['error'], 'tavern_session_required');
    });

    test('turn with invalid session token is rejected with 401', () async {
      final resp = await http.post(
        base.resolve('/v1/turn'),
        headers: {
          ..._loopbackAuth,
          'Content-Type': 'application/json',
          'X-Tavern-Session-Token': 'malformed.token',
        },
        body: turnBody,
      );
      expect(resp.statusCode, 401);
      final body = jsonDecode(resp.body) as Map;
      expect(body['error'], 'tavern_session_invalid');
    });

    test('turn with expired session token is rejected', () async {
      final expiredToken = _buildToken(exp: 1);
      final resp = await http.post(
        base.resolve('/v1/turn'),
        headers: {
          ..._loopbackAuth,
          'Content-Type': 'application/json',
          'X-Tavern-Session-Token': expiredToken,
        },
        body: turnBody,
      );
      expect(resp.statusCode, 401);
      expect(jsonDecode(resp.body)['reason'], 'expired');
    });
  });

  // ── Feature flag: disabled by default ──────────────────────────────────────
  // Every other test in this file calls setTavernSecretForTesting() to force
  // tavernAr mode on, so without these nothing exercises the default posture.
  // The production caller (KaiHeadlessCoordinator._startEmbodimentGateways)
  // omits tavernMode entirely and must therefore land in personalAr.

  group('TavernGatewayMode defaults', () {
    test('start() without tavernMode does not require the HMAC secret', () async {
      // personalAr is the default, so a gateway must come up cleanly on a
      // machine that has never heard of TAVERN_KAI_HMAC_SECRET — otherwise
      // shipping this contract would break every existing personal AR user.
      await gateway.stop();
      await gateway.start(
        ai: AIService(),
        channelSurface: KaiSurface.ar,
        port: 0,
        token: 'dev-test-token',
        allowUnauthenticatedLoopback: false,
        // tavernMode deliberately omitted — this is the production call shape.
      );
      expect(gateway.endpoint, isNotNull);

      // And with the feature off, tavern management routes must not serve a
      // session to anyone, even an authorized loopback caller.
      final resp = await _get(gateway.endpoint!, '/v1/tavern/bootstrap');
      expect(resp.statusCode, 404);
    });

    test('tavernAr mode fails closed when TAVERN_KAI_HMAC_SECRET is absent', () async {
      // Opting in without provisioning the secret must throw, never fall back
      // to an unsigned/permissive mode.
      await gateway.stop();
      // expectLater, not expect: start() is async, and a bare
      // expect(() => future, throwsA(...)) can report success without the
      // rejection ever being awaited — a false pass on a fail-closed test.
      await expectLater(
        gateway.start(
          ai: AIService(),
          channelSurface: KaiSurface.ar,
          port: 0,
          token: 'dev-test-token',
          tavernMode: TavernGatewayMode.tavernAr,
        ),
        throwsA(isA<StateError>()),
      );
      // And it must not have left a half-started server listening.
      expect(gateway.endpoint, isNull);
    });
  });

  // ── Route isolation ────────────────────────────────────────────────────────

  group('route isolation', () {
    test('/v1/tavern/bootstrap is only available on AR channel', () async {
      // VR channel should return 404 for tavern routes
      final vrGateway = KaiEmbodimentGatewayService.vr;
      await vrGateway.start(
        ai: AIService(),
        channelSurface: KaiSurface.vr,
        port: 0,
        token: 'dev-test-token',
      );
      addTearDown(() => vrGateway.stop());

      final vrBase = vrGateway.endpoint!;
      final resp = await _get(vrBase, '/v1/tavern/bootstrap');
      expect(resp.statusCode, 404);
    });
  });
}
