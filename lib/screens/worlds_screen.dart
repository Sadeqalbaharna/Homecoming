// WorldsScreen — Kai's top-down map of the projects ("worlds") he oversees.
//
// Reads the /projects registry (ProjectRegistryService) and lists every world
// with its status, summary, and where its code/data live. Tap + to add a world;
// tap a world to edit it. This is the interface surface of the "god brain".
library;

import 'package:flutter/material.dart';

import '../services/core/kai_project_service.dart';
import '../services/core/kai_work_request_service.dart';
import '../services/core/project_registry_service.dart';
import '../widgets/kai_project_card.dart';
import '../widgets/kai_state_scorecard_card.dart';

// Homecoming palette
const _stroke = Color(0xFFFFE7B0); // warm gold
const _bg = Color(0xFF0B0B0F);
const _card = Color(0x22FFFFFF);

class WorldsScreen extends StatelessWidget {
  final String personaId;

  const WorldsScreen({
    super.key,
    required this.personaId,
  });

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
          final worlds = snap.data ?? const <ProjectEntry>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _KaiGrowthSection(personaId: personaId),
              const SizedBox(height: 18),
              const _SectionHeader(
                eyebrow: 'WORLDS REGISTRY',
                title: 'Projects Kai oversees',
                body:
                    'Homecoming, Tavern, Lionheart, and any other world with code or lore worth tracking.',
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: _stroke),
                  ),
                )
              else if (snap.hasError)
                _Message(
                  icon: Icons.lock_outline,
                  title: "Couldn't read the registry",
                  body:
                      'This is usually a permissions issue — make sure you are signed in. '
                      '(${snap.error})',
                )
              else if (worlds.isEmpty)
                const _Message(
                  icon: Icons.public_off,
                  title: 'No worlds yet',
                  body:
                      'Tap "Add world" to register your first project. Kai will keep '
                      'a top-down view of every world you add here.',
                )
              else
                for (final world in worlds) ...[
                  _WorldCard(
                    entry: world,
                    onTap: () => _openEditor(context, registry, world),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
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

class _KaiGrowthSection extends StatelessWidget {
  final String personaId;

  const _KaiGrowthSection({required this.personaId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          eyebrow: 'KAI GROWTH',
          title: 'Brain cockpit',
          body:
              'The live state of Kai getting smarter — project layers, replay scorecard, and desktop work queue.',
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: KaiProjectCard(
            personaId: personaId,
            projectId: KaiProjectService.smarterId,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: KaiProjectCard(
            personaId: personaId,
            projectId: KaiProjectService.sentienceId,
          ),
        ),
        const SizedBox(height: 12),
        const KaiStateScorecardCard(),
        const SizedBox(height: 12),
        _DesktopQueueCard(personaId: personaId),
      ],
    );
  }
}

class _DesktopQueueCard extends StatelessWidget {
  final String personaId;

  const _DesktopQueueCard({required this.personaId});

  @override
  Widget build(BuildContext context) {
    final service = KaiWorkRequestService.instance;
    return StreamBuilder<List<KaiWorkRequest>>(
      stream: service.watchRequests(personaId),
      builder: (context, snap) {
        final all = snap.data ?? const <KaiWorkRequest>[];
        final open = all.where((r) => r.isOpen).take(3).toList();
        final latest = open.isNotEmpty ? open : all.take(2).toList();
        final openCount = all.where((r) => r.isOpen).length;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _stroke.withOpacity(0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.45),
                      border: Border.all(color: _stroke.withOpacity(0.45)),
                    ),
                    child: const Icon(Icons.computer_outlined,
                        color: _stroke, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Desktop work queue',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            _QueueCountChip(count: openCount),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mobile can queue work here; desktop-Kai picks it up with real tools and streams receipts back.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.58),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (snap.connectionState == ConnectionState.waiting) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  minHeight: 2,
                  color: _stroke.withOpacity(0.7),
                  backgroundColor: Colors.white.withOpacity(0.08),
                ),
              ] else if (snap.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  'Could not read queue: ${snap.error}',
                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11.5),
                ),
              ] else if (latest.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'No queued desktop work. Honest empty state. Beautifully boring.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                for (final request in latest) ...[
                  _WorkRequestRow(request: request),
                  if (request != latest.last) const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QueueCountChip extends StatelessWidget {
  final int count;

  const _QueueCountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count == 0 ? 'idle' : '$count open';
    final color = count == 0 ? Colors.white.withOpacity(0.46) : _stroke;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WorkRequestRow extends StatelessWidget {
  final KaiWorkRequest request;

  const _WorkRequestRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      KaiWorkRequestStatus.queued => _stroke,
      KaiWorkRequestStatus.running => const Color(0xFF8FD7FF),
      KaiWorkRequestStatus.done => const Color(0xFF8FE3A0),
      KaiWorkRequestStatus.failed => const Color(0xFFFF8A80),
      KaiWorkRequestStatus.cancelled => Colors.white.withOpacity(0.45),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(request.status), color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitleFor(request),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.48),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            request.status.name,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(KaiWorkRequestStatus status) {
    return switch (status) {
      KaiWorkRequestStatus.queued => Icons.schedule,
      KaiWorkRequestStatus.running => Icons.bolt,
      KaiWorkRequestStatus.done => Icons.check_circle_outline,
      KaiWorkRequestStatus.failed => Icons.error_outline,
      KaiWorkRequestStatus.cancelled => Icons.cancel_outlined,
    };
  }

  static String _subtitleFor(KaiWorkRequest request) {
    if ((request.summary ?? '').isNotEmpty) return request.summary!;
    if ((request.error ?? '').isNotEmpty) return request.error!;
    if ((request.claimedBy ?? '').isNotEmpty) {
      return 'claimed by ${request.claimedBy}';
    }
    return request.requiresDesktop
        ? 'waiting for desktop body'
        : 'available to any body';
  }
}


class _SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String body;

  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: TextStyle(
            color: _stroke.withOpacity(0.72),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(
            color: Colors.white.withOpacity(0.58),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
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
