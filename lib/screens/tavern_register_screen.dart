// tavern_register_screen.dart
//
// Staff registration screen for unlinked NFC coins (guests without the Kingdom app).
// Scan any NFC coin → read its UID → fill in customer details → save to RTDB.
//
// RTDB path (kingdom-ac44f): tavern_guests/{nfc_uid}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';

const _rtdb = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app';

class TavernRegisterScreen extends StatefulWidget {
  const TavernRegisterScreen({super.key});

  @override
  State<TavernRegisterScreen> createState() => _TavernRegisterScreenState();
}

class _TavernRegisterScreenState extends State<TavernRegisterScreen> {
  String? _scannedUid;
  bool _scanning = false;
  bool _saving   = false;
  bool _saved    = false;
  String? _error;

  final _nameCtrl  = TextEditingController();
  final _usualCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool  _isVip     = false;

  // ── RTDB helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _rtdbGet(String path) async {
    final resp = await http
        .get(Uri.parse('$_rtdb/$path.json'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode == 200 && resp.body != 'null') {
      return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    }
    return null;
  }

  Future<void> _rtdbPut(String path, Map<String, dynamic> data) async {
    await http.put(
      Uri.parse('$_rtdb/$path.json'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
  }

  Future<void> _rtdbPatch(String path, Map<String, dynamic> data) async {
    await http.patch(
      Uri.parse('$_rtdb/$path.json'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
  }

  // ── NFC ───────────────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      setState(() => _error = 'NFC not available on this device');
      return;
    }

    setState(() { _scanning = true; _error = null; _saved = false; });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final uid = _extractUid(tag);
        await NfcManager.instance.stopSession();

        if (uid == null) {
          setState(() { _scanning = false; _error = 'Could not read UID from this tag'; });
          return;
        }

        // Check if already registered in RTDB
        final existing = await _rtdbGet('tavern_guests/$uid');

        setState(() {
          _scanning   = false;
          _scannedUid = uid;
          if (existing != null) {
            _nameCtrl.text  = existing['name']       as String? ?? '';
            _usualCtrl.text = existing['usualOrder']  as String? ?? '';
            _notesCtrl.text = existing['notes']       as String? ?? '';
            _isVip          = existing['isVIP']       as bool?   ?? false;
          } else {
            _nameCtrl.clear();
            _usualCtrl.clear();
            _notesCtrl.clear();
            _isVip = false;
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
      bytes.map((b) => (b as int).toRadixString(16).padLeft(2, '0')).join('');

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final uid  = _scannedUid;
    final name = _nameCtrl.text.trim();
    if (uid == null || name.isEmpty) return;

    setState(() { _saving = true; _error = null; });

    try {
      final nowMs    = DateTime.now().millisecondsSinceEpoch;
      final existing = await _rtdbGet('tavern_guests/$uid');

      if (existing != null) {
        await _rtdbPatch('tavern_guests/$uid', {
          'name':       name,
          'usualOrder': _usualCtrl.text.trim(),
          'notes':      _notesCtrl.text.trim(),
          'isVIP':      _isVip,
          'updatedAt':  nowMs,
        });
      } else {
        await _rtdbPut('tavern_guests/$uid', {
          'name':       name,
          'visitCount': 0,
          'firstVisit': nowMs,
          'lastVisit':  nowMs,
          'usualOrder': _usualCtrl.text.trim(),
          'notes':      _notesCtrl.text.trim(),
          'isVIP':      _isVip,
        });
      }

      setState(() { _saving = false; _saved = true; });
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    _nameCtrl.dispose();
    _usualCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text('Register NFC Coin',
            style: TextStyle(color: Color(0xFFFFE7B0))),
        iconTheme: const IconThemeData(color: Color(0xFFFFE7B0)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScanCard(uid: _scannedUid, scanning: _scanning, onScan: _startScan),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],

            if (_scannedUid != null) ...[
              const SizedBox(height: 28),
              _TavernField(controller: _nameCtrl,  label: 'Customer name',  hint: 'e.g. Khalid',                     icon: Icons.person_outline),
              const SizedBox(height: 14),
              _TavernField(controller: _usualCtrl, label: 'Usual order',    hint: 'e.g. Dark ale, lamb shank',        icon: Icons.local_bar_outlined),
              const SizedBox(height: 14),
              _TavernField(controller: _notesCtrl, label: 'Notes for Kai',  hint: 'e.g. Prefers a quiet corner table', icon: Icons.notes, maxLines: 3),
              const SizedBox(height: 14),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1208),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
                ),
                child: SwitchListTile(
                  value: _isVip,
                  onChanged: (v) => setState(() => _isVip = v),
                  title: const Text('VIP guest', style: TextStyle(color: Color(0xFFFFE7B0))),
                  subtitle: const Text('Kai will treat them with extra care',
                      style: TextStyle(color: Color(0x66FFE7B0), fontSize: 12)),
                  activeColor: const Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(height: 28),

              if (_saved)
                const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
                      SizedBox(width: 8),
                      Text('Saved — Kai knows this guest',
                          style: TextStyle(color: Color(0xFF4CAF50))),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: (_saving || _nameCtrl.text.trim().isEmpty) ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save to Tavern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),

              if (_saved) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => setState(() { _scannedUid = null; _saved = false; }),
                  icon: const Icon(Icons.nfc, color: Color(0xFFFFE7B0)),
                  label: const Text('Register another coin',
                      style: TextStyle(color: Color(0xFFFFE7B0))),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ScanCard extends StatelessWidget {
  final String? uid;
  final bool scanning;
  final VoidCallback onScan;
  const _ScanCard({required this.uid, required this.scanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1208),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: uid != null
              ? const Color(0xFFD4AF37).withOpacity(0.8)
              : const Color(0xFFD4AF37).withOpacity(0.3),
        ),
      ),
      child: Column(children: [
        Icon(Icons.nfc, size: 52,
            color: uid != null
                ? const Color(0xFFD4AF37)
                : const Color(0xFFD4AF37).withOpacity(0.4)),
        const SizedBox(height: 12),
        if (scanning)
          const Column(children: [
            CircularProgressIndicator(color: Color(0xFFD4AF37), strokeWidth: 2),
            SizedBox(height: 10),
            Text('Hold coin to the back of your phone…',
                style: TextStyle(color: Color(0xFFFFE7B0), fontSize: 13)),
          ])
        else if (uid != null)
          Column(children: [
            const Text('Coin scanned',
                style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('UID: $uid',
                style: const TextStyle(color: Color(0x66FFE7B0), fontSize: 11, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onScan,
              child: const Text('Scan different coin', style: TextStyle(color: Color(0xFFD4AF37))),
            ),
          ])
        else
          Column(children: [
            const Text('Tap to scan an NFC coin',
                style: TextStyle(color: Color(0xFFFFE7B0), fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('The coin\'s UID becomes this guest\'s identity',
                style: TextStyle(color: Color(0x66FFE7B0), fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.nfc),
              label: const Text('Scan coin'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
      ]),
    );
  }
}

class _TavernField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;

  const _TavernField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFFFFE7B0)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFFD4AF37), size: 20),
        labelStyle: const TextStyle(color: Color(0x99FFE7B0)),
        hintStyle: const TextStyle(color: Color(0x44FFE7B0)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD4AF37)),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1208),
      ),
    );
  }
}
