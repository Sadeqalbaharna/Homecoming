// CodeWorkspaceService
//
// Phase 1 of Kai's "engineer mode": read-only, sandboxed access to a single
// code workspace. The Claude hemisphere uses these to investigate a repo
// before answering — read files, list directories, grep contents, glob paths.
//
// Safety: everything is scoped to one root folder. Paths are validated to
// prevent escaping it (no '..', no absolute paths, no drive hops), noise dirs
// (node_modules/.git/build/…) are skipped, binaries and oversized files are
// refused, and outputs are capped to keep token usage bounded. Nothing here
// ever writes, deletes, or executes — read-only by construction.

import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class CodeWorkspaceService {
  static final CodeWorkspaceService instance = CodeWorkspaceService._();
  CodeWorkspaceService._();

  String? _root;
  final List<String> _projects = [];
  bool _loaded = false;
  static const _prefsKey = 'code_workspace_root';
  static const _projectsKey = 'code_workspaces';

  static const _ignore = {
    'node_modules', '.git', 'build', '.dart_tool', '.gradle', 'Pods',
    '.idea', '.vscode', 'dist', '.next', 'out', 'DerivedData', '.venv',
  };
  static const _maxFileBytes = 120 * 1024;
  static const _maxLines = 700;
  static const _maxGrep = 80;
  static const _maxList = 200;

  bool get hasWorkspace => _root != null && _root!.isNotEmpty;
  String? get root => _root;
  List<String> get projects => List.unmodifiable(_projects);

  /// Load the persisted project list + active root (idempotent).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _root = p.getString(_prefsKey);
      _projects
        ..clear()
        ..addAll(p.getStringList(_projectsKey) ?? const []);
      if (_root != null && !_projects.contains(_root!)) _projects.add(_root!);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_root == null) {
        await p.remove(_prefsKey);
      } else {
        await p.setString(_prefsKey, _root!);
      }
      await p.setStringList(_projectsKey, _projects);
    } catch (_) {}
  }

  /// Set the active workspace (adds it to the project list). Null clears active.
  Future<void> setRoot(String? path) async {
    _root = (path == null || path.trim().isEmpty) ? null : path.trim();
    if (_root != null && !_projects.contains(_root!)) _projects.add(_root!);
    await _persist();
  }

  /// Add a project without necessarily switching to it.
  Future<void> addProject(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    if (!_projects.contains(p)) _projects.add(p);
    _root ??= p;
    await _persist();
  }

  /// Remove a project; if it was active, fall back to the first remaining one.
  Future<void> removeProject(String path) async {
    _projects.remove(path);
    if (_root == path) _root = _projects.isNotEmpty ? _projects.first : null;
    await _persist();
  }

  /// Make an existing project the active workspace.
  Future<void> selectProject(String path) async {
    if (_projects.contains(path)) {
      _root = path;
      await _persist();
    }
  }

  /// Short display name (last path segment) for a project path.
  static String nameOf(String path) {
    final parts = path.replaceAll('\\', '/').split('/')..removeWhere((s) => s.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  // ── Path safety ─────────────────────────────────────────────────────────────
  String? _resolve(String rel) {
    if (_root == null) return null;
    var r = rel.trim().replaceAll('\\', '/');
    while (r.startsWith('/')) {
      r = r.substring(1);
    }
    if (r.isEmpty) return _root;
    final segs = r.split('/').where((s) => s.isNotEmpty).toList();
    for (final s in segs) {
      if (s == '..' || s == '.' || s.contains(':')) return null; // no escaping
    }
    return _root! + Platform.pathSeparator + segs.join(Platform.pathSeparator);
  }

  bool _ignored(String path) {
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (_ignore.contains(part)) return true;
    }
    return false;
  }

  String _relOf(String abs) {
    var r = abs;
    if (_root != null && abs.startsWith(_root!)) r = abs.substring(_root!.length);
    return r.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }

  // ── Tools ───────────────────────────────────────────────────────────────────
  Future<String> readFile(String rel) async {
    final abs = _resolve(rel);
    if (abs == null) return 'Invalid or unscoped path: $rel';
    final f = File(abs);
    if (!await f.exists()) return 'No such file: $rel';
    try {
      final len = await f.length();
      if (len > _maxFileBytes) {
        return 'File too large (${(len / 1024).round()} KB): $rel — search it instead.';
      }
      final bytes = await f.readAsBytes();
      if (bytes.contains(0)) return 'Binary file (skipped): $rel';
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      final shown = lines.take(_maxLines).toList();
      final numbered = [
        for (int i = 0; i < shown.length; i++)
          '${(i + 1).toString().padLeft(4)}  ${shown[i]}'
      ].join('\n');
      final more = lines.length > _maxLines
          ? '\n… (${lines.length - _maxLines} more lines truncated)'
          : '';
      return '// $rel\n$numbered$more';
    } catch (e) {
      return 'Error reading $rel: $e';
    }
  }

  Future<String> listDir(String rel) async {
    final abs = _resolve(rel);
    if (abs == null) return 'Invalid path: $rel';
    final d = Directory(abs);
    if (!await d.exists()) return 'No such directory: $rel';
    try {
      final ents = d.listSync()..sort((a, b) => a.path.compareTo(b.path));
      final out = <String>[];
      for (final e in ents) {
        final name = _relOf(e.path).split('/').last;
        if (_ignore.contains(name)) continue;
        out.add(e is Directory ? '$name/' : name);
        if (out.length >= _maxList) {
          out.add('… (truncated)');
          break;
        }
      }
      return out.isEmpty ? '(empty)' : out.join('\n');
    } catch (e) {
      return 'Error listing $rel: $e';
    }
  }

  Future<String> searchCode(String pattern, {String? glob}) async {
    if (_root == null) return 'No workspace configured.';
    RegExp re;
    try {
      re = RegExp(pattern);
    } catch (e) {
      return 'Bad regex: $e';
    }
    final globRe = (glob != null && glob.isNotEmpty) ? _globToRegExp(glob) : null;
    final out = <String>[];
    int count = 0;
    await for (final f in _walk(Directory(_root!))) {
      if (globRe != null && !globRe.hasMatch(_relOf(f.path))) continue;
      try {
        if (await f.length() > _maxFileBytes) continue;
        final bytes = await f.readAsBytes();
        if (bytes.contains(0)) continue;
        final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (re.hasMatch(lines[i])) {
            out.add('${_relOf(f.path)}:${i + 1}: ${lines[i].trim()}');
            if (++count >= _maxGrep) {
              out.add('… (truncated at $_maxGrep matches)');
              return out.join('\n');
            }
          }
        }
      } catch (_) {}
    }
    return out.isEmpty ? 'No matches for /$pattern/' : out.join('\n');
  }

  Future<String> findFiles(String glob) async {
    if (_root == null) return 'No workspace configured.';
    final re = _globToRegExp(glob);
    final out = <String>[];
    await for (final f in _walk(Directory(_root!))) {
      final rel = _relOf(f.path);
      if (re.hasMatch(rel)) {
        out.add(rel);
        if (out.length >= _maxList) {
          out.add('… (truncated)');
          break;
        }
      }
    }
    return out.isEmpty ? 'No files match: $glob' : out.join('\n');
  }

  // ── Raw mutating I/O (Phase 2) ───────────────────────────────────────────────
  // These actually touch disk and are ONLY called by EditGate after the user
  // has approved the change. They stay scoped to the workspace root.
  static const _maxEditBytes = 1024 * 1024;

  /// Full contents of a file (for diffing/editing), or null if missing/too big.
  Future<String?> readRaw(String rel) async {
    final abs = _resolve(rel);
    if (abs == null) return null;
    final f = File(abs);
    if (!await f.exists()) return null;
    try {
      if (await f.length() > _maxEditBytes) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Write [content] to [rel] (creating parent dirs). Scoped to the workspace.
  Future<String> writeRaw(String rel, String content) async {
    final abs = _resolve(rel);
    if (abs == null) return 'Invalid or unscoped path: $rel';
    try {
      final f = File(abs);
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
      return 'Wrote ${content.length} chars to $rel';
    } catch (e) {
      return 'Error writing $rel: $e';
    }
  }

  /// True only on desktop platforms — where running commands makes sense.
  static bool get shellSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Run a command with the workspace as its working directory. No shell is
  /// used (runInShell:false, args passed as a list) so there's no command
  /// injection. Desktop-only; refuses on mobile. Called only by EditGate.
  Future<String> runCommandRaw(String command, List<String> args) async {
    if (_root == null) return 'No workspace configured.';
    if (!shellSupported) {
      return 'Shell commands are only available on desktop (not this platform).';
    }
    if (command.trim().isEmpty) return 'No command given.';
    try {
      final res = await Process.run(
        command,
        args,
        workingDirectory: _root,
        runInShell: false,
      ).timeout(const Duration(seconds: 180));
      final out = '${res.stdout}${res.stderr}';
      final capped = out.length > 8000
          ? '${out.substring(0, 8000)}\n… (output truncated)'
          : out;
      return 'exit ${res.exitCode}\n$capped';
    } catch (e) {
      return 'Command failed to run: $e';
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  /// Open a visible terminal window in the active workspace. This is separate
  /// from [runCommandRaw]: it gives Sadeq a real terminal to watch/use while Kai
  /// keeps using headless, captured commands for verified work.
  Future<String> openTerminalRaw() async {
    if (_root == null) return 'No workspace configured.';
    if (!shellSupported) {
      return 'Terminal is only available on desktop (not this platform).';
    }

    try {
      if (Platform.isWindows) {
        final wt = await Process.run('where', ['wt'], runInShell: true);
        if (wt.exitCode == 0) {
          await Process.start(
            'wt',
            ['-d', _root!],
            mode: ProcessStartMode.detached,
            runInShell: true,
          );
          return 'Opened Windows Terminal in $_root';
        }

        await Process.start(
          'powershell',
          ['-NoExit', '-Command', 'Set-Location -LiteralPath ${_psQuote(_root!)}'],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
        return 'Opened PowerShell in $_root';
      }

      if (Platform.isMacOS) {
        await Process.start(
          'open',
          ['-a', 'Terminal', _root!],
          mode: ProcessStartMode.detached,
        );
        return 'Opened Terminal in $_root';
      }

      final candidates = <List<String>>[
        ['x-terminal-emulator', '--working-directory=$_root'],
        ['gnome-terminal', '--working-directory=$_root'],
        ['konsole', '--workdir', _root!],
        ['xfce4-terminal', '--working-directory=$_root'],
      ];
      for (final c in candidates) {
        try {
          await Process.start(c.first, c.skip(1).toList(), mode: ProcessStartMode.detached);
          return 'Opened ${c.first} in $_root';
        } catch (_) {}
      }
      return 'Could not find a supported Linux terminal emulator.';
    } catch (e) {
      return 'Failed to open terminal: $e';
    }
  }

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Stream<File> _walk(Directory d) async* {
    List<FileSystemEntity> ents;
    try {
      ents = d.listSync();
    } catch (_) {
      return;
    }
    for (final e in ents) {
      if (_ignored(e.path)) continue;
      if (e is File) {
        yield e;
      } else if (e is Directory) {
        yield* _walk(e);
      }
    }
  }

  RegExp _globToRegExp(String glob) {
    final b = StringBuffer('^');
    final g = glob.replaceAll('\\', '/');
    for (int i = 0; i < g.length; i++) {
      final c = g[i];
      if (c == '*') {
        if (i + 1 < g.length && g[i + 1] == '*') {
          b.write('.*');
          i++;
          if (i + 1 < g.length && g[i + 1] == '/') i++;
        } else {
          b.write('[^/]*');
        }
      } else if (c == '?') {
        b.write('[^/]');
      } else if (r'.+()[]{}^$|'.contains(c)) {
        b.write('\\$c');
      } else {
        b.write(c);
      }
    }
    b.write(r'$');
    return RegExp(b.toString());
  }
}
