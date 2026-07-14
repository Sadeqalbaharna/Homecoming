// sherpa_model_manager.dart
//
// Downloads and caches the sherpa-onnx keyword spotting model files on first run.
//
// Model: sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01 (~11 MB total)
// Source: GitHub releases (public, no auth required)
//   https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/
//
// Files are cached to getApplicationDocumentsDirectory()/sherpa_kws/.
// Call ensureModels() — returns the cache dir path on success, null on failure.

library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SherpaModelManager {
  static final SherpaModelManager _instance = SherpaModelManager._internal();
  factory SherpaModelManager() => _instance;
  SherpaModelManager._internal();

  static const _modelName =
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';

  // GitHub releases — public, no auth required
  static const _tarballUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'kws-models/$_modelName.tar.bz2';

  static const _expectedFiles = [
    'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
    'tokens.txt',
  ];

  bool _downloading = false;
  double _progress = 0.0;

  bool get isDownloading => _downloading;
  double get downloadProgress => _progress;

  Future<bool> checkAvailable() async {
    final dir = await _modelDir();
    return _allPresent(dir);
  }

  /// Downloads the tarball from GitHub releases, extracts the model files,
  /// and returns the directory path on success, or null on failure.
  Future<String?> ensureModels({void Function(double)? onProgress}) async {
    final dir = await _modelDir();
    if (_allPresent(dir)) return dir.path;
    if (_downloading) return null;

    _downloading = true;
    _progress = 0.0;

    try {
      // ── 1. Download tarball ──────────────────────────────────────────────
      print('⬇️  [Sherpa] Downloading model tarball from GitHub…');
      onProgress?.call(0.05);

      final response = await http.get(
        Uri.parse(_tarballUrl),
        headers: {'User-Agent': 'homecoming-app/1.0'},
      );

      if (response.statusCode != 200) {
        print('❌  [Sherpa] HTTP ${response.statusCode} for $_tarballUrl');
        _downloading = false;
        return null;
      }

      onProgress?.call(0.5);
      print('✅  [Sherpa] Tarball downloaded (${response.bodyBytes.length} bytes)');

      // ── 2. Decompress bz2 → tar bytes ───────────────────────────────────
      print('📦  [Sherpa] Extracting…');
      final tarBytes = BZip2Decoder().decodeBytes(response.bodyBytes);
      final archive  = TarDecoder().decodeBytes(tarBytes);

      onProgress?.call(0.8);

      // ── 3. Write target files to cache dir ──────────────────────────────
      for (final file in archive) {
        final name = file.name.split('/').last; // strip leading dir component
        if (!_expectedFiles.contains(name)) continue;
        if (!file.isFile) continue;

        final dest = File('${dir.path}/$name');
        await dest.writeAsBytes(file.content as List<int>);
        print('✅  [Sherpa] Extracted $name');
      }

      onProgress?.call(1.0);

      if (!_allPresent(dir)) {
        print('❌  [Sherpa] Some files missing after extraction');
        _downloading = false;
        return null;
      }

      _downloading = false;
      print('🟢  [Sherpa] All models ready at ${dir.path}');
      return dir.path;
    } catch (e) {
      _downloading = false;
      print('❌  [Sherpa] Error: $e');
      return null;
    }
  }

  Future<void> deleteModels() async {
    final dir = await _modelDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
    print('🗑️  [Sherpa] Models deleted');
  }

  Future<Directory> _modelDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sherpa_kws');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  bool _allPresent(Directory dir) {
    for (final name in _expectedFiles) {
      final f = File('${dir.path}/$name');
      if (!f.existsSync() || f.lengthSync() < 512) return false;
    }
    return true;
  }
}
