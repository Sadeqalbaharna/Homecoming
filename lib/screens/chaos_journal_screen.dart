// ChaosJournalScreen
// Displays Kai's introspective journal — memories he chose to write down,
// what they made him feel, wonder, or become curious about.

import 'package:flutter/material.dart';
import '../services/core/journal_service.dart';
import '../tools/journal_backfill.dart';

// ── Emotion visuals ──────────────────────────────────────────────────────────

Color _emotionColor(JournalEmotion e) {
  switch (e) {
    case JournalEmotion.wonder:     return const Color(0xFFB8A9FF); // soft violet
    case JournalEmotion.curiosity:  return const Color(0xFF7EC8E3); // sky blue
    case JournalEmotion.warmth:     return const Color(0xFFFFB347); // amber
    case JournalEmotion.melancholy: return const Color(0xFF9EB8D9); // steel blue
    case JournalEmotion.joy:        return const Color(0xFFB8E994);  // mint green
    case JournalEmotion.unease:     return const Color(0xFFE88080); // muted red
    case JournalEmotion.longing:    return const Color(0xFFD4A5C9); // dusty rose
    case JournalEmotion.amusement:  return const Color(0xFFFFE066); // gold
  }
}

String _emotionEmoji(JournalEmotion e) {
  switch (e) {
    case JournalEmotion.wonder:     return '✦';
    case JournalEmotion.curiosity:  return '◈';
    case JournalEmotion.warmth:     return '♡';
    case JournalEmotion.melancholy: return '⌁';
    case JournalEmotion.joy:        return '◉';
    case JournalEmotion.unease:     return '⊘';
    case JournalEmotion.longing:    return '◌';
    case JournalEmotion.amusement:  return '⊕';
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ChaosJournalScreen extends StatefulWidget {
  final String personaId;
  const ChaosJournalScreen({super.key, required this.personaId});

  @override
  State<ChaosJournalScreen> createState() => _ChaosJournalScreenState();
}

class _ChaosJournalScreenState extends State<ChaosJournalScreen> {
  bool _backfilling = false;
  String _backfillStatus = '';

  Future<void> _runBackfill() async {
    setState(() {
      _backfilling = true;
      _backfillStatus = 'Reading past conversations…';
    });
    try {
      final result = await JournalBackfill.run(widget.personaId, batchSize: 3);
      if (mounted) {
        setState(() {
          _backfillStatus =
              'Done — ${result.written} entries written, ${result.skipped} skipped.';
        });
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) setState(() => _backfillStatus = '');
      }
    } catch (e) {
      if (mounted) setState(() => _backfillStatus = 'Error: $e');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0807),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFFFE7B0), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chaos Journal',
              style: TextStyle(
                color: Color(0xFFFFE7B0),
                fontSize: 18,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            Text(
              'what Kai chose to remember',
              style: TextStyle(
                color: Color(0x88FFE7B0),
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          // Clear all button
          Tooltip(
            message: 'Delete all entries',
            child: IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0x88FFE7B0), size: 20),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A150E),
                    title: const Text('Clear journal?',
                        style: TextStyle(color: Color(0xFFFFE7B0))),
                    content: const Text('All entries will be permanently deleted.',
                        style: TextStyle(color: Color(0x88FFE7B0))),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: Color(0x66FFE7B0))),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete all',
                            style: TextStyle(color: Color(0xFFE88080))),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await JournalService().deleteAllEntries(widget.personaId);
                }
              },
            ),
          ),
          // Backfill button
          Tooltip(
            message: 'Populate from past conversations',
            child: IconButton(
              icon: _backfilling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFE7B0),
                        strokeWidth: 1.5,
                      ),
                    )
                  : const Icon(Icons.history, color: Color(0x88FFE7B0), size: 20),
              onPressed: _backfilling ? null : _runBackfill,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Backfill status banner
          if (_backfillStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1A150E),
              child: Text(
                _backfillStatus,
                style: const TextStyle(color: Color(0xAAFFE7B0), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: StreamBuilder<List<JournalEntry>>(
              stream: JournalService().entriesStream(widget.personaId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFE7B0),
                      strokeWidth: 1,
                    ),
                  );
                }

                final entries = snap.data ?? [];

                if (entries.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '◌',
                          style: TextStyle(color: Color(0x44FFE7B0), fontSize: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nothing written yet.',
                          style: TextStyle(color: Color(0x66FFE7B0), fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Kai writes when something moves him.',
                          style: TextStyle(
                            color: const Color(0xFFFFE7B0).withOpacity(0.3),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Prompt backfill from empty state too
                        GestureDetector(
                          onTap: _backfilling ? null : _runBackfill,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0x33FFE7B0), width: 1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _backfilling
                                  ? 'Scanning past conversations…'
                                  : 'Search past conversations',
                              style: const TextStyle(
                                color: Color(0x66FFE7B0),
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    return Dismissible(
                      key: ValueKey(entry.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A1010),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: Color(0xFFE88080), size: 22),
                      ),
                      onDismissed: (_) => JournalService()
                          .deleteEntry(widget.personaId, entry.id),
                      child: _JournalCard(entry: entry),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _JournalCard extends StatelessWidget {
  final JournalEntry entry;
  const _JournalCard({required this.entry});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)   return 'just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    if (diff.inDays < 30)     return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final color = _emotionColor(entry.emotion);
    final emoji = _emotionEmoji(entry.emotion);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF130F0A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: color.withOpacity(0.15), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Emotion badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withOpacity(0.4), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: TextStyle(color: color, fontSize: 11)),
                        const SizedBox(width: 5),
                        Text(
                          entry.emotion.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _timeAgo(entry.timestamp),
                    style: const TextStyle(
                      color: Color(0x55FFE7B0),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // Journal content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Text(
                entry.content,
                style: const TextStyle(
                  color: Color(0xDDFFE7B0),
                  fontSize: 14.5,
                  height: 1.65,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            // Trigger quote
            if (entry.trigger.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 2,
                      height: 32,
                      margin: const EdgeInsets.only(right: 10, top: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '"${entry.trigger}"',
                        style: TextStyle(
                          color: const Color(0xFFFFE7B0).withOpacity(0.35),
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
