// lib/features/shell/ui/chat_bubble.dart
part of floating_kai;

/* ================================= COMIC BUBBLE ================================== */

class _ComicBubble extends StatelessWidget {
  final double maxWidth;
  final bool sending;
  final String? reply;
  final String? error;

  final bool devOpen;
  final Map<String, String>? devDetails;
  final VoidCallback onToggleDev;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onClose;

  final VoidCallback onPersonaTap;

  final bool autoPlay;
  final VoidCallback onToggleAutoPlay;
  final bool adaptToUser;
  final VoidCallback onToggleAdapt;
  final String modelId;
  final ValueChanged<String> onChangeModel;

  final VoidCallback onVoiceTap;
  final bool voiceLoading;
  final bool hasVoice;
  final Stream<PlayerState> playingStream;

  final String personaId;
  final bool pg13;

  const _ComicBubble({
    required this.maxWidth,
    required this.sending,
    required this.reply,
    required this.error,
    required this.devOpen,
    required this.devDetails,
    required this.onToggleDev,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.onPersonaTap,
    required this.autoPlay,
    required this.onToggleAutoPlay,
    required this.adaptToUser,
    required this.onToggleAdapt,
    required this.modelId,
    required this.onChangeModel,
    required this.onVoiceTap,
    required this.voiceLoading,
    required this.hasVoice,
    required this.playingStream,
    required this.personaId,
    required this.pg13,
  });

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF1F1A15);
    final stroke = const Color(0xFFFFE7B0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: -10,
            left: maxWidth * 0.5 - 14,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: stroke, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stroke, width: 2),
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 8, offset: Offset(0, 4), color: Colors.black26)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // header
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Tooltip(
                        message: 'Persona',
                        child: IconButton(
                          onPressed: onPersonaTap,
                          icon: const Icon(Icons.person),
                          color: stroke,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                        ),
                      ),
                      Text(
                        'Kai',
                        style: TextStyle(
                          color: pg13 ? Colors.redAccent : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: stroke,
                        ),
                        onPressed: onToggleDev,
                        child: Text(devOpen ? 'DEV ▲' : 'DEV ▼'),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        color: stroke,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 36, height: 36),
                      ),
                    ],
                  ),

                  // input row
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Ask Kai…',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Send',
                        onPressed: sending ? null : onSend,
                        icon: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        color: stroke,
                      ),
                    ],
                  ),

                  // reply + voice
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ] else if ((reply ?? '').isNotEmpty) ...[
                    const Divider(height: 14, color: Colors.white12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            reply!,
                            style: const TextStyle(
                                color: Colors.white, height: 1.25),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Voice:', style: TextStyle(color: stroke)),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ButtonStyle(
                            backgroundColor:
                                const MaterialStatePropertyAll<Color>(
                                    Colors.transparent),
                            foregroundColor:
                                MaterialStatePropertyAll<Color>(stroke),
                            side: MaterialStatePropertyAll<BorderSide>(
                              BorderSide(color: stroke, width: 1.2),
                            ),
                            padding:
                                const MaterialStatePropertyAll<EdgeInsets>(
                              EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            shape:
                                MaterialStatePropertyAll<RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            elevation:
                                const MaterialStatePropertyAll<double>(0),
                          ),
                          onPressed: voiceLoading ? null : onVoiceTap,
                          icon: voiceLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : StreamBuilder<PlayerState>(
                                  stream: playingStream,
                                  builder: (context, snap) {
                                    final playing =
                                        snap.data == PlayerState.playing;
                                    return Icon(playing
                                        ? Icons.pause
                                        : Icons.play_arrow);
                                  },
                                ),
                          label: const Text('Play/Pause'),
                        ),
                      ],
                    ),
                  ],

                  // DEV panel
                  if (devOpen && devDetails != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2119),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.6)),
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            height: 1.25),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('HTTP: ${devDetails!['status'] ?? ''}'),
                            const SizedBox(height: 4),
                            Text(
                                'Content-Type: ${devDetails!['content-type'] ?? ''}'),
                            const SizedBox(height: 4),
                            Text('Headers: ${devDetails!['headers'] ?? ''}'),
                            const SizedBox(height: 6),
                            const Text('Body snippet:'),
                            Text(devDetails!['body (first 300 chars)'] ?? ''),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
