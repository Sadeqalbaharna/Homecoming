// tavern_link_screen.dart
//
// FIRST-RUN badge linking for a customer who HAS the Kingdom app.
// The hero taps their own NFC badge to the phone → we bind that badge UID to
// their (anonymous) Firebase auth UID + email, so every later table tap is
// recognised as them.
//
// Writes (RTDB kingdom-ac44f):
//   nfc_links/{badgeUid}      = { authUid, email, linkedAt }   ← the Pi reads this on every tap
//   users/{authUid}/profile   ← { nfcUid, name, email, linkedAt }  (merged)
//
// Gate it with TavernLink.isLinked() so it only ever runs once.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rtdb = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app';
const _prefKey = 'tavern_nfc_linked';

/// Tiny helper so the app can decide whether to show the link screen.
class TavernLink {
  /// True once a badge has been linked on this device.
  static Future<bool> isLinked() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefKey) ?? false;
  }

  static Future<void> _markLinked() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, true);
  }
}

class TavernLinkScreen extends StatefulWidget {
  const TavernLinkScreen({super.key});

  @override
  State<TavernLinkScreen> createState() => _TavernLinkScreenState();
}

class _TavernLinkScreenState extends State<TavernLinkScreen> {
  String? _badgeUid;
  bool _scanning = false;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // ── RTDB helpers ───────────────────────────────────────────────────────────
  Future<void> _rtdbPut(String path, Map<String, dynamic> data) =>
      http.put(Uri.parse('$_rtdb/$path.json'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));

  Future<void> _rtdbPatch(String path, Map<String, dynamic> data) =>
      http.patch(Uri.parse('$_rtdb/$path.json'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));

  // ── NFC ────────────────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (!await NfcManager.instance.isAvailable()) {
      setState(() => _error = 'NFC not available on this device');
      return;
    }
    setState(() { _scanning = true; _error = null; _saved = false; });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final uid = _extractUid(tag);
        await NfcManager.instance.stopSession();
        setState(() {
          _scanning = false;
          if (uid == null) {
            _error = 'Could not read UID from this badge';
          } else {
            _badgeUid = uid;
          }
        });
      },
      onError: (e) async {
        await NfcManager.instance.stopSession(errorMessage: e.message);
        setState(() { _scanning = false; _error = e.message; });
      },
    );
  }

  String? _extractUid(NfcTag tag) {
    final data = tag.data;
    for (final key in ['nfca', 'iso14443a', 'nfcb', 'iso14443b', 'nfcf', 'nfcv', 'ndef']) {
      final entry = data[key];
      if (entry != null) {
        final id = entry['identifier'] as List?;
        if (id != null) return _bytesToHex(id);
      }
    }
    return null;
  }

  String _bytesToHex(List bytes) =>
      bytes.map((b) => (b as int).toRadixString(16).padLeft(2, '0')).join();

  // ── Save / link ─────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final badge = _badgeUid;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (badge == null || name.isEmpty || uid == null) {
      setState(() => _error = uid == null ? 'Not signed in yet — try again in a moment' : null);
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1) the join the Pi reads on every table tap
      await _rtdbPut('nfc_links/$badge', {
        'authUid': uid,
        'email': email,
        'linkedAt': now,
      });

      // 2) stamp the badge + contact details onto the shared user profile
      await _rtdbPatch('users/$uid/profile', {
        'nfcUid': badge,
        'name': name,
        'email': email,
        'linkedAt': now,
      });

      await TavernLink._markLinked();
      if (mounted) setState(() { _saving = false; _saved = true; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // ── UI ───────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    const cream = Color(0xFFFFE7B0);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text('Link your Tavern badge', style: TextStyle(color: cream)),
        iconTheme: const IconThemeData(color: cream),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1208),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: gold.withOpacity(_badgeUid != null ? 0.8 : 0.3)),
              ),
              child: Column(children: [
                Icon(Icons.nfc, size: 52, color: gold.withOpacity(_badgeUid != null ? 1 : 0.4)),
                const SizedBox(height: 12),
                if (_scanning)
                  const Column(children: [
                    CircularProgressIndicator(color: gold, strokeWidth: 2),
                    SizedBox(height: 10),
                    Text('Hold your badge to the back of your phone…',
                        style: TextStyle(color: cream, fontSize: 13)),
                  ])
                else if (_badgeUid != null)
                  Column(children: [
                    const Text('Badge read', style: TextStyle(color: gold, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('UID: $_badgeUid',
                        style: const TextStyle(color: Color(0x66FFE7B0), fontSize: 11, fontFamily: 'monospace')),
                    TextButton(onPressed: _startScan,
                        child: const Text('Scan a different badge', style: TextStyle(color: gold))),
                  ])
                else
                  Column(children: [
                    const Text('Tap to read your badge',
                        style: TextStyle(color: cream, fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    const Text('This binds the badge to your account so the Tavern knows it\'s you.',
                        style: TextStyle(color: Color(0x66FFE7B0), fontSize: 12), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _startScan,
                      icon: const Icon(Icons.nfc),
                      label: const Text('Read badge'),
                      style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                    ),
                  ]),
              ]),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],

            if (_badgeUid != null) ...[
              const SizedBox(height: 24),
              _field(_nameCtrl, 'Your name', 'e.g. Khalid', Icons.person_outline, cream, gold),
              const SizedBox(height: 14),
              _field(_emailCtrl, 'Email', 'you@example.com', Icons.alternate_email, cream, gold,
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 24),
              if (_saved)
                Column(children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
                    SizedBox(width: 8),
                    Text('Badge linked — welcome to the Tavern',
                        style: TextStyle(color: Color(0xFF4CAF50))),
                  ]),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Done', style: TextStyle(color: cream)),
                  ),
                ])
              else
                ElevatedButton.icon(
                  onPressed: (_saving || _nameCtrl.text.trim().isEmpty) ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.link),
                  label: Text(_saving ? 'Linking…' : 'Link badge to my account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold, foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, IconData icon,
      Color cream, Color gold, {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Color(0xFFFFE7B0)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: gold, size: 20),
        labelStyle: const TextStyle(color: Color(0x99FFE7B0)),
        hintStyle: const TextStyle(color: Color(0x44FFE7B0)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: gold.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: gold),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1208),
      ),
    );
  }
}
