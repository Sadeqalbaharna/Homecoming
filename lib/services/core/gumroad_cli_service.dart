// GumroadCliService — the only way a gumroad command may run.
//
// The decision of WHAT is permitted lives in lib/logic/gumroad_guard.dart
// (pure, 39 checks). This file is the part that touches the world, and its job
// is to make sure the guard cannot be walked around.
//
// ── Three rules, each protecting against a specific mistake ─────────────────
//
// 1. THE TOKEN NEVER BECOMES AMBIENT.
//    We do NOT run `gumroad auth login` and we do NOT export
//    GUMROAD_ACCESS_TOKEN into the shell Kai uses. A stored token is standing
//    authority: every future shell call inherits it, including ones nobody
//    reviewed. Instead the token is injected into the environment of ONE
//    process, for ONE guarded command, and dies with it.
//
// 2. THE TOKEN IS NEVER AN ARGUMENT.
//    Command-line arguments are visible in the process list to anything on the
//    machine. It goes in the environment map, never argv.
//
// 3. ARGUMENTS ARE A LIST, AND runInShell IS FALSE.
//    No shell means `;`, `&&` and backticks are inert data rather than command
//    separators. The guard rejects them anyway — belt and braces, because the
//    guard should not depend on this file staying correct.
//
// ── What this deliberately cannot do ───────────────────────────────────────
//
// There is no method here that refunds, reads payouts, touches licenses, or
// authenticates. Not "a method that checks approval first" — no method at all.
// Capability you don't build cannot be misused by a confused agent mid-turn.
library;

import 'dart:convert';
import 'dart:io';

import '../../logic/gumroad_guard.dart';
import 'secure_storage_service.dart';

class GumroadResult {
  final bool ok;
  final String output;

  /// Populated when the guard refused, so the caller can tell "the CLI failed"
  /// apart from "Kai was not allowed to try".
  final GuardDecision? refusal;

  const GumroadResult({required this.ok, required this.output, this.refusal});

  bool get wasRefused => refusal != null;
}

class GumroadCliService {
  GumroadCliService._();
  static final GumroadCliService instance = GumroadCliService._();

  /// Where the CLI lives.
  ///
  /// Plain `gumroad` only works if it's on PATH, and a downloaded .exe usually
  /// isn't. Rather than making Sadeq edit his system PATH, we try the known
  /// install location first and fall back to PATH. Overridable for tests.
  static String? binaryOverride;

  static final List<String> _candidates = [
    r'C:\tools\gumroad.exe',
    'gumroad',
  ];

  static String? _resolved;

  /// First candidate that actually exists on disk; otherwise bare `gumroad`
  /// and we let Process.run resolve it via PATH.
  static String get binary {
    if (binaryOverride != null) return binaryOverride!;
    if (_resolved != null) return _resolved!;
    for (final c in _candidates) {
      if (c.contains(RegExp(r'[/\\]')) && File(c).existsSync()) {
        _resolved = c;
        return c;
      }
    }
    _resolved = 'gumroad';
    return _resolved!;
  }

  final _storage = SecureStorageService();

  /// Is the storefront usable at all? False when no token is stored, which is
  /// the correct default — publishing stays impossible until Sadeq opts in.
  Future<bool> isConfigured() async {
    final t = await _storage.getGumroadToken();
    return t != null && t.trim().isNotEmpty;
  }

  /// Run a gumroad command, if and only if the guard permits it.
  ///
  /// [hasApproval] must be derived from a verified HumanApproval for the
  /// current factory run — never from a tool argument and never from anything
  /// Kai asserts about himself.
  Future<GumroadResult> run(
    List<String> args, {
    bool hasApproval = false,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final decision = guardGumroad(args, hasApproval: hasApproval);
    if (!decision.isAllowed) {
      // Refusals are logged loudly. A silently swallowed denial is how a
      // boundary quietly stops being one.
      print('🚫 [Gumroad] REFUSED ${args.join(' ')} — ${decision.reason}');
      return GumroadResult(
        ok: false,
        output: decision.verdict == GuardVerdict.requiresApproval
            ? 'Needs Sadeq: ${decision.reason}'
            : 'Refused: ${decision.reason}',
        refusal: decision,
      );
    }

    final token = await _storage.getGumroadToken();
    if (token == null || token.trim().isEmpty) {
      return const GumroadResult(
        ok: false,
        output: 'No Gumroad token stored. Sadeq sets it once from settings; '
            'I cannot create one.',
      );
    }

    // Forced on every invocation. The CLI prompts interactively by default, and
    // a prompt in a headless agent context doesn't ask a question — it hangs
    // until the timeout, burning a turn for no reason. `--non-interactive` and
    // `--no-input` make it fail loudly instead, which is the behaviour we want.
    //
    // Note this is NOT `--yes`: we're saying "never ask me", not "assume I said
    // yes". A command that needs confirmation should FAIL here, not proceed.
    final safeArgs = <String>[
      ...args,
      if (!args.contains('--non-interactive')) '--non-interactive',
      if (!args.contains('--no-input')) '--no-input',
    ];

    try {
      final proc = await Process.run(
        binary,
        safeArgs,
        // Rule 1 + 2: scoped to this process only, and never in argv.
        environment: {'GUMROAD_ACCESS_TOKEN': token},
        includeParentEnvironment: true,
        // Rule 3: no shell.
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);

      final out = (proc.stdout as String? ?? '').trim();
      final err = (proc.stderr as String? ?? '').trim();
      final ok = proc.exitCode == 0;
      print('${ok ? '✅' : '⚠️'} [Gumroad] ${args.take(2).join(' ')} '
          '→ exit ${proc.exitCode}');
      return GumroadResult(
        ok: ok,
        output: ok ? out : (err.isNotEmpty ? err : out),
      );
    } on ProcessException catch (e) {
      return GumroadResult(
        ok: false,
        output: 'Gumroad CLI not found or failed to start ($e). '
            'Install it before factory publishing can work.',
      );
    } catch (e) {
      return GumroadResult(ok: false, output: 'Gumroad command failed: $e');
    }
  }

  /// Convenience: sales history for the learning loop. Read-only.
  Future<GumroadResult> salesJson() =>
      run(['sales', 'list', '--all', '--json']);

  /// Convenience: create a DRAFT product. Safe by construction — a created
  /// product is not on sale until `publish`, which is gated.
  Future<GumroadResult> createDraft({
    required String name,
    required num price,
    String currency = 'usd',
  }) =>
      run([
        'products',
        'create',
        '--name',
        name,
        '--price',
        price.toString(),
        '--currency',
        currency,
        '--json',
      ]);
}
