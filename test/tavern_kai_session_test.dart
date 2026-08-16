// Contract tests for TavernKaiSession token validation.
//
// These tests verify the security contract at the Dart boundary — the same
// logic the AR gateway uses to validate tokens issued by Cloud Functions.
//
// Companion test file (Node.js): functions/test/tavern_kai_session_test.js

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/embodiment/tavern_kai_session.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _secret = 'dev-test-hmac-secret-32-bytes!!';
const _wrongSecret = 'wrong-secret';
const _now = 1700000000000; // fixed epoch — milliseconds since Unix epoch
const _ttlMs = 15 * 60 * 1000;
const _guestA = 'uid_guest_aaaaaaaaaaa';
const _guestB = 'uid_guest_bbbbbbbbbbb';
const _visitA = 'visit_aaa';
const _tableA = 'T04';

/// Build a minimal valid token using the same algorithm as Cloud Functions.
String _buildToken({
  String guestUid = _guestA,
  String visitId = _visitA,
  String tableId = _tableA,
  String personaScope = 'tavern_kai',
  int? exp,
  String secret = _secret,
}) {
  final expMs = exp ?? _now + _ttlMs;
  final payload = jsonEncode({
    'sessionId': 'test-session-id',
    'guestUid': guestUid,
    'visitId': visitId,
    'tableId': tableId,
    'personaScope': personaScope,
    'capabilities': ['conversation', 'menu_query'],
    'iat': _now,
    'exp': expMs,
    'nonce': 'test-nonce',
  });

  // base64url without padding (matches Node.js Buffer.from(x).toString('base64url'))
  final payloadB64 =
      base64Url.encode(utf8.encode(payload)).replaceAll('=', '');

  final hmac = Hmac(sha256, utf8.encode(secret));
  final digest = hmac.convert(utf8.encode(payloadB64));
  final sig = base64Url.encode(digest.bytes).replaceAll('=', '');

  return '$payloadB64.$sig';
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('valid session', () {
    test('round-trips correctly', () {
      final token = _buildToken();
      final result = validateTavernToken(token, _secret, _now);

      expect(result, isA<TavernSessionValid>());
      final session = (result as TavernSessionValid).session;
      expect(session.guestUid, _guestA);
      expect(session.visitId, _visitA);
      expect(session.tableId, _tableA);
      expect(session.capabilities, contains('conversation'));
      expect(session.capabilities, contains('menu_query'));
    });

    test('accepted one millisecond before expiry', () {
      final token = _buildToken(exp: _now + _ttlMs);
      // exp = _now + _ttlMs; nowMs = _now + _ttlMs - 1 → exp > nowMs → valid
      final result = validateTavernToken(token, _secret, _now + _ttlMs - 1);
      expect(result, isA<TavernSessionValid>());
    });
  });

  group('expiry', () {
    test('token at exactly expiry is rejected', () {
      final token = _buildToken(exp: _now + _ttlMs);
      final result = validateTavernToken(token, _secret, _now + _ttlMs);
      expect(result, isA<TavernSessionInvalid>());
      expect((result as TavernSessionInvalid).reason, 'expired');
    });

    test('expired token is rejected', () {
      final token = _buildToken(exp: _now - 1);
      final result = validateTavernToken(token, _secret, _now);
      expect(result, isA<TavernSessionInvalid>());
      expect((result as TavernSessionInvalid).reason, 'expired');
    });
  });

  group('signature integrity', () {
    test('tampered token is rejected', () {
      final token = _buildToken();
      final tampered = '${token.substring(0, token.length - 4)}ZZZZ';
      final result = validateTavernToken(tampered, _secret, _now);
      expect(result, isA<TavernSessionInvalid>());
      expect((result as TavernSessionInvalid).reason, 'invalid_signature');
    });

    test('wrong secret is rejected', () {
      final token = _buildToken(secret: _secret);
      final result = validateTavernToken(token, _wrongSecret, _now);
      expect(result, isA<TavernSessionInvalid>());
      expect((result as TavernSessionInvalid).reason, 'invalid_signature');
    });

    test('malformed tokens are rejected', () {
      for (final bad in ['', 'notvalid', 'only.one', '.nodot']) {
        final result = validateTavernToken(bad, _secret, _now);
        expect(result, isA<TavernSessionInvalid>(),
            reason: 'expected invalid for "$bad"');
      }
    });
  });

  group('persona scope', () {
    test('personal_kai scope is rejected even with valid signature', () {
      // Build a validly-signed token where personaScope = 'personal_kai'.
      final token = _buildToken(personaScope: 'personal_kai');
      final result = validateTavernToken(token, _secret, _now);
      expect(result, isA<TavernSessionInvalid>());
      expect((result as TavernSessionInvalid).reason, 'wrong_persona_scope');
    });
  });

  group('guest isolation', () {
    test('guestA token decodes to guestA uid, never guestB', () {
      final tokenA = _buildToken(guestUid: _guestA);
      final tokenB = _buildToken(guestUid: _guestB);

      final rA = validateTavernToken(tokenA, _secret, _now) as TavernSessionValid;
      final rB = validateTavernToken(tokenB, _secret, _now) as TavernSessionValid;

      expect(rA.session.guestUid, _guestA);
      expect(rB.session.guestUid, _guestB);
      expect(rA.session.guestUid, isNot(_guestB));
    });

    test('guestA token cannot decode as guestB — uid is in signed payload', () {
      final tokenA = _buildToken(guestUid: _guestA);
      final result = validateTavernToken(tokenA, _secret, _now);

      // Any attempt to forge the guestUid would change the payload and
      // invalidate the HMAC. The only valid outcome is guestA's uid.
      expect((result as TavernSessionValid).session.guestUid, _guestA);
    });
  });

  group('capabilities', () {
    test('tavern_kai token does not include personal_kai capability strings', () {
      final token = _buildToken();
      final result = validateTavernToken(token, _secret, _now) as TavernSessionValid;
      final caps = result.session.capabilities;

      expect(caps, isNot(contains('relationship_memory')));
      expect(caps, isNot(contains('sharedLife')));
      expect(caps, isNot(contains('personal_kai')));
      expect(caps, isNot(contains('private_thoughts')));
    });
  });

  group('no personal_kai data in token', () {
    test('raw token string does not contain guestUid as plaintext', () {
      final token = _buildToken(guestUid: _guestA);
      // guestUid is base64url-encoded inside the payload — not raw text.
      expect(token, isNot(contains(_guestA)));
    });
  });
}
