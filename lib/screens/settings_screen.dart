/// Settings Screen
/// Configure app behavior including proactive AI and voice activation
library;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai/proactive_service.dart';
import '../services/ai/ai_config.dart';
import '../services/ai/local_llm_service.dart';
import '../services/core/code_workspace_service.dart';
import 'kai_desktop_shell.dart';
import '../services/voice/voice_activation_service.dart';
import '../widgets/voice_setup_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProactiveService _proactive = ProactiveService();
  final VoiceActivationService _voiceActivation = VoiceActivationService();
  bool _proactiveEnabled = true;
  bool _voiceActivationEnabled = false;
  bool _ttsEnabled = false;
  bool _isLoading = true;

  // Local brain (Ollama)
  final _localEndpointCtrl = TextEditingController();
  // 'unchecked' | 'testing' | 'scanning' | 'ok' | 'error'
  String _localStatus = 'unchecked';
  List<String> _localModels = [];
  String _localStatusMessage = '';

  // Code workspace (engineer mode)
  String? _workspaceRoot;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _localEndpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEndpoint = await AIConfig.getLocalEndpoint();
    await CodeWorkspaceService.instance.load();
    setState(() {
      _proactiveEnabled = prefs.getBool('proactive_enabled') ?? true;
      _voiceActivationEnabled = prefs.getBool('voice_activation_enabled') ?? true;
      _ttsEnabled = prefs.getBool('tts_enabled') ?? false;
      _localEndpointCtrl.text = savedEndpoint ?? '';
      _localStatus = savedEndpoint != null ? 'ok' : 'unchecked';
      _workspaceRoot = CodeWorkspaceService.instance.root;
      _isLoading = false;
    });
  }

  Future<void> _testLocalEndpoint() async {
    final url = _localEndpointCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _localStatus = 'testing'; _localModels = []; _localStatusMessage = 'Connecting…'; });
    final models = await LocalLLMService().listModels(url);
    if (!mounted) return;
    if (models != null) {
      await AIConfig.setLocalEndpoint(url);
      setState(() {
        _localStatus = 'ok';
        _localModels = models;
        _localStatusMessage = models.isNotEmpty
            ? 'Connected — ${models.join(", ")}'
            : 'Connected (no models listed)';
      });
    } else {
      setState(() {
        _localStatus = 'error';
        _localStatusMessage = 'Unreachable — check IP, port, and that Ollama is running';
      });
    }
  }

  Future<void> _autoDiscover() async {
    setState(() {
      _localStatus = 'scanning';
      _localModels = [];
      _localStatusMessage = 'Scanning local network…';
    });

    final found = await LocalLLMService().discoverOllama(
      onProgress: (msg) {
        if (mounted) setState(() => _localStatusMessage = msg);
      },
    );

    if (!mounted) return;
    if (found != null) {
      final models = await LocalLLMService().listModels(found) ?? [];
      setState(() {
        _localEndpointCtrl.text = found;
        _localStatus = 'ok';
        _localModels = models;
        _localStatusMessage = models.isNotEmpty
            ? 'Found at $found — ${models.join(", ")}'
            : 'Found at $found';
      });
    } else {
      setState(() {
        _localStatus = 'error';
        _localStatusMessage = 'Not found — make sure Ollama is running:\n'
            'OLLAMA_HOST=0.0.0.0 ollama serve';
      });
    }
  }

  Future<void> _clearLocalEndpoint() async {
    await AIConfig.setLocalEndpoint(null);
    if (!mounted) return;
    setState(() {
      _localEndpointCtrl.clear();
      _localStatus = 'unchecked';
      _localModels = [];
      _localStatusMessage = '';
    });
  }

  Future<void> _toggleProactive(bool value) async {
    setState(() {
      _proactiveEnabled = value;
    });
    await _proactive.setEnabled(value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? '✨ Kai will now reach out proactively!'
              : '🔕 Kai will only respond when you initiate',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleTts(bool value) async {
    setState(() => _ttsEnabled = value);
    await AIConfig.setTtsEnabled(value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? '🔊 Kai will speak replies again'
              : '🔇 Kai will stay text-only'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleVoiceActivation(bool value) async {
    setState(() {
      _voiceActivationEnabled = value;
    });
    
    if (value) {
      final started = await _voiceActivation.start();
      if (!started && mounted) {
        setState(() {
          _voiceActivationEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to start voice activation. Check microphone permissions.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    } else {
      await _voiceActivation.stop();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? '🎤 "Hey Kai" voice activation enabled!'
              : '🔕 Voice activation disabled',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          '⚙️ Settings',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFE7B0),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionTitle('🎤 Voice Controls'),
                const SizedBox(height: 8),
                _buildVoiceActivationToggle(),
                const SizedBox(height: 12),
                _buildTtsToggle(),
                const SizedBox(height: 12),
                _buildVoiceTrainingOption(),
                const SizedBox(height: 24),
                
                _buildSectionTitle('🤖 AI Behavior'),
                const SizedBox(height: 8),
                _buildProactiveToggle(),
                const SizedBox(height: 24),

                _buildSectionTitle('🧠 Local Brain (Ollama / Qwen)'),
                const SizedBox(height: 8),
                _buildLocalBrainSection(),
                const SizedBox(height: 24),

                _buildSectionTitle('🛠 Code Workspace (Engineer Mode)'),
                const SizedBox(height: 8),
                _buildCodeWorkspaceSection(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const KaiDesktopShell()),
                    ),
                    icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                    label: const Text('Open Desktop Shell'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16213E),
                      foregroundColor: const Color(0xFFFFE7B0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionTitle('📊 Stats'),
                const SizedBox(height: 8),
                _buildProactiveStats(),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFFFE7B0),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildCodeWorkspaceSection() {
    final has = _workspaceRoot != null && _workspaceRoot!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Repository folder',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Lets the Claude hemisphere read & search this repo (read-only) when '
            'you ask about code.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(has ? Icons.folder_open : Icons.folder_off,
                    color: has ? const Color(0xFFFFE7B0) : Colors.white38,
                    size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _workspaceRoot! : 'No folder selected',
                    style: TextStyle(
                        color: has ? Colors.white : Colors.white38,
                        fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickWorkspace,
                  icon: const Icon(Icons.drive_folder_upload, size: 18),
                  label: Text(has ? 'Change folder' : 'Choose folder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE7B0),
                    foregroundColor: const Color(0xFF16213E),
                  ),
                ),
              ),
              if (has) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _clearWorkspace,
                  child: const Text('Clear',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Read-only — Kai can read, search and list files, but never write or '
            'run anything.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _pickWorkspace() async {
    try {
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Choose a code folder for Kai');
      if (dir != null && dir.isNotEmpty) {
        await CodeWorkspaceService.instance.setRoot(dir);
        if (mounted) setState(() => _workspaceRoot = dir);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the folder picker: $e')),
        );
      }
    }
  }

  Future<void> _clearWorkspace() async {
    await CodeWorkspaceService.instance.setRoot(null);
    if (mounted) setState(() => _workspaceRoot = null);
  }

  Widget _buildVoiceActivationToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"Hey Kai" Voice Activation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Always listen for "Hey Kai" to start conversations',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _voiceActivationEnabled,
                onChanged: _toggleVoiceActivation,
                activeThumbColor: const Color(0xFFFFE7B0),
              ),
            ],
          ),
          if (_voiceActivationEnabled) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mic, color: Color(0xFFFFE7B0), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'How it works:',
                        style: TextStyle(
                          color: Color(0xFFFFE7B0),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Say "Hey Kai" to activate hands-free\n'
                    '• On-device — no API key, no internet needed\n'
                    '• Model (~11 MB) downloads once on first enable',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.battery_5_bar, color: Colors.greenAccent, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Low power — sherpa-onnx runs on-device at ~2% CPU',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProactiveToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proactive Conversations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Kai will initiate conversations throughout the day',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _proactiveEnabled,
                onChanged: _toggleProactive,
                activeThumbColor: const Color(0xFFFFE7B0),
              ),
            ],
          ),
          if (_proactiveEnabled) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            _buildTriggerInfo('☀️', 'Morning greeting', '7-9 AM'),
            _buildTriggerInfo('🍽️', 'Lunch reminder', '12-1 PM'),
            _buildTriggerInfo('🌙', 'Evening recap', '8-10 PM'),
            _buildTriggerInfo('💭', 'Check-ins', 'When idle 4+ hours'),
            _buildTriggerInfo('💪', 'Break reminders', 'Every 2 hours'),
            _buildTriggerInfo('🤓', 'Curiosity facts', 'Random'),
          ],
        ],
      ),
    );
  }

  Widget _buildTriggerInfo(String emoji, String title, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBrainSection() {
    final isOk       = _localStatus == 'ok';
    final isError    = _localStatus == 'error';
    final isBusy     = _localStatus == 'testing' || _localStatus == 'scanning';
    final isScanning = _localStatus == 'scanning';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offload brain work to Qwen running locally on your laptop via Ollama. '
            'Extraction, consolidation, and DMN wandering run locally — zero '
            'token cost. Kai\'s actual replies always stay on cloud.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),

          // ── Endpoint field ──────────────────────────────────────────────
          TextField(
            controller: _localEndpointCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.42:11434',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0D0A07),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isOk
                      ? Colors.greenAccent.withOpacity(0.5)
                      : isError
                          ? Colors.redAccent.withOpacity(0.5)
                          : Colors.white12,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFFFE7B0), width: 1),
              ),
            ),
            onSubmitted: (_) => _testLocalEndpoint(),
          ),
          const SizedBox(height: 10),

          // ── Buttons row ─────────────────────────────────────────────────
          Row(
            children: [
              // Auto-discover button (primary action)
              Expanded(
                child: GestureDetector(
                  onTap: isBusy ? null : _autoDiscover,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE7B0).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFFE7B0).withOpacity(0.45)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isScanning)
                          const SizedBox(
                            width: 13, height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFFFFE7B0)),
                          )
                        else
                          const Icon(Icons.wifi_find_rounded,
                              color: Color(0xFFFFE7B0), size: 15),
                        const SizedBox(width: 7),
                        Text(
                          isScanning ? 'Scanning…' : 'Auto-discover',
                          style: const TextStyle(
                              color: Color(0xFFFFE7B0), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Manual Test button (if they typed an IP)
              GestureDetector(
                onTap: isBusy ? null : _testLocalEndpoint,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: isBusy && !isScanning
                      ? const SizedBox(
                          width: 13, height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54))
                      : const Text('Test',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
            ],
          ),

          // ── Status message ──────────────────────────────────────────────
          if (_localStatusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isBusy)
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 8),
                    child: Icon(
                      isOk
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: isOk ? Colors.greenAccent : Colors.redAccent,
                      size: 15,
                    ),
                  ),
                Expanded(
                  child: Text(
                    _localStatusMessage,
                    style: TextStyle(
                      color: isOk
                          ? Colors.greenAccent
                          : isError
                              ? Colors.redAccent
                              : Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                if (isOk)
                  GestureDetector(
                    onTap: _clearLocalEndpoint,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text('Clear',
                          style:
                              TextStyle(color: Colors.white30, fontSize: 11)),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Setup hint ──────────────────────────────────────────────────
          const Text(
            'Laptop setup (one-time):\n'
            '  ollama pull qwen3:8b\n'
            '  OLLAMA_HOST=0.0.0.0 ollama serve\n\n'
            'Then tap Auto-discover — Kai finds the IP automatically.',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProactiveStats() {
    return FutureBuilder<Map<String, int>>(
      future: _getProactiveStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFFE7B0),
            ),
          );
        }

        final stats = snapshot.data!;
        final total = stats.values.fold(0, (sum, count) => sum + count);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total proactive messages: $total',
                style: const TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...stats.entries.map((entry) {
                final name = entry.key
                    .replaceAll('proactive_', '')
                    .replaceAll('_count', '')
                    .replaceAll('_', ' ');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTrainingOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2C4C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFE7B0).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFE7B0).withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.record_voice_over,
              color: Color(0xFFFFE7B0),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Training',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Train Kai to recognize your voice',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _openVoiceTraining,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7B0).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFE7B0),
                ),
              ),
              child: const Text(
                'Setup',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openVoiceTraining() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const VoiceSetupDialog(),
    );
  }

  Future<Map<String, int>> _getProactiveStats() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = <String, int>{};
    
    for (var key in prefs.getKeys()) {
      if (key.startsWith('proactive_') && key.endsWith('_count')) {
        stats[key] = prefs.getInt(key) ?? 0;
      }
    }
    
    return stats;
  }
}
