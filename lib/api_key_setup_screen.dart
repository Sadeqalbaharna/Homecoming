// API Key Setup Screen - First-time configuration

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/core/secure_storage_service.dart';
import 'services/core/gumroad_cli_service.dart';
import 'services/ai/google_search_service.dart';
import 'services/ai/ai_config.dart';
import 'services/core/kai_secret_inventory.dart';
import 'logic/secret_registry.dart';
import 'widgets/kai_key_status_strip.dart';

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
  final _gumroadController = TextEditingController();
  final _googleKeyController = TextEditingController();
  final _googleCseController = TextEditingController();

  bool _saving = false;
  String? _error;
  bool _showOpenAI = false;
  bool _showElevenLabs = false;
  bool _showAnthropic = false;
  bool _showGumroad = false;

  /// Result of the last "Test connection" run. Never contains the token.
  String? _gumroadTestResult;
  bool _gumroadTesting = false;

  bool _showGoogle = false;
  String? _searchTestResult;
  bool _searchTesting = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKeys();
  }

  /// What was on disk when the screen opened.
  ///
  /// A save is only a ROTATION if the value actually changed. Recording one on
  /// every save would reset the clock whenever the screen is opened and closed,
  /// hiding a stale key for another ninety days — which is exactly the failure
  /// the whole panel exists to prevent. The app knows the difference, so it
  /// should not have to ask.
  final Map<String, String> _loadedValues = {};

  KaiSecretRegistry? _registry;

  Future<void> _refreshRegistry() async {
    final registry = await KaiSecretInventory.load();
    if (mounted) setState(() => _registry = registry);
  }

  /// The age line for one editable key, shown beside its field.
  ///
  /// Silent when nothing is recorded AND the field is empty: a key that has
  /// never been set does not need a rotation warning, it needs filling in.
  Widget _ageFor(String id, TextEditingController controller) {
    final reg = _registry;
    if (reg == null) return const SizedBox.shrink();
    KaiSecret? secret;
    for (final s in reg.secrets) {
      if (s.id == id) secret = s;
    }
    if (secret == null) return const SizedBox.shrink();
    if (secret.lastRotated == null && controller.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final colour = KaiKeyStatusStrip.colourFor(secret.urgency(now));
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
          const SizedBox(width: 6),
          Text(
            KaiKeyStatusStrip.ageLabel(secret, now),
            style: TextStyle(color: colour, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Future<void> _recordChangedRotations(Map<String, String> now) async {
    final at = DateTime.now();
    for (final entry in now.entries) {
      if (!KaiSecretInventory.editableIds.contains(entry.key)) continue;
      if (entry.value.isEmpty) continue;
      if (_loadedValues[entry.key] == entry.value) continue;
      await KaiSecretInventory.recordRotation(entry.key, at);
      _loadedValues[entry.key] = entry.value;
    }
    await _refreshRegistry();
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
    final gumroad = await _secureStorage.getGumroadToken();
    if (gumroad != null && gumroad.isNotEmpty) {
      _gumroadController.text = gumroad;
    }
    final googleKey = await _secureStorage.getGoogleKey();
    if (googleKey != null && googleKey.isNotEmpty) {
      _googleKeyController.text = googleKey;
    }
    final cse = await _secureStorage.getGoogleCseId();
    if (cse != null && cse.isNotEmpty) {
      _googleCseController.text = cse;
    }
    if (voiceId.isNotEmpty) {
      _voiceIdController.text = voiceId;
    }

    _loadedValues
      ..['openai'] = _openaiController.text.trim()
      ..['elevenlabs'] = _elevenlabsController.text.trim()
      ..['anthropic'] = _anthropicController.text.trim()
      ..['gumroad'] = _gumroadController.text.trim()
      ..['google_api'] = _googleKeyController.text.trim();
    await _refreshRegistry();
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

      final gumroadToken = _gumroadController.text.trim();
      if (gumroadToken.isNotEmpty) {
        await _secureStorage.setGumroadToken(gumroadToken);
      }

      final googleKey = _googleKeyController.text.trim();
      if (googleKey.isNotEmpty) {
        await _secureStorage.setGoogleKey(googleKey);
      }
      final googleCse = _googleCseController.text.trim();
      if (googleCse.isNotEmpty) {
        await _secureStorage.setGoogleCseId(googleCse);
      }


      final voiceId = _voiceIdController.text.trim();
      if (voiceId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_voice_id', voiceId);
      }

      await _recordChangedRotations({
        'openai': openaiKey,
        'elevenlabs': elevenlabsKey,
        'anthropic': anthropicKey,
        'gumroad': gumroadToken,
        'google_api': googleKey,
      });
      AIConfig.clearCache();
      widget.onComplete();
    } catch (e) {
      setState(() => _error = 'Failed to save keys: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  /// Saves the token, then runs ONE read-only command through the guarded
  /// service. `gumroad user` proves four things at once: the token is valid,
  /// the guard permits reads, the process plumbing works, and the CLI is
  /// installed where we think it is.
  ///
  /// The token is never echoed back, and neither is the account payload —
  /// only whether it worked.
  Future<void> _testGumroad() async {
    final token = _gumroadController.text.trim();
    if (token.isEmpty) {
      setState(() => _gumroadTestResult = 'Paste a token first');
      return;
    }
    setState(() {
      _gumroadTesting = true;
      _gumroadTestResult = null;
    });
    try {
      await _secureStorage.setGumroadToken(token);
      final res = await GumroadCliService.instance.run(['user', '--json']);
      setState(() {
        _gumroadTestResult = res.ok
            ? '✅ Connected — storefront reachable'
            : '❌ ${res.output.split('\n').first}';
      });
    } catch (e) {
      setState(() => _gumroadTestResult = '❌ $e');
    } finally {
      setState(() => _gumroadTesting = false);
    }
  }

  /// Saves both values, then runs ONE real search.
  ///
  /// A key that is merely *stored* proves nothing — the factory's first stage
  /// is harvesting evidence from the web, and a search that silently fails
  /// turns the scout into a machine that invents gaps instead of finding them.
  /// So this does a live query and reports what actually came back.
  Future<void> _testSearch() async {
    final key = _googleKeyController.text.trim();
    final cse = _googleCseController.text.trim();
    if (key.isEmpty || cse.isEmpty) {
      setState(() => _searchTestResult = 'Need both the API key and the CSE ID');
      return;
    }
    setState(() {
      _searchTesting = true;
      _searchTestResult = null;
    });
    try {
      await _secureStorage.setGoogleKey(key);
      await _secureStorage.setGoogleCseId(cse);
      AIConfig.clearCache();

      final res = await GoogleSearchService().search(
        apiKey: key,
        cseId: cse,
        query: 'restaurant staff turnover cost',
        num: 3,
        dateRestrict: 'y1',
      );
      setState(() {
        if (res.diagnostics.ok && res.results.isNotEmpty) {
          _searchTestResult =
              '✅ Search works — ${res.results.length} result(s). Kai can harvest.';
        } else if (res.diagnostics.ok) {
          _searchTestResult =
              '⚠️ Connected but zero results — check the CSE is set to search '
              'the entire web, not one site.';
        } else {
          _searchTestResult =
              '❌ ${res.diagnostics.error ?? 'failed'} (HTTP ${res.diagnostics.statusCode})';
        }
      });
    } catch (e) {
      setState(() => _searchTestResult = '❌ $e');
    } finally {
      setState(() => _searchTesting = false);
    }
  }

  @override
  void dispose() {
    _openaiController.dispose();
    _elevenlabsController.dispose();
    _voiceIdController.dispose();
    _anthropicController.dispose();
    _gumroadController.dispose();
    _googleKeyController.dispose();
    _googleCseController.dispose();
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

              // Which of these needs doing, before scrolling to the fields.
              KaiKeyStatusStrip(registry: _registry),

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
              _ageFor('openai', _openaiController),
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
              _ageFor('elevenlabs', _elevenlabsController),
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
              _ageFor('anthropic', _anthropicController),
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

              // ── Google Programmable Search (factory mode: HARVEST) ───────
              //
              // Without this Kai cannot search the web, and without search he
              // cannot harvest evidence. The scout's founding rule is that
              // gaps are harvested, not imagined — so a blindfolded scout does
              // not degrade gracefully, it starts inventing opportunities.
              // Factory mode is meaningless until this works.
              const Text(
                'Google Search — API Key + CSE ID',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _ageFor('google_api', _googleKeyController),
              TextField(
                controller: _googleKeyController,
                obscureText: !_showGoogle,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Google API key (AIza...)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showGoogle ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _showGoogle = !_showGoogle),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _googleCseController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search engine ID (cx=...)',
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
                'Key: console.cloud.google.com → enable "Custom Search API" → '
                'Credentials → API key.\n'
                'CSE ID: programmablesearchengine.google.com → create → set it '
                'to search the ENTIRE WEB, then copy the "cx" value.\n'
                'Free tier is 100 searches/day.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _searchTesting ? null : _testSearch,
                    icon: _searchTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore, size: 16),
                    label: const Text('Test search'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFE7B0),
                      side: BorderSide(
                        color: const Color(0xFFFFE7B0).withOpacity(0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_searchTestResult != null)
                    Expanded(
                      child: Text(
                        _searchTestResult!,
                        style: TextStyle(
                          color: _searchTestResult!.startsWith('✅')
                              ? const Color(0xFF2ECC71)
                              : _searchTestResult!.startsWith('⚠️')
                                  ? const Color(0xFFFFC862)
                                  : const Color(0xFFE74C3C),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Gumroad (factory mode storefront) ────────────────────────
              //
              // Lives in the OS keychain, NOT in secrets.dart or .env.local —
              // Kai has read_file over the workspace, so a token in a file is a
              // token he can hand to a raw shell command, straight past the
              // command guard. The keychain is the one place his tools can't
              // reach, which is what makes the guarded service the only path.
              const Text(
                'Gumroad Access Token (Optional)',
                style: TextStyle(
                  color: Color(0xFFFFE7B0),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _ageFor('gumroad', _gumroadController),
              TextField(
                controller: _gumroadController,
                obscureText: !_showGumroad,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Paste the access token (not the app id or secret)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF2A2119),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showGumroad ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    onPressed: () => setState(() => _showGumroad = !_showGumroad),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Powers factory mode. gumroad.com → Settings → Advanced → create '
                'application → Generate access token. Publishing still needs your '
                'explicit approval every time.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _gumroadTesting ? null : _testGumroad,
                    icon: _gumroadTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.storefront, size: 16),
                    label: const Text('Test connection'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFE7B0),
                      side: BorderSide(
                        color: const Color(0xFFFFE7B0).withOpacity(0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_gumroadTestResult != null)
                    Expanded(
                      child: Text(
                        _gumroadTestResult!,
                        style: TextStyle(
                          color: _gumroadTestResult!.startsWith('✅')
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFE74C3C),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
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

