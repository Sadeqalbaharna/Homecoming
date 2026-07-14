// WorldsScreen — Kai's top-down map of the projects ("worlds") he oversees.
//
// Reads the /projects registry (ProjectRegistryService) and lists every world
// with its status, summary, and where its code/data live. Tap + to add a world;
// tap a world to edit it. This is the interface surface of the "god brain".
library;

import 'package:flutter/material.dart';
import '../services/core/project_registry_service.dart';

// Homecoming palette
const _stroke = Color(0xFFFFE7B0); // warm gold
const _bg = Color(0xFF0B0B0F);
const _card = Color(0x22FFFFFF);

class WorldsScreen extends StatelessWidget {
  const WorldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = ProjectRegistryService();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _stroke),
        title: const Text('Worlds',
            style: TextStyle(color: _stroke, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: _stroke,
        icon: const Icon(Icons.add),
        label: const Text('Add world'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _stroke, width: 1),
        ),
        onPressed: () => _openEditor(context, registry, null),
      ),
      body: StreamBuilder<List<ProjectEntry>>(
        stream: registry.watch(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _stroke));
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.lock_outline,
              title: "Couldn't read the registry",
              body:
                  'This is usually a permissions issue — make sure you are signed in. '
                  '(${snap.error})',
            );
          }
          final worlds = snap.data ?? const [];
          if (worlds.isEmpty) {
            return const _Message(
              icon: Icons.public_off,
              title: 'No worlds yet',
              body:
                  'Tap "Add world" to register your first project. Kai will keep '
                  'a top-down view of every world you add here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: worlds.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _WorldCard(
              entry: worlds[i],
              onTap: () => _openEditor(context, registry, worlds[i]),
            ),
          );
        },
      ),
    );
  }

  void _openEditor(
    BuildContext context,
    ProjectRegistryService registry,
    ProjectEntry? existing,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WorldEditor(registry: registry, existing: existing),
    );
  }
}

class _WorldCard extends StatelessWidget {
  final ProjectEntry entry;
  final VoidCallback onTap;
  const _WorldCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final graduated = entry.status == 'graduated';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _stroke.withOpacity(0.5), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: const TextStyle(
                        color: _stroke,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusChip(graduated: graduated),
              ],
            ),
            if (entry.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.summary,
                  style: TextStyle(color: Colors.white.withOpacity(0.75))),
            ],
            if ((entry.firebase ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetaRow(icon: Icons.cloud_outlined, text: entry.firebase!),
            ],
            if ((entry.repoPath ?? '').isNotEmpty)
              _MetaRow(icon: Icons.folder_outlined, text: entry.repoPath!),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool graduated;
  const _StatusChip({required this.graduated});
  @override
  Widget build(BuildContext context) {
    final label = graduated ? 'graduated' : 'namespaced';
    final color = graduated ? const Color(0xFF8FE3A0) : _stroke;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.7), width: 1),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white.withOpacity(0.55)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Message(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _stroke.withOpacity(0.7), size: 48),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _stroke,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

// ── Editor sheet ────────────────────────────────────────────────────────────

class _WorldEditor extends StatefulWidget {
  final ProjectRegistryService registry;
  final ProjectEntry? existing;
  const _WorldEditor({required this.registry, this.existing});

  @override
  State<_WorldEditor> createState() => _WorldEditorState();
}

class _WorldEditorState extends State<_WorldEditor> {
  late final TextEditingController _name;
  late final TextEditingController _summary;
  late final TextEditingController _firebase;
  late final TextEditingController _rtdb;
  late final TextEditingController _repo;
  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _summary = TextEditingController(text: e?.summary ?? '');
    _firebase = TextEditingController(text: e?.firebase ?? '');
    _rtdb = TextEditingController(text: e?.rtdb ?? '');
    _repo = TextEditingController(text: e?.repoPath ?? '');
    _status = e?.status ?? 'namespaced';
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _firebase.dispose();
    _rtdb.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the world a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.existing?.id ?? ProjectRegistryService.keyFor(name);
      final entry = ProjectEntry(
        id: id,
        name: name,
        status: _status,
        firebase: _firebase.text.trim(),
        rtdb: _rtdb.text.trim(),
        repoPath: _repo.text.trim(),
        summary: _summary.text.trim(),
        createdAt: widget.existing?.createdAt ?? 0,
      );
      await widget.registry.upsert(entry);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    setState(() => _saving = true);
    try {
      await widget.registry.remove(e.id);
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      setState(() {
        _error = 'Could not remove: $err';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: _stroke.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(editing ? 'Edit world' : 'New world',
                style: const TextStyle(
                    color: _stroke,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _field(_name, 'Name', 'e.g. Kingdom / Tavern'),
            _field(_summary, 'Summary', 'One line about this world', lines: 2),
            const SizedBox(height: 8),
            _StatusToggle(
              status: _status,
              onChanged: (s) => setState(() => _status = s),
            ),
            const SizedBox(height: 8),
            _field(_firebase, 'Firebase project (optional)',
                'e.g. kingdom-ac44f'),
            _field(_rtdb, 'Database URL (optional)', 'https://…'),
            _field(_repo, 'Code path (optional)', r'C:\code\…'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (editing)
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFFF8A80)),
                    label: const Text('Remove',
                        style: TextStyle(color: Color(0xFFFF8A80))),
                  ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: _stroke,
                    side: const BorderSide(color: _stroke, width: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: _stroke, strokeWidth: 2))
                      : Text(editing ? 'Save' : 'Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: lines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: _stroke.withOpacity(0.9)),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _stroke.withOpacity(0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _stroke),
          ),
        ),
      ),
    );
  }
}

class _StatusToggle extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  const _StatusToggle({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget opt(String value, String label) {
      final on = status == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _stroke.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: on ? _stroke : _stroke.withOpacity(0.3), width: 1),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? _stroke : Colors.white.withOpacity(0.6),
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Row(
      children: [
        opt('namespaced', 'Namespaced'),
        opt('graduated', 'Graduated'),
      ],
    );
  }
}
