/// KaiKeyStatusStrip — how old every credential is, above the fields.
///
/// Sits at the top of the keys screen so the answer to "which of these needs
/// doing" is visible before scrolling, and lists the credentials this screen
/// CANNOT edit — compile-time constants and Firebase config — because a panel
/// that silently omits half the keys is worse than no panel.
///
/// ── It never renders a value ────────────────────────────────────────────────
///
/// Not masked, not truncated, not behind a reveal. This app has `read_screen`
/// as a tool, so anything drawn is readable by the assistant as well as by a
/// screenshot or a share. The fields below it already hold the values — this
/// strip only ever shows names, locations and ages.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/secret_registry.dart';
import '../services/core/kai_secret_inventory.dart';

class KaiKeyStatusStrip extends StatelessWidget {
  const KaiKeyStatusStrip({super.key, required this.registry});

  final KaiSecretRegistry? registry;

  static const _red = Color(0xFFE8674F);
  static const _amber = Color(0xFFE0B04A);
  static const _blue = Color(0xFF7B9BE8);
  static const _green = Color(0xFF4FD18B);
  static const _grey = Color(0xFF6F8699);

  static Color colourFor(KaiSecretUrgency u) => switch (u) {
        KaiSecretUrgency.exposed || KaiSecretUrgency.overdue => _red,
        KaiSecretUrgency.neverRotated => _amber,
        KaiSecretUrgency.aging => _blue,
        KaiSecretUrgency.fresh => _green,
        KaiSecretUrgency.informational => _grey,
      };

  /// The age line for one credential. Public so the fields below can reuse it.
  static String ageLabel(KaiSecret s, DateTime now) {
    if (s.kind == KaiSecretKind.publicIdentifier) return 'public identifier';
    final age = s.ageInDays(now);
    if (age == null) return 'never rotated';
    if (age == 0) return 'updated today';
    if (age == 1) return 'updated yesterday';
    if (age < 60) return 'updated $age days ago';
    return 'updated ${(age / 30).floor()} months ago';
  }

  @override
  Widget build(BuildContext context) {
    final reg = registry;
    if (reg == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final ranked = reg.ranked(now);
    final worst =
        ranked.isEmpty ? KaiSecretUrgency.fresh : ranked.first.urgency(now);
    final headline = reg.summary(now);

    // Only the ones this screen cannot edit. The rest have their own field
    // directly below with its own age line, so repeating them here would be
    // noise.
    final unmanaged = ranked
        .where((s) => !KaiSecretInventory.editableIds.contains(s.id))
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1826),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colourFor(worst).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, size: 14, color: colourFor(worst)),
              const SizedBox(width: 8),
              const Text(
                'ROTATION',
                style: TextStyle(
                  color: Color(0xFF9FD0E8),
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Text(
                headline,
                style: TextStyle(
                  color: colourFor(worst),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Saving a changed key records its date automatically. '
            'No key is ever displayed here.',
            style: TextStyle(color: _grey, fontSize: 10.5),
          ),
          if (unmanaged.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'NOT EDITABLE HERE',
              style: TextStyle(
                color: Color(0xFF6F8699),
                fontSize: 9,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            ...unmanaged.map((s) => _unmanagedRow(context, s, now)),
          ],
        ],
      ),
    );
  }

  Widget _unmanagedRow(BuildContext context, KaiSecret s, DateTime now) {
    final colour = colourFor(s.urgency(now));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: colour),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.label,
                  style: const TextStyle(
                    color: Color(0xFFDCE7F0),
                    fontSize: 11.5,
                  ),
                ),
              ),
              Text(
                ageLabel(s, now),
                style: TextStyle(color: colour, fontSize: 10.5),
              ),
              if (s.consoleUrl.isNotEmpty) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: s.consoleUrl),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text('${s.provider} console URL copied'),
                      ),
                    );
                  },
                  child: const Icon(Icons.link,
                      size: 13, color: Color(0xFF6F8699)),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 1),
            child: Text(
              s.location,
              style: const TextStyle(
                color: Color(0xFF5A7183),
                fontSize: 9.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (s.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 1),
              child: Text(
                s.note,
                style: const TextStyle(
                    color: Color(0xFF7A8E9E), fontSize: 9.5),
              ),
            ),
        ],
      ),
    );
  }
}
