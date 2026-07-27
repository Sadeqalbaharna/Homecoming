// ChatGPTImportScreen
// Lets the user paste their ChatGPT memories and import them into Kai's Firebase.
// Works with either the "Saved memories" list format or the "Memory summary" prose.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../logic/chatgpt_export.dart';
import '../services/core/chatgpt_memory_import_service.dart';
import '../services/ai/ai_config.dart';
import '../services/ai/usage_tracking_service.dart';
import '../tools/chatgpt_history_import.dart';

class ChatGPTImportScreen extends StatefulWidget {
  final String personaId;
  const ChatGPTImportScreen({super.key, required this.personaId});

  @override
  State<ChatGPTImportScreen> createState() => _ChatGPTImportScreenState();
}

class _ChatGPTImportScreenState extends State<ChatGPTImportScreen> {
  final _controller = TextEditingController();
  final _dio = Dio();
  bool _importing = false;
  bool _fetching = false;
  String? _status;
  ImportResult? _result;
  String? _error;
  List<ExportConversation>? _archive;
  ArchiveImportEstimate? _archiveEstimate;
  ImportRun? _archiveResult;
  String? _archiveName;
  String? _archiveStatus;
  bool _archiveImporting = false;
  bool _archiveCancelRequested = false;

  static const _bg = Color(0xFF0A0A12);
  static const _gold = Color(0xFFFFE7B0);
  static const _goldDim = Color(0x66FFE7B0);
  static const _goldFaint = Color(0x22FFE7B0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runImport() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _importing = true;
      _status = 'Starting…';
      _result = null;
      _error = null;
    });

    try {
      final result = await ChatGPTMemoryImportService().importMemories(
        personaId: widget.personaId,
        rawText: text,
        onProgress: (msg) {
          if (mounted) setState(() => _status = msg);
        },
      );

      if (mounted) {
        setState(() {
          _importing = false;
          _result = result;
          _status = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = e.toString();
          _status = null;
        });
      }
    }
  }

  Future<void> _fetchFromGPT() async {
    setState(() {
      _fetching = true;
      _error = null;
    });

    try {
      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) throw Exception('No OpenAI API key configured');

      const prompt = 'Please provide a comprehensive memory summary about me. '
          'Include everything you know: my name, where I live, my work and projects, '
          'my goals, my relationships and the people in my life, my preferences and interests, '
          'my values, any recurring themes in our conversations, and any personal context '
          'you have stored. Write it as a detailed prose summary, covering every topic you '
          'have any memory or context about. Be thorough — this will be used to brief '
          'another AI system about who I am.';

      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 2000,
          'temperature': 0.3,
        },
      );

      final reply = (response.data['choices'] as List)[0]['message']['content']
              as String? ??
          '';
      final _u = response.data['usage'];
      if (_u != null)
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o',
          inputTokens: _u['prompt_tokens'] as int? ?? 0,
          outputTokens: _u['completion_tokens'] as int? ?? 0,
          operation: 'chatgpt_import',
        ).catchError((_) {});

      if (mounted) {
        setState(() {
          _fetching = false;
          _controller.text = reply;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetching = false;
          _error = 'Could not fetch from GPT: $e';
        });
      }
    }
  }

  Future<void> _pickArchive() async {
    setState(() {
      _error = null;
      _archiveResult = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw Exception('Could not read the selected file.');
      final conversations = parseExport(jsonDecode(utf8.decode(bytes)));
      if (conversations.isEmpty) {
        throw Exception(
          'No ChatGPT conversations found. Select conversations.json from the export.',
        );
      }
      final estimate = estimateArchiveImport(conversations);
      if (!mounted) return;
      setState(() {
        _archive = conversations;
        _archiveEstimate = estimate;
        _archiveName = picked.name;
        _archiveStatus = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Archive could not be read: $e');
    }
  }

  Future<void> _runArchiveImport({required bool sampleOnly}) async {
    final conversations = _archive;
    if (conversations == null || conversations.isEmpty) return;
    setState(() {
      _archiveImporting = true;
      _archiveCancelRequested = false;
      _archiveResult = null;
      _archiveStatus = 'Checking Ollama and qwen3:8b…';
      _error = null;
    });
    try {
      final result = await ChatGPTHistoryImport.run(
        widget.personaId,
        conversations,
        dryRun: sampleOnly,
        dryRunConversations: 10,
        shouldCancel: () => _archiveCancelRequested,
        onProgress: (status) {
          if (mounted) setState(() => _archiveStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _archiveImporting = false;
        _archiveResult = result;
        _archiveStatus = result.stoppedReason.isEmpty
            ? 'Complete — paid API tokens: 0.'
            : '${result.stoppedReason}. Press resume when ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _archiveImporting = false;
        _archiveStatus = null;
        _error = e.toString();
      });
    }
  }

  Widget _archivePanel() {
    final estimate = _archiveEstimate;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10251D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.memory, color: Colors.greenAccent, size: 17),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'FULL HISTORY — OLLAMA ONLY',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Select conversations.json from your ChatGPT export. The raw file stays '
            'on this device. Obvious task chatter is discarded locally; personal '
            'history is processed by qwen3:8b with cloud fallback physically disabled.',
            style: TextStyle(color: _goldDim, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _archiveImporting ? null : _pickArchive,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(_archiveName ?? 'Choose conversations.json'),
          ),
          if (estimate != null) ...[
            const SizedBox(height: 10),
            Text(
              '${estimate.totalConversations} conversations found • '
              '${estimate.personalConversations} selected locally • '
              '~${estimate.approximateLocalInputTokens} local input tokens • '
              '0 paid tokens',
              style: const TextStyle(
                color: Color(0xFFB8FFD2),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _archiveImporting
                        ? null
                        : () => _runArchiveImport(sampleOnly: true),
                    child: const Text('Import richest 10 first'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _archiveImporting
                        ? null
                        : () => _runArchiveImport(sampleOnly: false),
                    child: Text(
                      _archiveResult?.stoppedReason.isNotEmpty == true
                          ? 'Resume import'
                          : 'Import / resume all',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_archiveImporting) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(color: Colors.greenAccent),
            const SizedBox(height: 8),
            Text(
              _archiveStatus ?? 'Processing locally…',
              style: const TextStyle(color: _goldDim, fontSize: 11.5),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _archiveCancelRequested = true),
              icon: const Icon(Icons.pause, size: 15),
              label: const Text('Pause safely after this conversation'),
            ),
          ] else if (_archiveStatus != null) ...[
            const SizedBox(height: 10),
            Text(
              _archiveStatus!,
              style: const TextStyle(color: Color(0xFFB8FFD2), fontSize: 11.5),
            ),
          ],
          if (_archiveResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _archiveResult!.summary,
              style:
                  const TextStyle(color: _goldDim, fontSize: 11, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _goldDim, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Import ChatGPT Memories',
          style: TextStyle(
              color: _gold, fontSize: 16, fontWeight: FontWeight.w400),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _archivePanel(),
              const SizedBox(height: 18),
              const Text(
                'SMALL SAVED-MEMORY NOTE — CLOUD IMPORT',
                style: TextStyle(
                  color: _goldDim,
                  fontSize: 10,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _goldFaint,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _goldDim.withOpacity(0.3), width: 0.5),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to get your ChatGPT memories:',
                      style: TextStyle(
                          color: _gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Open ChatGPT → Settings → Personalization\n'
                      '2. Click "Manage memories" or view your Memory summary\n'
                      '3. Select all text and paste it below\n\n'
                      'Both formats work — the bullet list or the prose summary.',
                      style:
                          TextStyle(color: _goldDim, fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Auto-fetch button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_fetching || _importing) ? null : _fetchFromGPT,
                  icon: _fetching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: _gold, strokeWidth: 1.5))
                      : const Icon(Icons.auto_awesome_outlined,
                          color: _gold, size: 16),
                  label: Text(
                    _fetching
                        ? 'Asking GPT for memories…'
                        : 'Auto-fetch from GPT',
                    style: const TextStyle(color: _gold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: _goldDim, width: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Expanded(child: Divider(color: Color(0x22FFE7B0))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or paste manually',
                        style:
                            TextStyle(color: Color(0x44FFE7B0), fontSize: 11)),
                  ),
                  Expanded(child: Divider(color: Color(0x22FFE7B0))),
                ]),
              ),

              // Text input
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _goldDim.withOpacity(0.3), width: 0.5),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 14,
                  style:
                      const TextStyle(color: _gold, fontSize: 13, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: 'Paste your ChatGPT memories here…',
                    hintStyle: TextStyle(color: _goldDim, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Import button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _importing ? null : _runImport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _goldFaint,
                    foregroundColor: _gold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _goldDim, width: 0.5),
                    ),
                    elevation: 0,
                  ),
                  child: _importing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: _gold, strokeWidth: 1.5),
                            ),
                            const SizedBox(width: 10),
                            Text(_status ?? 'Importing…',
                                style: const TextStyle(fontSize: 13)),
                          ],
                        )
                      : const Text('Import into Kai\'s memory',
                          style: TextStyle(fontSize: 14)),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              ],

              // Success
              if (_result != null) ...[
                const SizedBox(height: 20),
                _ResultCard(result: _result!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ImportResult result;
  const _ResultCard({required this.result});

  static const _gold = Color(0xFFFFE7B0);
  static const _goldDim = Color(0x88FFE7B0);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.greenAccent.withOpacity(0.25), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 16),
              SizedBox(width: 8),
              Text('Import complete',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          _stat('Knowledge nodes added', result.nodesAdded.toString()),
          _stat('Connections added', result.edgesAdded.toString()),
          _stat('Core facts written', result.factsWritten.toString()),
          _stat('Personality context',
              result.personalityUpdated ? 'Updated' : 'Skipped'),
          if (result.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Summary written to Kai:',
                style: TextStyle(color: _goldDim, fontSize: 11)),
            const SizedBox(height: 6),
            Text(
              result.summary,
              style: const TextStyle(
                  color: _gold,
                  fontSize: 12,
                  height: 1.6,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _goldDim, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: _gold, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
