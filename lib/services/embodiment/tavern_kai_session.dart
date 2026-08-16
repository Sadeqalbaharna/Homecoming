// Pure HMAC-SHA256 validation for TavernKaiSession tokens.
//
// Token format mirrors the Node.js implementation in functions/tavern_kai_session.js:
//   base64url(JSON.stringify(payload)) + "." + HMAC-SHA256(base64url_payload, secret)
//
// The HMAC is computed over the UTF-8 bytes of the base64url payload string —
// both sides must agree on this to produce matching signatures.
//
// Security invariants enforced here:
// • guestUid is read from the HMAC-verified payload — never from a header or body
// • personaScope must equal 'tavern_kai' exactly
// • Expired tokens are rejected before any field access
// • This class performs no I/O — revocation checking is the gateway's responsibility

import 'dart:convert';
import 'package:crypto/crypto.dart';

const _personaScope = 'tavern_kai';

class TavernKaiSession {
  final String sessionId;
  final String guestUid;
  final String visitId;
  final String tableId;
  final List<String> capabilities;
  final int expiresAt;

  const TavernKaiSession({
    required this.sessionId,
    required this.guestUid,
    required this.visitId,
    required this.tableId,
    required this.capabilities,
    required this.expiresAt,
  });
}

sealed class TavernSessionResult {
  const TavernSessionResult();
}

final class TavernSessionValid extends TavernSessionResult {
  final TavernKaiSession session;
  const TavernSessionValid(this.session);
}

final class TavernSessionInvalid extends TavernSessionResult {
  final String reason;
  const TavernSessionInvalid(this.reason);
}

// ── Base64url helpers ─────────────────────────────────────────────────────────
// Node.js base64url encoding strips padding. Dart's base64Url includes it.
// We strip on encode and add on decode to keep both sides compatible.

String _b64urlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _b64urlDecode(String input) {
  // Pad to a multiple of 4 if needed.
  final padded = input.padRight(((input.length + 3) ~/ 4) * 4, '=');
  return base64Url.decode(padded);
}

// ── Token validation ──────────────────────────────────────────────────────────

/// Validate a TavernKaiSession token.
///
/// [nowMs] is the current time in milliseconds since epoch. Pass
/// `DateTime.now().millisecondsSinceEpoch` in production, or a fixed value
/// in tests for determinism.
///
/// Returns [TavernSessionValid] on success, [TavernSessionInvalid] otherwise.
/// This function performs no I/O — revocation checking is the caller's job.
TavernSessionResult validateTavernToken(
    String token, String secret, int nowMs) {
  final dotIdx = token.lastIndexOf('.');
  if (dotIdx <= 0) return const TavernSessionInvalid('malformed');

  final payloadB64 = token.substring(0, dotIdx);
  final sig = token.substring(dotIdx + 1);

  // Compute expected HMAC over the UTF-8 bytes of the base64url payload string.
  final hmac = Hmac(sha256, utf8.encode(secret));
  final expectedDigest = hmac.convert(utf8.encode(payloadB64));
  final expectedSig = _b64urlEncode(expectedDigest.bytes);

  if (sig != expectedSig) return const TavernSessionInvalid('invalid_signature');

  final Map<String, dynamic> payload;
  try {
    final decoded = utf8.decode(_b64urlDecode(payloadB64));
    payload = jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    return const TavernSessionInvalid('invalid_payload');
  }

  if (payload['personaScope'] != _personaScope) {
    return const TavernSessionInvalid('wrong_persona_scope');
  }

  final exp = payload['exp'];
  if (exp is! int || exp <= nowMs) {
    return const TavernSessionInvalid('expired');
  }

  final sessionId = payload['sessionId'] as String?;
  final guestUid = payload['guestUid'] as String?;
  final visitId = payload['visitId'] as String?;
  final tableId = payload['tableId'] as String?;

  if (sessionId == null ||
      sessionId.isEmpty ||
      guestUid == null ||
      guestUid.isEmpty ||
      visitId == null ||
      visitId.isEmpty ||
      tableId == null ||
      tableId.isEmpty) {
    return const TavernSessionInvalid('missing_fields');
  }

  final rawCaps = payload['capabilities'];
  final capabilities = rawCaps is List
      ? rawCaps.map((e) => e.toString()).toList()
      : <String>['conversation'];

  return TavernSessionValid(
    TavernKaiSession(
      sessionId: sessionId,
      guestUid: guestUid,
      visitId: visitId,
      tableId: tableId,
      capabilities: capabilities,
      expiresAt: exp,
    ),
  );
}
