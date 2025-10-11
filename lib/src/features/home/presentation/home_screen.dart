import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../overlay/avatar_overlay.dart';
import '../../../features/voice/voice_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final LayerLink _anchor = LayerLink();
  OverlayEntry? _menuEntry;

  void _toggleMenu() {
    if (_menuEntry != null) {
      _menuEntry!.remove();
      _menuEntry = null;
      return;
    }
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _menuEntry = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleMenu, // tap outside closes
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _anchor,
              offset: const Offset(-160, -12), // position menu left of avatar
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 160),
                  child: _AvatarMenu(ref: ref, onClose: _toggleMenu),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    overlay.insert(_menuEntry!);
  }

  @override
  void dispose() {
    _menuEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Avatar anchored bottom-right
          Positioned(
            right: 24,
            bottom: 24,
            child: CompositedTransformTarget(
              link: _anchor,
              child: GestureDetector(
                onTap: _toggleMenu,
                behavior: HitTestBehavior.translucent,
                child: const AvatarOverlay(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarMenu extends StatelessWidget {
  final WidgetRef ref;
  final VoidCallback onClose;
  const _AvatarMenu({required this.ref, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final voice = ref.read(voiceServiceProvider);
    final baseUrl = const String.fromEnvironment('API_BASE_URL');
    final apiKey = const String.fromEnvironment('API_KEY');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MenuItem(
          label: 'Start recording',
          onTap: () async {
            try {
              await voice.start();
              onClose();
            } catch (e) {
              _toast(context, 'Mic error: $e');
            }
          },
        ),
        _MenuItem(
          label: 'Stop & send',
          onTap: () async {
            try {
              final bytes = await voice.stopAndSend(
                baseUrl: baseUrl.isEmpty ? null : baseUrl,
                apiKey: apiKey.isEmpty ? null : apiKey,
              );
              _toast(context, 'Got ${bytes.length} bytes');
            } catch (e) {
              _toast(context, 'Stop/send error: $e');
            } finally {
              onClose();
            }
          },
        ),
        const Divider(height: 1),
        _MenuItem(
          label: 'Settings',
          onTap: () {
            onClose();
            context.go('/settings');
          },
        ),
      ],
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MenuItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
