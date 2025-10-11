// lib/features/shell/ui/persona_dialog.dart
part of floating_kai;

/* =============================== PERSONA DIALOG ================================ */

class PersonaDialog extends StatefulWidget {
  final AgentState initial;
  final Future<void> Function(
          Map<String, num> pc, Map<String, num> mc, Map<String, num> ac)
      onSave;
  final bool pg13; // hide affinity/intimacy in CloneKai
  const PersonaDialog(
      {super.key, required this.initial, required this.onSave, this.pg13 = false});
  @override
  State<PersonaDialog> createState() => _PersonaDialogState();
}

class _PersonaDialogState extends State<PersonaDialog> {
  late Map<String, num> _pc; // 0..1000
  late Map<String, num> _mc; // 0..100
  late Map<String, num> _ac; // intimacy/physicality 0..100

  @override
  void initState() {
    super.initState();
    _pc = widget.initial.personalityCurrent
        .map((k, v) => MapEntry(k, (num.tryParse(v.toString()) ?? 0)));
    _mc = widget.initial.moodCurrent
        .map((k, v) => MapEntry(k, (num.tryParse(v.toString()) ?? 0)));
    final aff = widget.initial.affinityCurrent;
    _ac = {
      'intimacy': num.tryParse((aff['intimacy'] ?? 50).toString()) ?? 50,
      'physicality': num.tryParse((aff['physicality'] ?? 50).toString()) ?? 50,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF1F1A15);
    final stroke = const Color(0xFFFFE7B0);
    final faint = const Color(0xFFFFE7B0).withOpacity(0.12);

    Widget sliderRow({
      required String title,
      required double max,
      required num value,
      required ValueChanged<double> onChanged,
      String? label,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(color: Colors.white70)),
            if (label != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: faint,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: stroke.withOpacity(0.6), width: 1),
                ),
                child:
                    Text(label, style: const TextStyle(color: Colors.white)),
              ),
            ],
            const Spacer(),
            Text('${value.round()}/${max.toInt()}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          Slider(
            value: value.toDouble().clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
            activeColor: stroke,
            inactiveColor: Colors.white24,
          ),
        ],
      );
    }

    final labels = widget.initial.labels ?? {};
    final pl = (labels['personality_labels'] ?? {}) as Map? ?? {};
    final ml = (labels['mood_labels'] ?? {}) as Map? ?? {};

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: stroke, width: 2),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Kai — Persona',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (widget.initial.mbti != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: stroke, width: 1.2),
                          borderRadius: BorderRadius.circular(12),
                          color: faint,
                        ),
                        child: Text(widget.initial.mbti!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Fetch memory slices',
                      child: IgnorePointer(
                        ignoring: true,
                        child: IconButton(
                          icon: const Icon(Icons.memory, color: Colors.amber),
                          onPressed: () {},
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Init persona from sliders',
                      child: IgnorePointer(
                        ignoring: true,
                        child: IconButton(
                          icon: const Icon(Icons.upload_file,
                              color: Colors.lightBlueAccent),
                          onPressed: () {},
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Patch a small note',
                      child: IgnorePointer(
                        ignoring: true,
                        child: IconButton(
                          icon: const Icon(Icons.edit_note,
                              color: Colors.orangeAccent),
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if ((widget.initial.summary ?? '').isNotEmpty) ...[
                  Text(widget.initial.summary!,
                      style: const TextStyle(
                          color: Colors.white70, height: 1.25)),
                  const SizedBox(height: 12),
                ],

                _CardBox(
                  title: 'Personality',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sliderRow(
                          title: 'Extraversion',
                          max: 1000,
                          value: _pc['extraversion'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['extraversion'] = v),
                          label: (pl['extraversion'] ?? '—').toString()),
                      sliderRow(
                          title: 'Intuition',
                          max: 1000,
                          value: _pc['intuition'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['intuition'] = v),
                          label: (pl['intuition'] ?? '—').toString()),
                      sliderRow(
                          title: 'Feeling',
                          max: 1000,
                          value: _pc['feeling'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['feeling'] = v),
                          label: (pl['feeling'] ?? '—').toString()),
                      sliderRow(
                          title: 'Perceiving',
                          max: 1000,
                          value: _pc['perceiving'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _pc['perceiving'] = v),
                          label: (pl['perceiving'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _CardBox(
                  title: 'Mood',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sliderRow(
                          title: 'Valence',
                          max: 100,
                          value: _mc['valence'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['valence'] = v),
                          label: (ml['valence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Energy',
                          max: 100,
                          value: _mc['energy'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['energy'] = v),
                          label: (ml['energy'] ?? '—').toString()),
                      sliderRow(
                          title: 'Warmth',
                          max: 100,
                          value: _mc['warmth'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['warmth'] = v),
                          label: (ml['warmth'] ?? '—').toString()),
                      sliderRow(
                          title: 'Confidence',
                          max: 100,
                          value: _mc['confidence'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['confidence'] = v),
                          label: (ml['confidence'] ?? '—').toString()),
                      sliderRow(
                          title: 'Playfulness',
                          max: 100,
                          value: _mc['playfulness'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['playfulness'] = v),
                          label: (ml['playfulness'] ?? '—').toString()),
                      sliderRow(
                          title: 'Focus',
                          max: 100,
                          value: _mc['focus'] ?? 0,
                          onChanged: (v) =>
                              setState(() => _mc['focus'] = v),
                          label: (ml['focus'] ?? '—').toString()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (!widget.pg13)
                  _CardBox(
                    title: 'Affinity',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sliderRow(
                            title: 'Intimacy',
                            max: 100,
                            value: _ac['intimacy'] ?? 50,
                            onChanged: (v) =>
                                setState(() => _ac['intimacy'] = v)),
                        sliderRow(
                            title: 'Physicality',
                            max: 100,
                            value: _ac['physicality'] ?? 50,
                            onChanged: (v) =>
                                setState(() => _ac['physicality'] = v)),
                      ],
                    ),
                  ),
                if (!widget.pg13) const SizedBox(height: 12),

                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await widget.onSave(_pc, _mc, _ac);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Saved to Homecoming DB')));
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Save failed: $e')));
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                      style: TextButton.styleFrom(foregroundColor: stroke),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                          foregroundColor: stroke,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      icon: const Icon(Icons.check),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardBox extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardBox({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final stroke = const Color(0xFFFFE7B0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2119),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stroke.withOpacity(0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
