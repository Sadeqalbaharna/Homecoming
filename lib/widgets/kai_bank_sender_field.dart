/// KaiBankSenderField — which senders may reach the ledger.
///
/// Not a credential, but the same shape of thing and the same consequences: a
/// short string that grants access, which is why it sits beside the API keys
/// rather than buried in a settings page.
///
/// ── This list IS the trust boundary ─────────────────────────────────────────
///
/// Nothing downstream re-checks provenance. An enrolled sender's messages can
/// become ledger rows and, with a rule, be auto-approved; everything else is
/// parsed and left pending forever.
///
/// Two properties the UI has to preserve:
///
///   EMPTY MEANS NOTHING IS CAPTURED, and that is the correct starting state.
///   An earlier build shipped guessed Bahraini sender ids, which invented a
///   boundary instead of asking for one — and a wrong guess fails as SILENCE.
///   So the empty state says so loudly rather than looking merely tidy.
///
///   EXACT MATCH. "Anything containing BANK" matches a scammer calling
///   themselves BANK-ALERT, so the field asks for the sender id verbatim and
///   says why capitalisation and punctuation are copied, not typed.
library;

import 'package:flutter/material.dart';

import '../logic/ledger_sources.dart';
import '../services/core/kai_ledger_runner.dart';

class KaiBankSenderField extends StatefulWidget {
  const KaiBankSenderField({super.key});

  @override
  State<KaiBankSenderField> createState() => _KaiBankSenderFieldState();
}

class _KaiBankSenderFieldState extends State<KaiBankSenderField> {
  final _controller = TextEditingController();
  KaiLedgerSources? _sources;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final sources = await KaiLedgerRunner.loadSources();
    if (mounted) setState(() => _sources = sources);
  }

  Future<void> _add() async {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    setState(() => _saving = true);
    await KaiLedgerRunner.enrolSms(id);
    _controller.clear();
    await _reload();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _remove(String id) async {
    await KaiLedgerRunner.revokeSms(id);
    await _reload();
  }

  static const _cyan = Color(0xFF2ED9FF);
  static const _amber = Color(0xFFE0B04A);
  static const _grey = Color(0xFF6F8699);

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final enrolled = sources?.enabled
            .where((s) => s.channel == KaiLedgerChannel.sms)
            .toList(growable: false) ??
        const <KaiLedgerSource>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1826),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enrolled.isEmpty
              ? _amber.withOpacity(0.45)
              : const Color(0xFF24384C),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sms_outlined,
                  size: 14, color: enrolled.isEmpty ? _amber : _cyan),
              const SizedBox(width: 8),
              const Text(
                'BANK ALERT SENDERS',
                style: TextStyle(
                  color: Color(0xFF9FD0E8),
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Text(
                enrolled.isEmpty ? 'none — nothing is captured' : '${enrolled.length} enrolled',
                style: TextStyle(
                  color: enrolled.isEmpty ? _amber : _grey,
                  fontSize: 11,
                  fontWeight: enrolled.isEmpty ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Copy the sender exactly as it appears in Messages — case and '
            'punctuation included. It is matched exactly, so a near-miss '
            'captures nothing and says nothing.',
            style: TextStyle(color: _grey, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. AlSalamBank',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: const Color(0xFF0A1420),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF24384C)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF24384C)),
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _saving ? null : _add,
                child: const Text('Enrol'),
              ),
            ],
          ),
          if (enrolled.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in enrolled)
                  Chip(
                    backgroundColor: const Color(0xFF10323C),
                    side: const BorderSide(color: Color(0xFF24384C)),
                    label: Text(
                      s.identifier,
                      style: const TextStyle(
                        color: Color(0xFFDCE7F0),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 13),
                    // Removing genuinely removes: the list is pushed to the
                    // phone before every drain, so a revocation reaches the
                    // capture filter within one cycle rather than at next
                    // launch.
                    onDeleted: () => _remove(s.identifier),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
