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
  /// Cap on a WHOLE-FILE read only. A ranged read ignores this entirely — see
  /// readFile. 700 lines is the real token guard; bytes never were.
  static const _maxFileBytes = 120 * 1024;

  /// Grep reads a file line-by-line and keeps nothing, so it can afford far
  /// more than a whole-file read can. It shared `_maxFileBytes` for no reason
  /// other than the constant being nearby — and that coincidence is what made
  /// ai_service.dart (130 KB) invisible to the tool he navigates with.
  ///
  /// Whatever this is set to, the SKIP IS REPORTED. That's the part that
  /// matters; a limit is fine, a silent limit is a lie.
  static const _searchMaxFileBytes = 2 * 1024 * 1024;

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

  /// Acquire the Homecoming repo without making the model guess a path.
  /// Used when a persisted coding job resumes before a workspace was restored.
  Future<bool> ensureHomecomingWorkspace() async {
    await load();

    bool valid(String? path) {
      if (path == null || path.trim().isEmpty) return false;
      final root = Directory(path.trim());
      return root.existsSync() &&
          File('${root.path}${Platform.pathSeparator}pubspec.yaml').existsSync() &&
          Directory('${root.path}${Platform.pathSeparator}lib').existsSync();
    }

    if (valid(_root)) return true;

    for (final project in _projects) {
      if (nameOf(project).toLowerCase() == 'homecoming_app' && valid(project)) {
        await setRoot(project);
        return true;
      }
    }

    final candidates = <String>[];
    var cursor = Directory.current;
    for (var i = 0; i < 8; i++) {
      candidates.add(cursor.path);
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }
    if (Platform.isWindows) candidates.add(r'C:\code\homecoming_app');

    for (final candidate in candidates) {
      if (nameOf(candidate).toLowerCase() == 'homecoming_app' && valid(candidate)) {
        await setRoot(candidate);
        return true;
      }
    }
    return false;
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
    if (r.isEmpty || r == '.') return _root;
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
  /// Read a file, optionally a window of it.
  ///
  /// ── This was blinding him ────────────────────────────────────────────────
  ///
  /// It used to be `lines.take(700)` — the FIRST 700 lines, always, with no way
  /// to ask for any others. kai_desktop_shell.dart is ~2,041 lines. Everything
  /// past line 700 of his own biggest file was unreachable through his own file
  /// reader. Not slow, not awkward: unreachable.
  ///
  /// So he built a file reader out of Python, at runtime, every time:
  ///
  ///   run_command(python, [-c, "lines=Path('...').read_text().splitlines()
  ///                             for i in range(1600,1705): print(...)"])
  ///
  /// …and paid for it in UTF-8 crashes on the Windows console, wasted
  /// iterations, and — worst of all — misplaced blame: "the normal reader is
  /// lying about line numbers", "exactly the tool goblin Claude warned about".
  /// It wasn't lying and it wasn't the mount. It stopped at 700 and never said
  /// so in a way he could act on. He assumed the fault was his environment,
  /// because that's what he'd been taught to assume.
  ///
  /// §10.1. Every single time. Check what he was handed.
  ///
  /// Four things matter here:
  ///   • the WINDOW is capped, not the file — any 700 lines, not the first 700
  ///   • line numbers are ABSOLUTE, so they line up with the analyzer,
  ///     self_check, and the stack traces he's reading them against
  ///   • the truncation notice tells him HOW TO CONTINUE instead of leaving him
  ///     to invent a workaround
  ///   • the gutter ends at a '│' and NOTHING else in the line is ours
  ///
  /// That last one was a fresh wound of exactly the same species as the 700.
  /// The gutter used to be two spaces:
  ///
  ///     '${' 493'}  ' + '  void _autoscroll() {'   →   ' 493    void _autoscroll() {'
  ///
  /// Four spaces between the number and the code: two gutter, two indentation,
  /// and no way on earth to tell which is which. So he copied it out for an
  /// edit_file with the indentation guessed wrong, got "old_string not found",
  /// and — because he had no reason to suspect the reader — assumed the tool
  /// was being fussy about line endings. NINE consecutive failed edits. Nine
  /// gpt-5.5 round trips at a 64k system prompt. He only escaped by shelling
  /// out to Python to print the raw bytes, at which point he found it
  /// instantly: "the helper lives at class indentation, not nested".
  ///
  /// He was right about the fix from iteration 13. He spent eight more
  /// fighting the thing that was supposed to be helping him read.
  ///
  /// §10.1 again, and note the shape: BOTH failures here were the reader
  /// quietly mangling what it handed him, and BOTH times he blamed his
  /// environment. He will always blame his environment, because a tool that
  /// lies is indistinguishable from one that's broken. The fix is not to tell
  /// him to trust the reader. The fix is to make the reader unambiguous.
  Future<String> readFile(String rel, {int? startLine, int? endLine}) async {
    final abs = _resolve(rel);
    if (abs == null) return 'Invalid or unscoped path: $rel';
    final f = File(abs);
    if (!await f.exists()) return 'No such file: $rel';
    try {
      // ── A line range is ALWAYS servable, whatever the file weighs ────────
      //
      // This used to be a flat `if (len > _maxFileBytes) return 'File too
      // large — search it instead.'` — and it refused a request for FORTY
      // LINES because the file around them was big:
      //
      //   read_file(ai_service.dart, start_line: 300, end_line: 340)
      //     → "File too large (130 KB): — search it instead."
      //   search_code('sendMessage', glob: 'ai_service.dart')
      //     → "No matches"          ← in the file that DEFINES sendMessage
      //
      // Two readers pointing at each other, both lying. He burned about fifteen
      // iterations writing python line-dumpers to read his own brain, and said
      // so: "Yep, search lied to me there — real disk has the symbols."
      //
      // The size cap only ever made sense as a TOKEN guard, and _maxLines
      // already is one. A windowed read of a 130KB file costs exactly the same
      // as a windowed read of a 5KB file. So: bytes only limit the WHOLE-FILE
      // read, never a range.
      final len = await f.length();
      final windowedRequest = startLine != null || endLine != null;
      if (len > _maxFileBytes && !windowedRequest) {
        final lineCount = await _countLines(f);
        return 'That file is ${(len / 1024).round()} KB — too big to hand back '
            'whole, but NOT too big to read. It has $lineCount lines.\n'
            'Ask for a range and I will give you every one of them:\n'
            '  read_file(path: "$rel", start_line: 1, end_line: $_maxLines)\n'
            'Or find the spot first with search_code, then read around it.';
      }
      final bytes = await f.readAsBytes();
      if (bytes.contains(0)) return 'Binary file (skipped): $rel';
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      final total = lines.length;
      if (total == 0) return '// $rel\n(empty)';

      // Clamp rather than throw: an off-by-one on a range should show him the
      // nearest real lines, not an error on top of the thing he was already
      // debugging.
      final from = (startLine ?? 1).clamp(1, total);
      var to = (endLine ?? total).clamp(from, total);
      final windowed = startLine != null || endLine != null;
      if (to - from + 1 > _maxLines) to = from + _maxLines - 1;

      final shown = lines.sublist(from - 1, to);
      final width = to.toString().length + 1;
      // '│' and not two spaces. The delimiter has to be a character that
      // cannot be confused with indentation, because the whole failure mode
      // is him not knowing where our gutter stops and his code starts.
      final numbered = [
        for (int i = 0; i < shown.length; i++)
          '${(from + i).toString().padLeft(width)}│${shown[i]}'
      ].join('\n');

      // Say it out loud. He can't infer the convention from one look at the
      // output, and inferring wrong costs him ten iterations of "old_string
      // not found" with no clue pointing back here.
      const gutterNote = '// Everything left of │ is the reader, not the file. '
          'Content starts immediately after │ — copy from there for edit_file.';

      final head = (windowed || to < total)
          ? '// $rel  (lines $from–$to of $total)\n$gutterNote'
          : '// $rel\n$gutterNote';
      final more = to < total
          ? '\n… ${total - to} more lines. Read them with '
              'read_file(path: "$rel", start_line: ${to + 1})'
          : '';
      return '$head\n$numbered$more';
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

    // ── It must never say "no matches" about a file it did not read ────────
    //
    // This loop used to `continue` on any file over the cap — SILENTLY — and
    // then return "No matches". Which produced this, in a real session:
    //
    //   search_code('sendMessage', glob: 'lib/services/ai/ai_service.dart')
    //     → No matches for /sendMessage/
    //
    // …in the file that DEFINES sendMessage. That is not a limitation, it is a
    // false statement. It cost him roughly fifteen iterations and a pile of
    // hand-written python before he worked out the tool was lying:
    //
    //   "That's suspicious: the file exists but has none of the symbols the
    //    shell compiles against."
    //   "Yep, search lied to me there — real disk has the symbols."
    //
    // Right again. That is the FIFTH reader failure in two days — the 700-line
    // truncation, the two-space gutter, Process.run's encoding, the stale mount,
    // and now this — and every single time his instinct that the tooling was
    // wrong turned out to be correct.
    //
    // "I didn't look there" and "there's nothing there" are different answers.
    // A tool that cannot tell them apart must say which one it means.
    final skipped = <String>[];

    await for (final f in _walk(Directory(_root!))) {
      final rel = _relOf(f.path);
      if (globRe != null && !globRe.hasMatch(rel)) continue;
      try {
        if (await f.length() > _searchMaxFileBytes) {
          skipped.add(rel);
          continue;
        }
        final bytes = await f.readAsBytes();
        if (bytes.contains(0)) continue;
        final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (re.hasMatch(lines[i])) {
            out.add('$rel:${i + 1}: ${lines[i].trim()}');
            if (++count >= _maxGrep) {
              out.add('… (truncated at $_maxGrep matches)');
              return out.join('\n');
            }
          }
        }
      } catch (_) {}
    }

    final note = skipped.isEmpty
        ? ''
        : '\n\n⚠️ I did NOT search ${skipped.length} file(s) — each over '
            '${_searchMaxFileBytes ~/ 1024} KB:\n'
            '${skipped.map((s) => '  • $s').join('\n')}\n'
            'So this is "I did not look there", NOT "it is not there". Read '
            'those by line range instead — read_file serves any range at any '
            'file size.';

    if (out.isEmpty) {
      return skipped.isEmpty
          ? 'No matches for /$pattern/'
          : 'No matches for /$pattern/ in the files I searched.$note';
    }
    return '${out.join('\n')}$note';
  }

  /// Line count without ever holding the file as one string — so the "too big
  /// to hand back whole" message can still tell him exactly how many lines he
  /// can ask for.
  Future<int> _countLines(File f) async {
    try {
      var n = 0;
      await for (final chunk in f.openRead()) {
        for (final b in chunk) {
          if (b == 0x0A) n++;
        }
      }
      return n + 1;
    } catch (_) {
      return -1;
    }
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

  /// Windows resolves `flutter` → `flutter.bat` using PATHEXT, and PATHEXT is a
  /// SHELL feature. With `runInShell: false` — which is what makes command
  /// injection impossible here, and is worth keeping — `Process.run('flutter',
  /// …)` simply cannot find it. So `run_tests` was born broken:
  ///
  ///   "Running pub get through real Flutter path, because our wrapper goblin
  ///    is still PATH-busted."
  ///   run_command(C:\code\flutter\bin\flutter.bat, [pub, get])  → exit 0
  ///
  /// He routed around his own tool with an absolute path and got on with it,
  /// which is exactly the kind of quiet competence that hides a broken tool for
  /// months.
  ///
  /// `where` IS a real executable, so it needs no shell either — no injection
  /// surface is added. Args still go as a list; only the executable is resolved.
  static final Map<String, String> _exeCache = {};

  Future<String> _resolveExecutable(String command) async {
    if (!Platform.isWindows) return command;
    // Already an explicit path — nothing to resolve.
    if (command.contains(RegExp(r'[\\/]'))) return command;
    final hit = _exeCache[command];
    if (hit != null) return hit;
    try {
      final r = await Process.run('where', [command], runInShell: false);
      if (r.exitCode == 0) {
        final found = (r.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        // `where flutter` lists the extensionless shim FIRST, and that one
        // cannot be executed without a shell. Prefer something runnable.
        final runnable = found.firstWhere(
          (p) {
            final l = p.toLowerCase();
            return l.endsWith('.bat') || l.endsWith('.cmd') || l.endsWith('.exe');
          },
          orElse: () => found.isEmpty ? command : found.first,
        );
        _exeCache[command] = runnable;
        return runnable;
      }
    } catch (_) {}
    return command;
  }

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
      // stdoutEncoding/stderrEncoding are NOT optional here.
      //
      // Dart defaults both to systemEncoding. On Windows that's the ANSI code
      // page — Windows-1252 — so every byte of UTF-8 output from git, python
      // or flutter got decoded with the wrong table before he ever saw it.
      // An em dash is E2 80 94; read as Windows-1252 that is exactly "â€”".
      //
      // He spotted the symptom himself and misfiled it as cosmetic: "existing
      // mojibake in a comment near _Parallax, likely CRLF/encoding weirdness;
      // harmless but ugly". It was neither pre-existing nor harmless. It was
      // this function, live, handing him a corrupted copy of his own source —
      // and anything he copies out of a run_command result and back into an
      // edit_file writes that corruption to disk for real.
      //
      // Same species as the 700-line truncation and the two-space gutter: the
      // tool that was supposed to let him see quietly altered what it showed
      // him, and he blamed the environment. Third time. It is always the
      // reader.
      //
      // allowMalformed because output that genuinely isn't UTF-8 should come
      // through as replacement characters, not throw and lose the whole result.
      const outEnc = Utf8Codec(allowMalformed: true);
      final exe = await _resolveExecutable(command);
      final res = await Process.run(
        exe,
        args,
        workingDirectory: _root,
        runInShell: false,
        stdoutEncoding: outEnc,
        stderrEncoding: outEnc,
      ).timeout(const Duration(seconds: 180));
      final out = '${res.stdout}${res.stderr}';

      // ── Keep the END. That's where the verdict is. ────────────────────────
      //
      // This used to be `out.substring(0, 8000)` — head only — and it quietly
      // broke the one tool built so he could prove his work.
      //
      // `flutter test` on 161 tests is chatty, so the output blows past 8000
      // chars long before the last line, which is the ONLY line that matters:
      //
      //     00:04 +161: All tests passed!
      //
      // Head-truncation amputates it. run_tests then can't find "All tests
      // passed", falls through, and reports a green suite as FAILING. A
      // targeted test on one file is short enough to survive, so the bug hid
      // behind "well it works for the small case".
      //
      // He caught it: "It launched, and the raw output begins with exit 0. But
      // the wrapper labelled it FAILING... That is not a real test failure."
      //
      // Test runners put the answer last. Compilers put errors in the middle.
      // Keep both ends and say what was dropped — the middle of a 161-test
      // progress log is the only part nobody has ever needed.
      const headMax = 3000;
      const tailMax = 5000;
      String capped;
      if (out.length <= headMax + tailMax) {
        capped = out;
      } else {
        final cut = out.length - headMax - tailMax;
        capped = '${out.substring(0, headMax)}\n'
            '… [$cut chars of middle dropped — head and TAIL kept, because the '
            'verdict lives at the end] …\n'
            '${out.substring(out.length - tailMax)}';
      }
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
