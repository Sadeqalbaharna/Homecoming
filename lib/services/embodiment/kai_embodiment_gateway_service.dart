// Local embodiment gateway: exposes the canonical Homecoming Kai to Unity.
//
// This is deliberately a thin transport adapter. Personality, memory, mood,
// tools and voice remain inside AIService; Unity owns only embodiment.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../ai/ai_service.dart';
import '../core/kai_continuity_contract.dart';
import '../core/kai_surface_context.dart';
import '../voice/voice_service.dart';

class KaiEmbodimentGatewayService {
  KaiEmbodimentGatewayService._();

  static final KaiEmbodimentGatewayService instance =
      KaiEmbodimentGatewayService._();

  static const protocolVersion = '1';
  static const canonicalPersona = 'truekai';
  static const defaultPort = 8787;

  HttpServer? _server;
  AIService? _ai;
  bool _busy = false;
  String _model = 'gpt-5.5';
  KaiSurface _channelSurface = KaiSurface.vr;
  bool _allowUnauthenticatedLoopback = false;
  String _token = const String.fromEnvironment(
    'KAI_EMBODIMENT_TOKEN',
    defaultValue: '',
  );
  final Map<String, _CachedKaiAudio> _audio = {};

  bool get isRunning => _server != null;
  Uri? get endpoint =>
      _server == null ? null : Uri.parse('http://127.0.0.1:${_server!.port}');

  Future<void> start({
    required AIService ai,
    required KaiSurface channelSurface,
    int port = defaultPort,
    String model = 'gpt-5.5',
    String? token,
    bool allowUnauthenticatedLoopback = false,
  }) async {
    if (_server != null) return;

    _ai = ai;
    _model = model;
    _channelSurface = channelSurface;
    _allowUnauthenticatedLoopback = allowUnauthenticatedLoopback;
    if (token != null) _token = token;
    if (_token.isEmpty && !_allowUnauthenticatedLoopback) {
      _ai = null;
      throw StateError(
        'KAI_EMBODIMENT_TOKEN is required unless unauthenticated loopback '
        'development is explicitly enabled.',
      );
    }

    // Milestone one is Editor-on-the-same-PC only. Loopback ensures an empty
    // development token can never expose Kai's brain to the local network.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(
      _handleRequest,
      onError: (Object error, StackTrace stack) {
        print('[EmbodimentGateway] server error: $error');
      },
      onDone: () {
        if (identical(_server, server)) _server = null;
      },
      cancelOnError: false,
    );

    print('[EmbodimentGateway] listening at $endpoint '
        '(loopback only, auth=${_token.isEmpty ? 'local-only' : 'required'})');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _ai = null;
    _audio.clear();
    if (server != null) await server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applyHeaders(request.response);

    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 3 &&
        request.uri.pathSegments[0] == 'v1' &&
        request.uri.pathSegments[1] == 'audio') {
      await _serveAudio(request, request.uri.pathSegments[2]);
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      _writeJson(request.response, HttpStatus.ok, {
        'ok': true,
        'service': 'homecoming-kai-embodiment',
        'protocolVersion': protocolVersion,
        'continuityVersion': KaiContinuityContract.version,
        'personaId': canonicalPersona,
        'authRequired': _token.isNotEmpty,
        'channelSurface': _channelSurface.name,
        'loopbackDevelopment': _token.isEmpty && _allowUnauthenticatedLoopback,
        'capabilities': [
          'text_turn',
          'elevenlabs_tts',
          'spatial_audio',
          'speech_to_text',
          'continuity_handoff',
          'memory_candidates',
        ],
      });
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/v1/transcribe') {
      await _transcribe(request);
      return;
    }

    if (request.method != 'POST' || request.uri.path != '/v1/turn') {
      _writeJson(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
      return;
    }

    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized, {
        'error': 'unauthorized',
      });
      return;
    }

    if (_busy) {
      _writeJson(request.response, HttpStatus.conflict, {
        'error': 'kai_is_already_handling_a_turn',
      });
      return;
    }

    final declaredLength = request.contentLength;
    if (declaredLength > 64 * 1024) {
      _writeJson(request.response, HttpStatus.requestEntityTooLarge, {
        'error': 'request_too_large',
      });
      return;
    }

    _busy = true;
    try {
      final rawBody = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const FormatException('JSON object required');
      }

      final body = decoded.cast<String, dynamic>();
      // This transport is a headset. It hosts embodied bodies and nothing else.
      //
      // Without this clamp the universal parser will mint whatever surface the
      // payload names, and the surface IS the permission set — so a POST
      // carrying {"surface":"desktop"} came back holding SMS, calendar,
      // filesystem, shell and Gumroad publish. Loopback binding and an
      // empty-by-default auth token are not a boundary against a local process.
      //
      // Unity may declare vr or ar. Anything else is refused here, before a
      // context exists to be trusted.
      final turn = KaiContinuityTurnRequest.fromJson(
        body,
        defaultPersona: canonicalPersona,
        allowedSurfaces: kEmbodimentSurfaces,
        authoritativeSurface: _channelSurface,
      );
      final personaId = turn.personaId;
      final utterance = turn.utterance;
      final correlationId = turn.correlationId;
      final spatial = body['spatial'];

      if (personaId != canonicalPersona) {
        _writeJson(request.response, HttpStatus.badRequest, {
          'protocolVersion': protocolVersion,
          'correlationId': correlationId,
          'presenceState': 'error',
          'error': 'unknown_persona',
        });
        return;
      }
      if (utterance.isEmpty || utterance.length > 12000) {
        _writeJson(request.response, HttpStatus.badRequest, {
          'protocolVersion': protocolVersion,
          'correlationId': correlationId,
          'presenceState': 'error',
          'error': 'utterance_missing_or_too_long',
        });
        return;
      }

      final isPresenceEvent = turn.surfaceContext.isPresenceEvent;

      final response = await _ai!.sendMessage(
        text: utterance,
        personaId: canonicalPersona,
        model: _model,
        useMemory: !isPresenceEvent,
        useWebSearch: false,
        saveUserMessage: !isPresenceEvent,
        saveAssistantReply: true,
        surfaceContext: turn.surfaceContext,
        ephemeralContext: _perceptionContext(spatial),
      );

      // Voice is generated by Homecoming, where Kai's custom ElevenLabs
      // identity and credentials already live. Unity receives only an ephemeral
      // audio URL and never sees a provider key.
      String voiceAudioUri = '';
      try {
        final bytes = await _ai!.synthesizeTTS(response.reply);
        if (bytes != null && bytes.isNotEmpty) {
          _evictExpiredAudio();
          final sanitizedCorrelation =
              correlationId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
          final safeCorrelation = sanitizedCorrelation.length > 48
              ? sanitizedCorrelation.substring(0, 48)
              : sanitizedCorrelation;
          final id = '${safeCorrelation.isEmpty ? 'turn' : safeCorrelation}-'
              '${DateTime.now().microsecondsSinceEpoch}.mp3';
          _audio[id] = _CachedKaiAudio(
            bytes,
            DateTime.now().add(const Duration(minutes: 5)),
          );
          voiceAudioUri = '${endpoint!}/v1/audio/$id';
        }
      } catch (error) {
        // A voice outage must not discard Kai's valid text response.
        print('[EmbodimentGateway] TTS unavailable: $error');
      }

      _writeJson(request.response, HttpStatus.ok, {
        'protocolVersion': protocolVersion,
        ...KaiContinuityTurnResponse(
          correlationId: correlationId,
          reply: response.reply,
          presenceState: 'speaking',
          gesture: _gestureFor(response.tags),
          voiceAudioUri: voiceAudioUri,
          availableCapabilities: availableCapabilitiesFor(turn.surfaceContext),
          // Candidates stay empty until a scoped summarizer proposes one.
          // Never infer durable memory from Unity perception in the adapter.
          memoryCandidates: const [],
          handoff: turn.handoff,
        ).toJson(),
      });
    } on FormatException catch (error) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'presenceState': 'error',
        'error': 'invalid_json: ${error.message}',
      });
    } catch (error, stack) {
      print('[EmbodimentGateway] turn failed: $error\n$stack');
      _writeJson(request.response, HttpStatus.internalServerError, {
        'presenceState': 'error',
        'error': 'homecoming_turn_failed',
      });
    } finally {
      _busy = false;
    }
  }

  bool _authorized(HttpRequest request) {
    if (_token.isEmpty) {
      return _allowUnauthenticatedLoopback &&
          request.connectionInfo?.remoteAddress.isLoopback == true;
    }
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return header == 'Bearer $_token';
  }

  Future<void> _transcribe(HttpRequest request) async {
    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized, {
        'error': 'unauthorized',
      });
      return;
    }

    const maximumBytes = 15 * 1024 * 1024;
    if (request.contentLength > maximumBytes) {
      _writeJson(request.response, HttpStatus.requestEntityTooLarge, {
        'error': 'audio_too_large',
      });
      return;
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maximumBytes) {
        _writeJson(request.response, HttpStatus.requestEntityTooLarge, {
          'error': 'audio_too_large',
        });
        return;
      }
    }

    final bytes = builder.takeBytes();
    if (bytes.length < 48) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'error': 'audio_empty',
      });
      return;
    }

    final file = File('${Directory.systemTemp.path}'
        '${Platform.pathSeparator}kai_unity_${DateTime.now().microsecondsSinceEpoch}.wav');
    try {
      await file.writeAsBytes(bytes, flush: true);
      final transcript =
          (await VoiceService().transcribeAudio(file.path))?.trim() ?? '';
      if (transcript.isEmpty) {
        _writeJson(request.response, HttpStatus.unprocessableEntity, {
          'error': 'transcription_empty',
        });
        return;
      }
      _writeJson(request.response, HttpStatus.ok, {
        'transcript': transcript,
        'error': '',
      });
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  String _perceptionContext(dynamic spatial) {
    if (spatial is! Map) return '';
    final encoded = jsonEncode(spatial);
    final bounded =
        encoded.length > 6000 ? encoded.substring(0, 6000) : encoded;
    return '''LIVE UNITY PERCEPTION (temporary, authoritative only for this turn):
$bounded
Use this to understand the immediate scene naturally. Do not claim to see anything absent from this snapshot. Do not recite the data structure. These observations are transient world state, not user testimony and not durable memory.''';
  }

  Future<void> _serveAudio(HttpRequest request, String id) async {
    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized, {
        'error': 'unauthorized',
      });
      return;
    }

    _evictExpiredAudio();
    final cached = _audio.remove(id); // single-use URL
    if (cached == null || cached.expiresAt.isBefore(DateTime.now())) {
      _writeJson(request.response, HttpStatus.notFound, {
        'error': 'audio_expired_or_missing',
      });
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('audio', 'mpeg');
    request.response.headers.contentLength = cached.bytes.length;
    request.response.add(cached.bytes);
    await request.response.close();
  }

  void _evictExpiredAudio() {
    final now = DateTime.now();
    _audio.removeWhere((_, value) => value.expiresAt.isBefore(now));
  }

  static String _gestureFor(List<String> tags) {
    final normalized = tags.map((tag) => tag.toLowerCase()).toSet();
    if (normalized.any((tag) => tag.contains('greet'))) return 'wave';
    if (normalized.any((tag) => tag.contains('curious'))) return 'curious';
    if (normalized.any((tag) => tag.contains('agree'))) return 'acknowledge';
    return 'none';
  }

  static void _applyHeaders(HttpResponse response) {
    response.headers.contentType = ContentType.json;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Cache-Control', 'no-store');
  }

  static void _writeJson(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) {
    final payload = Map<String, Object?>.from(body);
    if (payload.containsKey('presenceState')) {
      // Keep failures on the same versioned envelope as successful turns so a
      // client never needs a second response parser for continuity metadata.
      payload.putIfAbsent(
        'continuityVersion',
        () => KaiContinuityContract.version,
      );
      payload.putIfAbsent('availableCapabilities', () => const <String>[]);
      payload.putIfAbsent('memoryCandidates', () => const <Object>[]);
    }
    response.statusCode = status;
    response.write(jsonEncode(payload));
    response.close();
  }
}

class _CachedKaiAudio {
  const _CachedKaiAudio(this.bytes, this.expiresAt);

  final Uint8List bytes;
  final DateTime expiresAt;
}
