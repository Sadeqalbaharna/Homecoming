// API Key Setup Screen - First-time configuration

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/core/secure_storage_service.dart';
import 'services/ai/ai_config.dart';

/// Screen for setting up API keys on first launch
class ApiKeySetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const ApiKeySetupScreen({super.key, required this.onComplete});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final _secureStorage = SecureStorageService();
  final _openaiController = TextEditingController();
  final _elevenlabsController = TextEditingController();
  final _voiceIdController = TextEditingController();
  final _anthropicController = TextEditingController();

  bool _saving = false;
  String? _error;
  bool _showOpenAI = false;
  bool _showElevenLabs = false;
  bool _showAnthropic = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKeys();
  }

  Future<void> _loadExistingKeys() async {
    final openai = await _secureStorage.getOpenAIKey();
    final elevenlabs = await _secureStorage.getElevenLabsKey();
    final anthropic = await _secureStorage.getAnthropicKey();
    final prefs = await SharedPreferences.getInstance();
    final voiceId = prefs.getString('selected_voice_id') ?? '';

    if (openai != null && openai.isNotEmpty) {
      _openaiController.text = openai;
    }
    if (elevenlabs != null && elevenlabs.isNotEmpty) {
      _elevenlabsController.text = elevenlabs;
    }
    if (anthropic != null && anthropic.isNotEmpty) {
      _anthropicController.text = anthropic;
    }
    if (voiceId.isNotEmpty) {
      _voiceIdController.text = voiceId;
    }
  }

  Future<void> _saveKeys() async {
    final openaiKey = _openaiController.text.trim();
    
    if (openaiKey.isEmpty) {
      setState(() => _error = 'OpenAI API key is required');
      return;
    }
    
    if (!openaiKey.startsWith('sk-')) {
      setState(() => _error = 'OpenAI API key should start with "sk-"');
      return;
    }
    
    setState(() {
      _saving = true;
      _error = null;
    });
    
    try {
      await _secureStorage.setOpenAIKey(openaiKey);
      
      final elevenlabsKey = _elevenlabsController.text.trim();
      if (elevenlabsKey.isNotEmpty) {
        await _secureStorage.setElevenLabsKey(elevenlabsKey);
      }

      final anthropicKey = _anthropicController.text.trim();
      if (anthropicKey.isNotEmpty) {
        await _secureStorage.setAnthropicKey(anthropicKey);
      }


      final voiceId = _voiceIdController.text.trim();
      if (voiceId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_voice_id', voiceId);
      }

      AIConfig.clearCache();
      widget.onComplete();
    } catch (e) {
      setState(() => _error = 'Failed to save keys: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _openaiController.dispose();
    _elevenlabsController.dispose();
    _voiceIdController.dispose();
    _anthropicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              
              // Header
              const Icon(
                Icons.key,
                size: 64,
                color: Color(0xFFFFE7B0),
              ),
              const SizedBox(height: 24),
              const Text(
                'API Key Setup',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your keys are encrypted and stored securely on your device using Android Keystore',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // OpenAI API Key (Required)
              const Text(
                'OpenAI API Key *',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _openaiController,
                obscureText: !_showOpenAI,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'sk-...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showOpenAI ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _showOpenAI = !_showOpenAI),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Required for chat and voice input (Whisper)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // ElevenLabs API Key (Optional)
              const Text(
                'ElevenLabs API Key (Optional)',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _elevenlabsController,
                obscureText: !_showElevenLabs,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Leave empty to skip voice synthesis',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showElevenLabs ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _showElevenLabs = !_showElevenLabs),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'For text-to-speech voice responses',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 24),

              // ElevenLabs Voice ID
              const Text(
                'ElevenLabs Voice ID (Optional)',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _voiceIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. 21m00Tcm4TlvDq8ikWAM',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Find your Voice ID at elevenlabs.io → Voices → click a voice → copy its ID',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 24),

              // Anthropic API Key (for Opus personality drift)
              const Text(
                'Anthropic API Key (Optional)',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _anthropicController,
                obscureText: !_showAnthropic,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'sk-ant-...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showAnthropic ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _showAnthropic = !_showAnthropic),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Powers deep personality drift analysis using Claude Opus. Get one at console.anthropic.com',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),

              const SizedBox(height: 24),

              // Sherpa-ONNX wake word info (no key needed)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2ECC71).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.mic, color: Color(0xFF2ECC71), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '"Hey Kai" — Built-in, No Key Required',
                            style: TextStyle(
                              color: Color(0xFF2ECC71),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Wake word detection runs on-device using sherpa-onnx. '
                            'Enable it in Settings → Voice Controls. '
                            'The model (~11 MB) downloads automatically on first use.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              // Save button
              ElevatedButton(
                onPressed: _saving ? null : _saveKeys,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE7B0),
                  foregroundColor: const Color(0xFF0D0A07),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0D0A07),
                        ),
                      )
                    : const Text(
                        'Save & Continue',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              
              const SizedBox(height: 24),
              
              // Help links
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                    text: 'https://platform.openai.com/api-keys',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Get OpenAI API Key'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFE7B0),
                ),
              ),
              
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                    text: 'https://elevenlabs.io/app/settings/api-keys',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Get ElevenLabs API Key'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFE7B0),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Security note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.security,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your API keys are encrypted using Android Keystore and never leave your device',
                        style: TextStyle(
                          color: Colors.blue.shade200,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

