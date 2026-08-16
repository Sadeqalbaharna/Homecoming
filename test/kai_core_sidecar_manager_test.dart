import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';

class _FakeKaiCoreClient extends KaiCoreClient {
  _FakeKaiCoreClient(this.responses);

  final List<bool> responses;
  int calls = 0;

  @override
  Future<bool> isHealthy() async {
    calls += 1;
    if (responses.isEmpty) return false;
    return responses.removeAt(0);
  }
}

class _FakeProcess implements Process {
  @override
  int get pid => 1234;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
}

void main() {
  test('starts sidecar from executable folder and waits for readiness', () async {
    final executable = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'kai_core_sidecar_test_${DateTime.now().microsecondsSinceEpoch}'
      '${Platform.pathSeparator}'
      '${Platform.isWindows ? 'KaiCore.exe' : 'kai-core'}',
    );
    await executable.parent.create(recursive: true);
    await executable.writeAsString('fake');

    final client = _FakeKaiCoreClient([false, false, true]);
    final delays = <Duration>[];
    String? seenWorkingDirectory;
    ProcessStartMode? seenMode;

    await runZoned(
      () async {
        final manager = KaiCoreSidecarManager(
          client: client,
          readinessAttempts: 3,
          executableCandidates: () => [executable.path],
          delay: (duration) async => delays.add(duration),
          processStarter: (
            executablePath,
            arguments, {
            workingDirectory,
            mode = ProcessStartMode.normal,
          }) async {
            expect(executablePath, executable.path);
            expect(arguments, isEmpty);
            seenWorkingDirectory = workingDirectory;
            seenMode = mode;
            return _FakeProcess();
          },
        );

        expect(await manager.ensureAvailable(), isTrue);
      },
      zoneValues: {},
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, ____) {},
      ),
    );

    expect(seenWorkingDirectory, executable.parent.path);
    expect(seenMode, ProcessStartMode.detachedWithStdio);
    expect(delays, hasLength(2));
    expect(client.calls, 3);

    await executable.parent.delete(recursive: true);
  });
}
