/// KaiSecretRotationCard — every credential, its age, and the way to rotate it.
///
/// ── What this deliberately does not do ──────────────────────────────────────
///
/// It never renders a secret value. Not masked, not truncated, not behind a
/// reveal button. This app has `read_screen` as a tool, so anything on screen is
/// readable by the assistant as well as by a screenshot or a share — a "tap to
/// reveal" would be a hole with a lid on it.
///
/// What it shows is enough to act: which credentials exist, where each lives,
/// how long since it was rotated, and a button that opens the exact console
/// page. The friction was never the clicking; it was not knowing what the list
/// was or which ones were already done.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/secret_registry.dart';
import '../services/core/kai_secret_inventory.dart';

class KaiSecretRotationCard extends StatefulWidget {
  const KaiSecretRotationCard({super.key});

  @override
  State<KaiSecretRotationCard> createState() => _KaiSecretRotationCardState();
}

class _KaiSecretRotationCardState extends State<KaiSecretRotationCard> {
  KaiSecretRegistry? _registry;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final registry = await KaiSecretInventory.load();
    if (mounted) setState(() => _registry = registry);
  }

  Future<void> _markRotated(KaiSecret secret) async {
    await KaiSecretInventory.recordRotation(secret.id, DateTime.now());
    await _reload();
  }

  /// Copies the console URL rather than launching it.
  ///
  /// No new dependency, and it works identically on desktop and phone. The
  /// friction being removed is "which page do I even go to", and a URL on the
  /// clipboard removes that just as well as a launch would.
  Future<void> _openConsole(KaiSecret secret) async {
    if (secret.consoleUrl.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: secret.consoleUrl));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('${secret.provider} console URL copied'),
      ),
    );
  }

  static const _red = Color(0xFFE8674F);
  static const _amber = Color(0xFFE0B04A);
  static const _blue = Color(0xFF7B9BE8);
  static const _green = Color(0xFF4FD18B);
  static const _grey = Color(0xFF6F8699);

  Color _colourFor(KaiSecretUrgency u) => switch (u) {
        KaiSecretUrgency.exposed => _red,
        KaiSecretUrgency.overdue => _red,
        KaiSecretUrgency.neverRotated => _amber,
        KaiSecretUrgency.aging => _blue,
        KaiSecretUrgency.fresh => _green,
        KaiSecretUrgency.informational => _grey,
      };

  String _ageLabel(KaiSecret s, DateTime now) {
    if (s.kind == KaiSecretKind.publicIdentifier) return 'public identifier';
    final age = s.ageInDays(now);
    if (age == null) return 'never rotated';
    if (age == 0) return 'rotated today';
    if (age == 1) return 'rotated yesterday';
    if (age < 60) return '$age days ago';
    final months = (age / 30).floor();
    return '$months months ago';
  }

  @override
  Widget build(BuildContext context) {
    final registry = _registry;
    if (registry == null) {
      return const SizedBox(height: 72, child: Center(
        child: SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }

    final now = DateTime.now();
    final ranked = registry.ranked(now);
    final headline = registry.summary(now);
    final worst = ranked.isEmpty
        ? KaiSecretUrgency.fresh
        : ranked.first.urgency(now);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1D2B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF24394B)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 16, color: _colourFor(worst)),
              const SizedBox(width: 8),
              const Text(
                'KEYS',
                style: TextStyle(
                  color: Color(0xFFA2B6C6),
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                headline,
                style: TextStyle(
                  color: _colourFor(worst),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF6F8699),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          if (!_expanded) ...[
            const SizedBox(height: 6),
            // The value is not here and never will be. Saying so stops the
            // question being asked.
            const Text(
              'Ages and locations only — no key is ever shown.',
              style: TextStyle(color: _grey, fontSize: 10.5),
            ),
          ],
          if (_expanded)
            ...ranked.map((s) => _row(s, now)),
        ],
      ),
    );
  }

  Widget _row(KaiSecret s, DateTime now) {
    final urgency = s.urgency(now);
    final colour = _colourFor(urgency);
    final actionable = s.kind == KaiSecretKind.secret;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: colour),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.label,
                  style: const TextStyle(
                    color: Color(0xFFDCE7F0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _ageLabel(s, now),
                style: TextStyle(color: colour, fontSize: 11),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 2),
            child: Text(
              s.location,
              style: const TextStyle(
                color: Color(0xFF6F8699),
                fontSize: 10.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (s.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 3),
              child: Text(
                s.note,
                style: const TextStyle(color: Color(0xFF8FA3B4), fontSize: 10.5),
              ),
            ),
          if (actionable)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 6),
              child: Row(
                children: [
                  _button('Open console', () => _openConsole(s), colour),
                  const SizedBox(width: 8),
                  // Two separate taps on purpose. Recording a rotation that did
                  // not happen would reset the clock on a live key and hide it
                  // for another ninety days — the one failure this card exists
                  // to prevent.
                  _button('I rotated it', () => _markRotated(s), _grey),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, Color colour) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colour.withOpacity(0.55)),
          ),
          child: Text(
            label,
            style: TextStyle(color: colour, fontSize: 10.5),
          ),
        ),
      );
}
