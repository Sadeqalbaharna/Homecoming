// WorkspaceService
//
// The read-only file layer for Kai's engineer hemisphere (Phase 1). Holds a
// single "workspace" root (a repo folder the user points Kai at) and exposes
// scoped, safe, read-only operations over it: list a directory, read a file,
// search the code. Nothing here can write, delete, or run anything.
//
// Safety: every path is resolved *inside* the workspace root and any traversal
// ('..') is rejected — Kai can never read outside the folder you chose. Junk
// dirs (.git, build, node_modules, …) are skipped and reads are size-capped so
// a stray binary can't blow up the context.
//
// dart:io — desktop/mobile only (not web). Engineer mode is a desktop feature.

import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WorkspaceService {
  static final WorkspaceService instance = WorkspaceService._();
  WorkspaceService._();

  static const _prefKey = 'engineer_workspace_root';
  String? _root;
  bool _loaded = false;

  static const _skipDirs = {
    '.git', '.dart_tool', 'build', 'node_modules', '.gradle', '.idea',
    '.vscode', 'Pods', 'DerivedData', '.kotlin', 'dist', '.next', '__pycache__',
  };
  static const _textExt = {
    'dart', 'js', 'ts', 'tsx', 'jsx', 'html', 'css', 'scss', 'json', 'yaml',
    'yml', 'md', 'txt', 'py', 'kt', 'kts', 'java', 'gradle', 'xml', 'sh',
    'c', 'h', 'cpp', 'go', 'rs', 'rb', 'php', 'sql', 'toml', 'ini', 'properties',
    'gitignore', 'env',
  };

  // ── Root management ──────────────────────────────────────────────────────────
  Future<String?> getRoot() async {
    if (!_loaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _root = prefs.getString(_prefKey);
      } catch (_) {}
      _loaded = true;
    }
    return _root;
  }

  String? get rootSync => _root;
  bool get isSet => _root != null && _root!.isNotEmpty;

  Future<void> setRoot(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) throw Exception('Folder does not exist: $path');
    _root = dir.absolute.path;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _root!);
    } catch (_) {}
  }

  // ── Path safety ──────────────────────────────────────────────────────────────
  // Resolve a workspace-relative path to an absolute one *inside* the root.
  // Returns null on any escape attempt.
  String? _abs(String rel) {
    if (_root == null) return null;
    final cleaned = rel.replaceAll('\\', '/').trim();
    if (cleaned.split('/').any((s) => s == '..')) return null;
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '/') return _root;
    final native = cleaned.replaceAll('/', Platform.pathSeparator);
    return '$_root${Platform.pathSeparator}$native';
  }

  String _rel(String abs) {
    if (_root == null) return abs;
    var r = abs.startsWith(_root!) ? abs.substring(_root!.length) : abs;
    r = r.replaceAll('\\', '/');
    return r.startsWith('/') ? r.substring(1) : r;
  }

  // ── list_dir ─────────────────────────────────────────────────────────────────
  Future<String> listDir(String rel) async {
    final abs = _abs(rel);
    if (abs == null) return 'Path is outside the workspace or invalid.';
    final dir = Directory(abs);
    if (!dir.existsSync()) return 'Not a directory: $rel';
    final dirs = <String>[], files = <String>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory) {
          if (_skipDirs.contains(name)) continue;
          dirs.add('  [dir]  $name/');
        } else if (e is File) {
          final kb = (e.lengthSync() / 1024).toStringAsFixed(kbPrecision(e.lengthSync()));
          files.add('  $name  (${kb}KB)');
        }
      }
    } catch (e) {
      return 'Could not list $rel: $e';
    }
    dirs.sort();
    files.sort();
    final header = rel.isEmpty ? '(workspace root)' : rel;
    return '$header\n${([...dirs, ...files]).join('\n')}';
  }

  int kbPrecision(int bytes) => bytes < 10240 ? 1 : 0;

  // ── read_file ────────────────────────────────────────────────────────────────
  Future<String> readFile(String rel) async {
    final abs = _abs(rel);
    if (abs == null) return 'Path is outside the workspace or invalid.';
    final f = File(abs);
    if (!f.existsSync()) return 'No such file: $rel';
    try {
      final len = f.lengthSync();
      if (len > 2 * 1024 * 1024) {
        return 'File is too large to read (${(len / 1024 / 1024).toStringAsFixed(1)}MB): $rel';
      }
      var text = await f.readAsString().catchError((_) => '');
      if (text.isEmpty) return '(empty or non-text file): $rel';
      const cap = 60000;
      var truncated = false;
      if (text.length > cap) {
        text = text.substring(0, cap);
        truncated = true;
      }
      final lines = const LineSplitter().convert(text);
      final numbered = <String>[];
      for (var i = 0; i < lines.length; i++) {
        numbered.add('${(i + 1).toString().padLeft(4)}  ${lines[i]}');
      }
      return '$rel\n${numbered.join('\n')}${truncated ? '\n… (truncated)' : ''}';
    } catch (e) {
      return 'Could not read $rel: $e';
    }
  }

  // ── search_code ──────────────────────────────────────────────────────────────
  Future<String> search(String query, {String? glob}) async {
    if (_root == null) return 'No workspace set.';
    if (query.trim().isEmpty) return 'Empty search query.';
    final q = query.toLowerCase();
    final matches = <String>[];
    final rootDir = Directory(_root!);
    var scanned = 0;
    try {
      for (final e in rootDir.listSync(recursive: true, followLinks: false)) {
        if (matches.length >= 80 || scanned > 4000) break;
        if (e is! File) continue;
        final path = _rel(e.path);
        if (path.split('/').any((s) => _skipDirs.contains(s))) continue;
        final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
        if (!_textExt.contains(ext)) continue;
        if (glob != null && glob.isNotEmpty && !_globMatch(path, glob)) continue;
        try {
          if (e.lengthSync() > 512 * 1024) continue;
          scanned++;
          final lines = const LineSplitter().convert(await e.readAsString());
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].toLowerCase().contains(q)) {
              final snip = lines[i].trim();
              matches.add('$path:${i + 1}:  ${snip.length > 160 ? snip.substring(0, 160) : snip}');
              if (matches.length >= 80) break;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      return 'Search failed: $e';
    }
    if (matches.isEmpty) return 'No matches for "$query".';
    return 'Matches for "$query" (${matches.length}${matches.length >= 80 ? '+' : ''}):\n${matches.join('\n')}';
  }

  bool _globMatch(String path, String glob) {
    // very small glob: supports * and extension filters like "*.dart"
    final re = RegExp('^' +
        RegExp.escape(glob).replaceAll(r'\*', '.*').replaceAll(r'\?', '.') +
        r'$');
    final name = path.split('/').last;
    return re.hasMatch(name) || re.hasMatch(path);
  }

  // ── tree (orientation) ───────────────────────────────────────────────────────
  Future<String> tree({int maxDepth = 2}) async {
    if (_root == null) return 'No workspace set.';
    final out = <String>[];
    void walk(Directory dir, int depth, String prefix) {
      if (depth > maxDepth || out.length > 200) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      entries.sort((a, b) => a.path.compareTo(b.path));
      for (final e in entries) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory) {
          if (_skipDirs.contains(name)) continue;
          out.add('$prefix$name/');
          walk(e, depth + 1, '$prefix  ');
        } else {
          out.add('$prefix$name');
        }
      }
    }

    walk(Directory(_root!), 0, '');
    return out.join('\n');
  }
}
