import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/services/core/kai_core_server.dart';
import 'package:homecoming_app/services/core/kai_surface_context.dart';
import 'package:homecoming_app/services/embodiment/kai_embodiment_gateway_service.dart';

void main() {
  test('an authoritative VR turn registers its full embodied presence',
      () async {
    final data = await Directory.systemTemp.createTemp('kai-vr-presence-');
    final server = KaiCoreServer(dataDirectory: data, port: 0);
    final client = KaiCoreClient(endpoint: await server.start());
    addTearDown(() async {
      client.close();
      await server.stop();
      await data.delete(recursive: true);
    });

    final reported = await reportEmbodiedPresenceToCore(
      client: client,
      status: 'thinking',
      context: KaiSurfaceContext.vr(
        worldId: 'vr_shack',
        deviceId: 'quest-three',
        sessionId: 'shack-session',
        goggles: KaiGoggles.on,
      ),
    );

    expect(reported, isTrue);
    expect((await client.activeDevices()).single['status'], 'thinking');
    final body = (await client.activeDevices()).single;
    expect(body['deviceId'], 'quest-three');
    expect(body['surface'], 'vr');
    expect(body['sessionId'], 'shack-session');
    expect(body['worldId'], 'vr_shack');
    expect(body['gogglesOn'], isTrue);
    expect(body['audioAvailable'], isTrue);
  });

  test('the embodiment report fails open when the core is unavailable',
      () async {
    final client = KaiCoreClient(
      endpoint: Uri.parse('http://127.0.0.1:1'),
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(client.close);

    expect(
      await reportEmbodiedPresenceToCore(
        client: client,
        context: KaiSurfaceContext.ar.copyWith(
          deviceId: 'glasses-one',
          sessionId: 'room-session',
        ),
      ),
      isFalse,
    );
  });

  test('non-embodied surfaces cannot register through the headset reporter',
      () async {
    final client = KaiCoreClient(
      endpoint: Uri.parse('http://127.0.0.1:1'),
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(client.close);

    expect(
      await reportEmbodiedPresenceToCore(
        client: client,
        context: KaiSurfaceContext.desktop,
      ),
      isFalse,
    );
  });
}
