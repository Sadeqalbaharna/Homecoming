import 'dart:async';
import 'dart:io';

import 'package:homecoming_app/services/core/kai_core_server.dart';

Future<void> main(List<String> args) async {
  final configuredData = _argument(args, '--data-dir') ??
      Platform.environment['KAI_CORE_DATA_DIR'];
  final localData = Platform.environment['LOCALAPPDATA'];
  final dataDirectory = Directory(
    configuredData ??
        (localData == null || localData.isEmpty
            ? '${Directory.current.path}${Platform.pathSeparator}.kai-core'
            : '$localData${Platform.pathSeparator}Homecoming${Platform.pathSeparator}KaiCore'),
  );
  final port = int.tryParse(_argument(args, '--port') ?? '') ?? 8790;
  final server = KaiCoreServer(dataDirectory: dataDirectory, port: port);
  final endpoint = await server.start();
  stdout.writeln('[KaiCore] listening at $endpoint');
  stdout.writeln('[KaiCore] data: ${dataDirectory.path}');

  final stopping = Completer<void>();
  if (!Platform.isWindows) {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signal.watch().listen((_) async {
        if (stopping.isCompleted) return;
        await server.stop();
        stopping.complete();
      });
    }
  }
  // Windows has no portable SIGINT/SIGTERM subscription for a detached GUI
  // process. The open HttpServer keeps this future alive; process termination
  // closes the listener and the durable store is already flushed per mutation.
  await stopping.future;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
