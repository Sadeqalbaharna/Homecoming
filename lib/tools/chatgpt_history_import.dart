// ChatGPTHistoryImport — pour a year of ChatGPT into Kai's graph, correctly.
//
// ── The two traps this avoids ────────────────────────────────────────────────
//
// 1. The WRONG extractor. chatgpt_memory_import_service stamps 'related' on every
//    edge and asks for "values / patterns / insights" in 1–4 words — that is the
//    word-cloud generator the whole graph rebuild was a war against. Running a
//    year through it would rebuild the 152-node horoscope at scale. This routes
//    through brain_extraction_service.extractAndMerge instead: the stranger test,
//    typed EdgeTypes, confidence, salience — the extractor we got right.
//
// 2. SHALLOW depth. brain_backfill calls extractAndMerge with no event, so it
//    lands on the shallow prompt: "concrete facts only, max 3 nodes, save
//    abstract themes for deeper exchanges." A year of real conversation IS the
//    deeper exchange — fears, reversals, why he wants what he wants. So this
//    forces DEEP, and the deep prompt is the one that says "the deeper layer is
//    not more abstract, it is more specific: 'shipping the Tavern before it's
//    ready', not 'fear of failure'."
//
// ── Dry run first, always ────────────────────────────────────────────────────
//
// Pouring a year in is irreversible-ish. So the default is a SAMPLE IMPORT over
// a handful of conversations, reporting meaningfulness before committing the
// rest. The sample is explicitly persisted; it is not falsely called a dry run.
// If it comes back a word cloud, you find out after 15 calls, not 10,000. The
// number that matters is
// graphMeaningfulness — the same one that read 32% on the old graph.
library;

import 'dart:async';

import '../logic/chatgpt_export.dart';
import '../services/ai/ai_config.dart';
import '../services/ai/local_llm_service.dart';
import '../services/core/brain_extraction_service.dart';
import '../services/core/emotional_event_service.dart';
import '../services/core/kai_db.dart';

class LocalArchiveImportException implements Exception {
  final String message;
  const LocalArchiveImportException(this.message);
  @override
  String toString() => message;
}

class ArchiveImportEstimate {
  final int totalConversations;
  final int personalConversations;
  final int approximateLocalInputTokens;
  final int rawCharacters;

  const ArchiveImportEstimate({
    required this.totalConversations,
    required this.personalConversations,
    required this.approximateLocalInputTokens,
    required this.rawCharacters,
  });
}

class ImportRun {
  final int conversations;
  final int pairsSeen;
  final int extracted;
  final int failed;

  /// Meaningfulness AFTER this run — meaningful edges over total. The honest
  /// score of what he now knows. A dry run reports it so you can judge the
  /// extractor before spending the whole year.
  final int graphMeaningful;
  final int graphTotal;
  final bool dryRun;
  final int skippedAlready;
  final String localModel;
  final String stoppedReason;

  ImportRun({
    required this.conversations,
    required this.pairsSeen,
    required this.extracted,
    required this.failed,
    required this.graphMeaningful,
    required this.graphTotal,
    required this.dryRun,
    this.skippedAlready = 0,
    this.localModel = '',
    this.stoppedReason = '',
  });

  double get meaningfulness =>
      graphTotal == 0 ? 0 : graphMeaningful / graphTotal;

  String get summary =>
      '${dryRun ? "SAMPLE IMPORT" : "IMPORT"}: $conversations conversation(s), '
      '$extracted/$pairsSeen pairs extracted ($failed failed). '
      '$skippedAlready already imported. '
      'Graph now ${(meaningfulness * 100).round()}% meaningful '
      '($graphMeaningful/$graphTotal edges). '
      'Provider: ${localModel.isEmpty ? "local" : localModel}; paid tokens: 0.';
}

ArchiveImportEstimate estimateArchiveImport(
  List<ExportConversation> conversations, {
  double personalThreshold = 0.05,
}) {
  final personal = filterPersonal(conversations, threshold: personalThreshold);
  var chars = 0;
  for (final conversation in personal) {
    final userChars = conversation.turns
        .where((turn) => turn.role == 'user')
        .fold<int>(0, (sum, turn) => sum + turn.text.length)
        .clamp(0, ChatGPTHistoryImport.maxUserChars);
    final assistantChars = conversation.turns
        .where((turn) => turn.role == 'assistant')
        .fold<int>(0, (sum, turn) => sum + turn.text.length)
        .clamp(0, ChatGPTHistoryImport.maxAssistantChars);
    chars += userChars + assistantChars;
  }
  return ArchiveImportEstimate(
    totalConversations: conversations.length,
    personalConversations: personal.length,
    approximateLocalInputTokens: (chars / 4).ceil(),
    rawCharacters: chars,
  );
}

String archiveConversationId(ExportConversation conversation) {
  var hash = 0xcbf29ce484222325;
  final material = StringBuffer(conversation.title);
  for (final turn in conversation.turns) {
    material
      ..write('|${turn.role}|${turn.createTime}|')
      ..write(turn.text);
  }
  for (final unit in material.toString().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return 'conversation_${hash.toRadixString(16).padLeft(16, '0')}';
}

Map<String, dynamic> archiveEvidenceCapsule(
  ExportConversation conversation, {
  int excerptChars = 700,
}) {
  String excerpt(String role) {
    final text = conversation.turns
        .where((turn) => turn.role == role)
        .map((turn) => turn.text)
        .join('\n')
        .trim();
    return text.length <= excerptChars
        ? text
        : '${text.substring(0, excerptChars)}…';
  }

  final times = conversation.turns
      .map((turn) => turn.createTime)
      .where((time) => time > 0)
      .toList()
    ..sort();
  return {
    'sourceId': archiveConversationId(conversation),
    'title': conversation.title,
    'firstMessageAt': times.isEmpty ? 0 : (times.first * 1000).round(),
    'lastMessageAt': times.isEmpty ? 0 : (times.last * 1000).round(),
    'turnCount': conversation.turns.length,
    'userExcerpt': excerpt('user'),
    // Historical assistant text is evidence of the old relationship/voice,
    // never automatically a factual claim about the user or present Kai.
    'legacyAssistantExcerpt': excerpt('assistant'),
    'assistantAuthority': 'historical_voice_only',
    'livePromptEligible': false,
    'schemaVersion': 1,
  };
}

class ChatGPTHistoryImport {
  /// Run the import over parsed conversations.
  ///
  /// [dryRun] is a legacy parameter name. When true (default), it imports and
  /// checkpoints only [dryRunConversations]. Set false to import the whole list.
  ///
  /// Every pair is forced DEEP so the extractor reaches beliefs and reversals,
  /// not just names. Rate-limited so a year doesn't hammer the API in one breath.
  /// How much of one conversation's user-side text we hand the extractor. A
  /// conversation is collapsed to ONE call (the batching win), and this caps
  /// what that call costs. 6k chars is a long, substantive conversation; past
  /// that it's usually the same person repeating themselves.
  static const maxUserChars = 6000;
  static const maxAssistantChars = 2000;

  static Future<ImportRun> run(
    String personaId,
    List<ExportConversation> conversations, {
    bool dryRun = true,
    int dryRunConversations = 15,
    Duration pause = const Duration(milliseconds: 150),
    double personalThreshold = 0.05,
    void Function(String status)? onProgress,
    bool Function()? shouldCancel,
    Future<String> Function()? localPreflight,
  }) async {
    final brain = BrainExtractionService();
    final localModel = await (localPreflight ?? _requireLocalOllama)();
    onProgress?.call('Ollama ready: $localModel. Cloud fallback is disabled.');

    // LEVER 1 (free): drop impersonal task-chatter before a token is spent.
    // Strongest-personal first, so a dry run samples the richest conversations.
    final personal =
        filterPersonal(conversations, threshold: personalThreshold);
    onProgress?.call(
        '${conversations.length - personal.length} impersonal conversation(s) '
        'skipped for free. ${personal.length} carry personal signal.');

    final take =
        dryRun ? personal.take(dryRunConversations).toList() : personal;

    // LEVER 2 (~20x fewer calls): one extraction per CONVERSATION, not per turn.
    // A fact spans turns; per-turn re-extracts it ten times and misses the arc.
    // Collapse each conversation to a single synthetic exchange.
    final exchanges = <(ExportConversation, String, String)>[];
    for (final c in take) {
      final user =
          c.turns.where((t) => t.role == 'user').map((t) => t.text).join('\n');
      final asst = c.turns
          .where((t) => t.role == 'assistant')
          .map((t) => t.text)
          .join('\n');
      if (user.trim().isEmpty) continue;
      exchanges.add((
        c,
        user.length > maxUserChars ? user.substring(0, maxUserChars) : user,
        asst.length > maxAssistantChars
            ? asst.substring(0, maxAssistantChars)
            : asst,
      ));
    }

    onProgress?.call(
        '${dryRun ? "Dry run" : "Importing"}: ${exchanges.length} conversation(s) '
        '(one call each)…');

    var extracted = 0, failed = 0, skippedAlready = 0, pairsSeen = 0;
    var stoppedReason = '';
    for (var i = 0; i < exchanges.length; i++) {
      if (shouldCancel?.call() ?? false) {
        stoppedReason = 'paused by user';
        break;
      }
      final exchange = exchanges[i];
      final sourceId = archiveConversationId(exchange.$1);
      final checkpoint = KaiDb.instance.ref(
        'kai/$personaId/chatgpt_archive_import/checkpoints/$sourceId',
      );
      if ((await checkpoint.get()).exists) {
        skippedAlready++;
        onProgress?.call(
          'Skipping ${i + 1}/${exchanges.length}: already imported.',
        );
        continue;
      }
      pairsSeen++;
      BrainExtractionOutcome? outcome;
      await brain.extractAndMerge(
        personaId: personaId,
        userMessage: exchange.$2,
        aiReply: exchange.$3,
        eventType: EmotionalEventType.deep,
        eventIntensity: 45,
        sourceShardId: 'chatgpt_archive:$sourceId',
        allowCloudFallback: false,
        onOutcome: (value) => outcome = value,
      );
      if (outcome == BrainExtractionOutcome.merged ||
          outcome == BrainExtractionOutcome.empty) {
        extracted++;
        await KaiDb.instance
            .ref('kai/$personaId/chatgpt_archive_capsules/$sourceId')
            .set({
          ...archiveEvidenceCapsule(exchange.$1),
          'processedAt': DateTime.now().millisecondsSinceEpoch,
        });
        await checkpoint.set({
          'sourceId': sourceId,
          'title': exchange.$1.title,
          'processedAt': DateTime.now().millisecondsSinceEpoch,
          'outcome': outcome!.name,
          'provider': 'ollama',
          'model': localModel,
          'inputChars': exchange.$2.length + exchange.$3.length,
          'paidTokens': 0,
        });
      } else {
        failed++;
        stoppedReason = outcome == BrainExtractionOutcome.unavailable
            ? 'Ollama became unavailable; safe to resume later'
            : 'local extraction failed; safe to resume later';
        onProgress?.call(stoppedReason);
        break;
      }
      onProgress?.call(
        'Extracted ${i + 1}/${exchanges.length} locally; paid tokens: 0.',
      );
      if (i + 1 < exchanges.length) await Future.delayed(pause);
    }

    // The verdict: what did this actually build?
    final m = await brain.graphMeaningfulness(personaId);
    final run = ImportRun(
      conversations: take.length,
      pairsSeen: pairsSeen,
      extracted: extracted,
      failed: failed,
      graphMeaningful: m.meaningful,
      graphTotal: m.total,
      dryRun: dryRun,
      skippedAlready: skippedAlready,
      localModel: localModel,
      stoppedReason: stoppedReason,
    );
    await KaiDb.instance
        .ref('kai/$personaId/chatgpt_archive_import/last_run')
        .set({
      'finishedAt': DateTime.now().millisecondsSinceEpoch,
      'conversations': take.length,
      'processed': extracted,
      'failed': failed,
      'skippedAlready': skippedAlready,
      'stoppedReason': stoppedReason,
      'provider': 'ollama',
      'model': localModel,
      'paidTokens': 0,
    });
    print('📥 [Import] ${run.summary}');
    return run;
  }

  static Future<String> _requireLocalOllama() async {
    final local = LocalLLMService();
    var endpoint = await AIConfig.getLocalEndpoint();
    var models = endpoint == null ? null : await local.listModels(endpoint);
    if (models == null) {
      const loopback = 'http://127.0.0.1:11434';
      models = await local.listModels(loopback);
      if (models != null) {
        endpoint = loopback;
        await AIConfig.setLocalEndpoint(loopback);
      }
    }
    if (models == null) {
      throw const LocalArchiveImportException(
        'Ollama is not reachable. Start it and resume; no cloud request was made.',
      );
    }
    final expected = LocalLLMService.defaultModel;
    final available = models.any(
      (model) => model == expected || model.startsWith('$expected:'),
    );
    if (!available) {
      throw LocalArchiveImportException(
        'Ollama is connected but $expected is missing. Run: ollama pull $expected',
      );
    }
    return expected;
  }
}
