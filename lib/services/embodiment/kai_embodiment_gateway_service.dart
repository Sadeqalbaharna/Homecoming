// Local embodiment gateway: exposes the canonical Homecoming Kai to Unity.
//
// This is deliberately a thin transport adapter. Personality, memory, mood,
// tools and voice remain inside AIService; Unity owns only embodiment.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/ai_service.dart';
import '../core/kai_continuity_contract.dart';
import '../core/kai_core_client.dart';
import '../core/kai_memory_scope.dart';
import '../core/kai_surface_context.dart';
import '../voice/voice_service.dart';
import 'tavern_kai_session.dart';

/// Whether the AR channel runs as a personal-Kai surface or a Tavern public kiosk.
///
/// In [tavernAr] mode every turn requires a valid Tavern session token;
/// requests without one are rejected before AI/memory/tool access (fail closed).
/// In [personalAr] mode (default) the personal-Kai surface is active as normal.
enum TavernGatewayMode {
  personalAr,
  tavernAr,
}

class KaiEmbodimentGatewayService {
  KaiEmbodimentGatewayService._();

  // ── One channel per body ───────────────────────────────────────────────────
  //
  // A channel is a listening endpoint bound to exactly ONE surface, because the
  // surface is the permission set — a transport that hosts two bodies has to
  // let the payload pick between them, which is the thing authoritativeSurface
  // exists to stop.
  //
  // That is not a limitation here, it is the shape of the hardware: the Quest
  // and the AR glasses are different devices that connect separately. Two
  // devices, two channels, two ports, two pinned surfaces. When per-device
  // enrolment lands, each channel gets its own credential and this becomes the
  // natural place to hang it.

  /// The VR channel — the Shack.
  static final KaiEmbodimentGatewayService vr = KaiEmbodimentGatewayService._();

  /// The AR channel — the Tavern, and anywhere else Kai is in the room.
  static final KaiEmbodimentGatewayService ar = KaiEmbodimentGatewayService._();

  /// Alias kept for callers written when there was one VR-only gateway.
  static KaiEmbodimentGatewayService get instance => vr;

  static const protocolVersion = '1';
  static const canonicalPersona = 'truekai';
  static const defaultPort = 8787;
  static const defaultArPort = 8788;

  /// One ordered lane per embodied body. VR and AR may now speak concurrently;
  /// turns within the same channel stay serial. Shared mood/personality writes
  /// are server-side increments, so neither body's state movement is lost.
  bool _busy = false;

  HttpServer? _server;
  AIService? _ai;
  String _model = 'gpt-5.5';
  KaiSurface _channelSurface = KaiSurface.vr;
  bool _allowUnauthenticatedLoopback = false;
  String _token = const String.fromEnvironment(
    'KAI_EMBODIMENT_TOKEN',
    defaultValue: '',
  );
  final Map<String, _CachedKaiAudio> _audio = {};
  final KaiCoreClient _coreClient = KaiCoreClient();

  // Tavern AR state — AR channel only.
  // _tavernHmacSecret is set at start() time from Platform.environment['TAVERN_KAI_HMAC_SECRET'].
  // Never set via --dart-define; secrets must not be compiled into client artifacts.
  String _tavernHmacSecret = '';
  TavernGatewayMode _tavernGatewayMode = TavernGatewayMode.personalAr;
  // Session provisioned by Kingdom Flutter via POST /v1/tavern/provision (loopback auth).
  // Cleared by stop() and POST /v1/tavern/end.
  _ProvisionedSession? _activeProvisionedSession;
  // Revocation cache: checks RTDB on each turn (30s TTL). Survives gateway restart
  // because the authoritative state lives in RTDB, not in this in-memory set.
  final Map<String, _RevocationCacheEntry> _revocationCache = {};

  bool get isRunning => _server != null;

  /// Test-only override — sets the HMAC secret and gateway mode directly,
  /// bypassing the Platform.environment read that start() would perform.
  /// Never call in production; the [kDebugMode] guard enforces this.
  @visibleForTesting
  void setTavernSecretForTesting(String secret, TavernGatewayMode mode) {
    assert(kDebugMode, 'setTavernSecretForTesting must only be called in debug builds');
    _tavernHmacSecret = secret;
    _tavernGatewayMode = mode;
  }
  Uri? get endpoint =>
      _server == null ? null : Uri.parse('http://127.0.0.1:${_server!.port}');

  Future<void> start({
    required AIService ai,
    required KaiSurface channelSurface,
    int port = defaultPort,
    String model = 'gpt-5.5',
    String? token,
    bool allowUnauthenticatedLoopback = false,
    TavernGatewayMode tavernMode = TavernGatewayMode.personalAr,
  }) async {
    if (_server != null) return;

    _ai = ai;
    _model = model;
    _channelSurface = channelSurface;
    _allowUnauthenticatedLoopback = allowUnauthenticatedLoopback;
    _tavernGatewayMode = tavernMode;
    if (token != null) _token = token;
    if (_token.isEmpty && !_allowUnauthenticatedLoopback) {
      _ai = null;
      throw StateError(
        'KAI_EMBODIMENT_TOKEN is required unless unauthenticated loopback '
        'development is explicitly enabled.',
      );
    }

    if (tavernMode == TavernGatewayMode.tavernAr) {
      final envSecret = Platform.environment['TAVERN_KAI_HMAC_SECRET'] ?? '';
      if (envSecret.isEmpty) {
        _ai = null;
        throw StateError(
          'TAVERN_KAI_HMAC_SECRET environment variable must be set before '
          'starting the AR gateway in tavernAr mode. '
          'Do not use --dart-define for secrets.',
        );
      }
      _tavernHmacSecret = envSecret;
    }

    // Milestone one is Editor-on-the-same-PC only. Loopback ensures an empty
    // development token can never expose Kai's brain to the local network.
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException catch (error) {
      if (error.osError?.errorCode == 10048) {
        _ai = null;
        print(
            '[EmbodimentGateway] ${_channelSurface.name} channel not started: '
            '127.0.0.1:$port is already in use.');
        return;
      }
      rethrow;
    }
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

    print('[EmbodimentGateway] ${_channelSurface.name} channel listening at '
        '$endpoint (loopback only, '
        'auth=${_token.isEmpty ? 'local-only' : 'required'})');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _ai = null;
    _audio.clear();
    _activeProvisionedSession = null;
    _revocationCache.clear();
    if (server != null) await server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    String? runtimeTaskId;
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

    // Tavern AR session provisioning — Kingdom Flutter calls this after issueTavernKaiSession.
    // Requires the same loopback Bearer token as Unity turns. The token delivered here
    // came directly from the authenticated Cloud Function call — no RTDB relay.
    if (request.method == 'POST' &&
        request.uri.path == '/v1/tavern/provision' &&
        _channelSurface == KaiSurface.ar) {
      await _provisionTavernSession(request);
      return;
    }

    // Tavern AR session bootstrap — Unity calls this to retrieve the provisioned token.
    // Returns data from _activeProvisionedSession (in-memory, set via /v1/tavern/provision).
    // Requires the same loopback Bearer token as Unity turns.
    if (request.method == 'GET' &&
        request.uri.path == '/v1/tavern/bootstrap' &&
        _channelSurface == KaiSurface.ar) {
      await _serveTavernBootstrap(request);
      return;
    }

    // Tavern AR session end — call from Kingdom Flutter after announceDepart.
    // Clears in-memory session and audio buffers immediately. Revocation authority
    // is the RTDB tombstone written by endTavernKaiSession Cloud Function.
    if (request.method == 'POST' &&
        request.uri.path == '/v1/tavern/end' &&
        _channelSurface == KaiSurface.ar) {
      await _endTavernSession(request);
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

    // Tavern AR session validation.
    // In tavernAr mode: missing token → 401 immediately (fail closed — no fallthrough to
    // personal-Kai). In personalAr mode: a stray token header is still validated for
    // defense in depth, but its absence is not an error.
    // guestUid is taken from the HMAC-signed payload — never from the request body.
    TavernKaiSession? tavernSession;
    if (_channelSurface == KaiSurface.ar) {
      final tavernToken = request.headers.value('X-Tavern-Session-Token');

      if (_tavernGatewayMode == TavernGatewayMode.tavernAr &&
          (tavernToken == null || tavernToken.isEmpty)) {
        _writeJson(request.response, HttpStatus.unauthorized, {
          'error': 'tavern_session_required',
        });
        return;
      }

      if (tavernToken != null && tavernToken.isNotEmpty) {
        if (_tavernHmacSecret.isEmpty) {
          _writeJson(request.response, HttpStatus.internalServerError, {
            'error': 'tavern_not_configured',
          });
          return;
        }
        final result = validateTavernToken(
          tavernToken,
          _tavernHmacSecret,
          DateTime.now().millisecondsSinceEpoch,
        );
        switch (result) {
          case TavernSessionInvalid(:final reason):
            _writeJson(request.response, HttpStatus.unauthorized, {
              'error': 'tavern_session_invalid',
              'reason': reason,
            });
            return;
          case TavernSessionValid(:final session):
            // Check RTDB revocation tombstone (30s cache, survives gateway restart).
            if (await _isSessionRevoked(session.sessionId)) {
              _writeJson(request.response, HttpStatus.unauthorized, {
                'error': 'tavern_session_revoked',
              });
              return;
            }
            tavernSession = session;
        }
      }
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

      // For Tavern AR sessions, replace the Unity-supplied surface context with
      // one built from the HMAC-verified guest identity. This enforces:
      //   • speaker = knownGuest (guestUid sourced from signed token)
      //   • memoryScopes = {identity} only (KaiSurfaceProfiles.host)
      //   • isSadeq = false → KaiMemoryScope.ephemeral (no durable memory)
      // Without this, Unity could supply any guestId or surface it chose.
      final effectiveSurfaceContext = tavernSession != null
          ? KaiSurfaceContext.arPublic(
              guestId: tavernSession.guestUid,
              consent: KaiGuestConsent.service,
              deviceId: body['deviceId'] as String? ?? 'unity-ar-tavern',
              sessionId: tavernSession.sessionId,
            )
          : turn.surfaceContext;

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

      final isPresenceEvent = effectiveSurfaceContext.isPresenceEvent;

      // Presence is coordination metadata, not chat authority. Report the
      // gateway-derived body after validation, but never hold up or reject a
      // Unity turn when the optional core is unavailable during migration.
      unawaited(reportEmbodiedPresenceToCore(
        client: _coreClient,
        context: effectiveSurfaceContext,
        status: isPresenceEvent ? 'idle' : 'thinking',
      ));

      if (isPresenceEvent) {
        _writeJson(request.response, HttpStatus.ok, {
          'protocolVersion': protocolVersion,
          ...KaiContinuityTurnResponse(
            correlationId: correlationId,
            reply: '',
            presenceState: 'present',
            gesture: 'none',
            voiceAudioUri: '',
            availableCapabilities:
                availableCapabilitiesFor(effectiveSurfaceContext),
            memoryCandidates: const [],
            handoff: turn.handoff,
            error: '',
          ).toJson(),
        });
        return;
      }

      runtimeTaskId = await _claimConversationSlot(turn);
      if (runtimeTaskId == null) {
        _writeJson(request.response, HttpStatus.serviceUnavailable, {
          'protocolVersion': protocolVersion,
          'correlationId': correlationId,
          'presenceState': 'waiting',
          'error': 'central_conversation_lane_unavailable',
        });
        return;
      }

      // Tavern turns must not read personal-Kai memory and must not save messages
      // or extracted facts. No consent policy for durable Tavern memory exists yet.
      final isTavernTurn = tavernSession != null;
      final response = await _ai!.sendMessage(
        text: utterance,
        personaId: canonicalPersona,
        model: _model,
        useMemory: !isTavernTurn,
        useWebSearch: false,
        saveUserMessage: !isTavernTurn,
        saveAssistantReply: !isTavernTurn,
        surfaceContext: effectiveSurfaceContext,
        ephemeralContext: _perceptionContext(spatial),
      );
      final visibleReply = effectiveSurfaceContext.allowsTechnicalConversation
          ? response.reply
          : sanitizeGogglesOffReply(response.reply, userText: utterance);

      if (runtimeTaskId != null) {
        await _coreClient.completeTask(
          runtimeTaskId,
          workerId: _workerId,
          result: {'replyCharacters': visibleReply.length},
        );
        runtimeTaskId = null;
      }

      // Voice is generated by Homecoming, where Kai's custom ElevenLabs
      // identity and credentials already live. Unity receives only an ephemeral
      // audio URL and never sees a provider key.
      String voiceAudioUri = '';
      try {
        final bytes = await _ai!.synthesizeTTS(visibleReply);
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
          reply: visibleReply,
          presenceState: 'speaking',
          gesture: _gestureFor(response.tags),
          voiceAudioUri: voiceAudioUri,
          availableCapabilities: availableCapabilitiesFor(effectiveSurfaceContext),
          // Candidates stay empty until a scoped summarizer proposes one.
          // Never infer durable memory from Unity perception in the adapter.
          memoryCandidates: const [],
          handoff: turn.handoff,
          error: response.raw['error']?.toString() ?? '',
        ).toJson(),
      });
    } on FormatException catch (error) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'presenceState': 'error',
        'error': 'invalid_json: ${error.message}',
      });
    } catch (error, stack) {
      if (runtimeTaskId != null) {
        try {
          await _coreClient.failTask(
            runtimeTaskId,
            workerId: _workerId,
            error: error.toString(),
          );
        } catch (_) {}
      }
      print('[EmbodimentGateway] turn failed: $error\n$stack');
      _writeJson(request.response, HttpStatus.internalServerError, {
        'presenceState': 'error',
        'error': 'homecoming_turn_failed',
      });
    } finally {
      _busy = false;
    }
  }

  String get _workerId => 'embodiment-${_channelSurface.name}';

  Future<String?> _claimConversationSlot(KaiContinuityTurnRequest turn) async {
    if (!await _coreClient.isHealthy()) return null;
    final correlation = turn.correlationId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '',
    );
    final taskId = '${_channelSurface.name}-turn-'
        '${correlation.isEmpty ? DateTime.now().microsecondsSinceEpoch : correlation}-'
        '${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _coreClient.enqueueTask(
        taskId: taskId,
        lane: 'conversation',
        kind: 'embodied_turn',
        sourceSurface: _channelSurface.name,
        conversationId: turn.surfaceContext.conversationId,
        payload: {
          'correlationId': turn.correlationId,
          'bodyId': turn.surfaceContext.deviceId ??
              'unity-${_channelSurface.name}-loopback',
          'gogglesOn': turn.surfaceContext.gogglesOn,
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 65));
      while (DateTime.now().isBefore(deadline)) {
        try {
          await _coreClient.claimTask(
            taskId,
            workerId: _workerId,
            lease: const Duration(minutes: 5),
          );
          return taskId;
        } on KaiCoreException catch (error) {
          if (error.statusCode != HttpStatus.conflict) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      await _coreClient.cancelTask(taskId, workerId: _workerId);
    } catch (error) {
      print('[EmbodimentGateway] lane admission failed: $error');
    }
    return null;
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

  // ── Tavern AR helpers ──────────────────────────────────────────────────────

  static const _rtdbBase =
      'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app';
  static const _revocationCacheTtl = Duration(seconds: 30);

  /// POST /v1/tavern/provision
  ///
  /// Called by Kingdom Flutter after issueTavernKaiSession succeeds.
  /// Accepts {sessionId, sessionToken} and stores them as the active session.
  /// Requires the same loopback Bearer token as Unity turns — no public access.
  Future<void> _provisionTavernSession(HttpRequest request) async {
    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized,
          {'error': 'unauthorized'});
      return;
    }
    final rawBody = await utf8.decoder.bind(request).join();
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(rawBody) as Map).cast<String, dynamic>();
    } catch (_) {
      _writeJson(request.response, HttpStatus.badRequest,
          {'error': 'invalid_json'});
      return;
    }
    final sessionToken = body['sessionToken'] as String?;
    if (sessionToken == null || sessionToken.isEmpty) {
      _writeJson(request.response, HttpStatus.badRequest,
          {'error': 'sessionToken_required'});
      return;
    }
    if (_tavernHmacSecret.isEmpty) {
      _writeJson(request.response, HttpStatus.internalServerError,
          {'error': 'tavern_not_configured'});
      return;
    }
    // Validate the token before storing it — reject garbage up front.
    final result = validateTavernToken(
        sessionToken, _tavernHmacSecret, DateTime.now().millisecondsSinceEpoch);
    switch (result) {
      case TavernSessionInvalid(:final reason):
        _writeJson(request.response, HttpStatus.badRequest, {
          'error': 'invalid_session_token',
          'reason': reason,
        });
        return;
      case TavernSessionValid(:final session):
        _activeProvisionedSession = _ProvisionedSession(session, sessionToken);
        _writeJson(request.response, HttpStatus.ok, {
          'provisioned': true,
          'sessionId': session.sessionId,
          'tableId': session.tableId,
          'expiresAt': session.expiresAt,
        });
    }
  }

  /// GET /v1/tavern/bootstrap
  ///
  /// Called by Unity to retrieve the provisioned session token.
  /// Serves from _activeProvisionedSession (set via POST /v1/tavern/provision).
  /// Requires the same loopback Bearer token as Unity turns — no public access.
  Future<void> _serveTavernBootstrap(HttpRequest request) async {
    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized,
          {'error': 'unauthorized'});
      return;
    }
    final provisioned = _activeProvisionedSession;
    if (provisioned == null) {
      _writeJson(request.response, HttpStatus.notFound,
          {'error': 'no_active_session'});
      return;
    }
    final session = provisioned.session;
    _writeJson(request.response, HttpStatus.ok, {
      'sessionId': session.sessionId,
      'sessionToken': provisioned.sessionToken,
      'tableId': session.tableId,
      'guestUid': session.guestUid,
      'expiresAt': session.expiresAt,
      'personaScope': 'tavern_kai',
      'capabilities': session.capabilities,
    });
  }

  /// POST /v1/tavern/end
  ///
  /// Called by Kingdom Flutter on visit departure.
  /// Clears the in-memory session and audio buffers immediately.
  /// The authoritative revocation is the RTDB tombstone written by
  /// endTavernKaiSession Cloud Function — this call provides instant local cleanup.
  Future<void> _endTavernSession(HttpRequest request) async {
    if (!_authorized(request)) {
      _writeJson(request.response, HttpStatus.unauthorized,
          {'error': 'unauthorized'});
      return;
    }
    final cleared = _activeProvisionedSession != null;
    _activeProvisionedSession = null;
    _audio.clear();
    _revocationCache.clear();
    _writeJson(request.response, HttpStatus.ok, {'cleared': cleared});
  }

  /// Check whether [sessionId] has been revoked by consulting the RTDB
  /// /tavern_kai_revocations/{sessionId} tombstone. Result is cached for
  /// [_revocationCacheTtl] to avoid an RTDB read on every turn.
  ///
  /// Fails closed: any network or parse error is treated as revoked.
  Future<bool> _isSessionRevoked(String sessionId) async {
    final now = DateTime.now();
    final cached = _revocationCache[sessionId];
    if (cached != null && now.isBefore(cached.cachedUntil)) {
      return cached.revoked;
    }
    try {
      final uri =
          Uri.parse('$_rtdbBase/tavern_kai_revocations/$sessionId.json');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      final revoked = resp.statusCode == 200 && resp.body != 'null';
      _revocationCache[sessionId] = _RevocationCacheEntry(
        revoked: revoked,
        cachedUntil: now.add(_revocationCacheTtl),
      );
      return revoked;
    } catch (error) {
      print('[EmbodimentGateway] revocation check failed for $sessionId: $error');
      // Fail closed — deny the turn if we cannot confirm revocation status.
      return true;
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

Future<bool> reportEmbodiedPresenceToCore({
  required KaiCoreClient client,
  required KaiSurfaceContext context,
  String status = 'idle',
}) async {
  if (context.surface != KaiSurface.vr && context.surface != KaiSurface.ar) {
    return false;
  }
  try {
    await client.heartbeat(
      deviceId: context.deviceId ?? 'unity-${context.surface.name}-loopback',
      surface: context.surface.name,
      sessionId: context.sessionId ?? '${context.surface.name}-session',
      foreground: true,
      audioAvailable: true,
      worldId: context.worldId,
      gogglesOn: context.gogglesOn,
      status: status,
      lastInteractionAt: DateTime.now(),
    );
    return true;
  } catch (_) {
    return false;
  }
}

class _ProvisionedSession {
  final TavernKaiSession session;
  final String sessionToken;
  const _ProvisionedSession(this.session, this.sessionToken);
}

class _RevocationCacheEntry {
  final bool revoked;
  final DateTime cachedUntil;
  const _RevocationCacheEntry({required this.revoked, required this.cachedUntil});
}

class _CachedKaiAudio {
  const _CachedKaiAudio(this.bytes, this.expiresAt);

  final Uint8List bytes;
  final DateTime expiresAt;
}
