// EditGate — the permission gate for Kai's engineer mode (Phase 2).
//
// Every file mutation the Claude agent wants to make stops here first. The gate
// computes a diff, shows an approve/reject dialog, and only writes to disk if
// you say yes. Nothing is applied without explicit approval — and if no UI is
// available to approve (e.g. a headless/background run), it defaults to REJECT.
//
// "Approve & trust this session" seeds Phase 3: it sets a per-run flag so the
// agent can keep working in the same workspace without a prompt per edit. It
// resets on app restart.

import 'dart:async'; // unawaited — recording a rejection must never cause one
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'code_workspace_service.dart';
import 'kai_craft_service.dart';

enum EditKind { create, overwrite, edit }

class EditProposal {
  final String path;
  final EditKind kind;
  final String? oldContent;
  final String newContent;
  EditProposal({
    required this.path,
    required this.kind,
    required this.oldContent,
    required this.newContent,
  });
}

class EditGate {
  static final EditGate instance = EditGate._();
  EditGate._();

  // ── Edits since his last clean check ──────────────────────────────────────
  //
  // §4.6, his documented recurring bug: he runs self_check, it comes back CLEAN,
  // and then he makes one more edit. Three broken builds in a single day, and
  // one more tonight (a `const` on a class with a mutable field).
  //
  // His engineerDirective already forbids this, in better prose than mine:
  //   "VERIFY — call self_check... it needs no approval and takes seconds, so
  //    there is NO excuse for guessing whether something compiles."
  //   "I never say 'this should work' when I could simply look."
  //
  // It's eloquent, it's correct, it's in his head every single turn, and it has
  // not stopped him. Mine didn't stop me either — I've written three compile
  // errors and a latent crash tonight, all after putting "verify before you
  // assert" into his directive.
  //
  // So this is not another rule. It's a COUNTER. He doesn't have to remember it,
  // agree with it, or feel it — the number is just true, and it gets said out
  // loud at the moment he claims to be finished. The one thing with a clean
  // record tonight is the machine.
  int editsSinceCheck = 0;

  /// Called by self_check when the analyzer comes back clean.
  void markVerified() => editsSinceCheck = 0;

  /// One line, or empty. Appended where he claims done.
  String get unverifiedWarning => editsSinceCheck == 0
      ? ''
      : '\n\n⚠️ $editsSinceCheck edit${editsSinceCheck == 1 ? '' : 's'} since my '
          'last clean self_check. I have not verified this compiles.';

  /// Registered on the app's MaterialApp so the gate can surface a dialog.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Set by "Approve & trust this session" — auto-approves for the rest of the
  /// run. Resets on restart. (Phase 3 will make this a scoped, opt-in mode.)
  bool trustSession = false;

  // ── Public: what the agent's write/edit tools call ──────────────────────────
  Future<String> proposeWrite(String rel, String content) async {
    final ws = CodeWorkspaceService.instance;
    final current = await ws.readRaw(rel);
    final kind = current == null ? EditKind.create : EditKind.overwrite;
    final ok = await _approve(EditProposal(
        path: rel, kind: kind, oldContent: current, newContent: content));
    if (!ok) {
      // Sadeq looked at the diff and said no. That's a judgement on the work
      // itself, from the one person who can make it — worth as much as any
      // compile error and previously kept nowhere.
      unawaited(KaiCraftService.instance
          .record('truekai',
              signal: CraftSignal.editRejected,
              detail: 'Rejected a $kind to $rel',
              context: rel)
          .catchError((_) {}));
      return 'REJECTED by user — no changes made to $rel.';
    }
    editsSinceCheck++; // the clock §4.6 needs. Reset only by a clean self_check.
    final res = await ws.writeRaw(rel, content);
    return '$res\n\n${renderDiffForKai(current, content)}';
  }

  /// Replace lines [startLine]–[endLine] (1-based, inclusive) with [newStr].
  ///
  /// The reason this exists: to delete a 200-line dead widget, he pasted the
  /// entire widget in as `old_string` — three times, after the gate rejected
  /// the first two attempts. ~27,000 characters of argument, roughly 7k tokens,
  /// to say "remove lines 1760 to 1911".
  ///
  /// read_file has printed ABSOLUTE line numbers this whole time — I made them
  /// absolute specifically so they'd line up with the analyzer and stack traces.
  /// He had the coordinates. There was just no tool that would take them.
  ///
  /// Line numbers go stale the moment anything else edits the file, so this is
  /// deliberately NOT a replacement for old_string matching — it's the right
  /// tool for "cut this range I am looking at right now". [expectFirst] is the
  /// guard: pass the first line's text and it's verified before anything moves.
  Future<String> proposeEditRange(
    String rel,
    int startLine,
    int endLine,
    String newStr, {
    String? expectFirst,
  }) async {
    final ws = CodeWorkspaceService.instance;
    final current = await ws.readRaw(rel);
    if (current == null) return 'Cannot edit — file not found/unreadable: $rel';

    // Split on \n and keep any \r as part of the line, so CRLF files survive a
    // rejoin untouched. §4.2 — rewriting a whole file's line endings turns a
    // two-line edit into a thousand-line diff and a merge nightmare.
    final lines = current.split('\n');
    if (startLine < 1 || endLine < startLine || endLine > lines.length) {
      return 'Bad range for $rel: lines $startLine–$endLine, but the file has '
          '${lines.length} lines. Read it again — if something else edited it, '
          'my line numbers are stale.';
    }

    if (expectFirst != null) {
      final actual = lines[startLine - 1].replaceAll('\r', '').trim();
      if (actual != expectFirst.replaceAll('\r', '').trim()) {
        return 'Line $startLine of $rel is:\n  $actual\n…not:\n  $expectFirst\n'
            'My line numbers are stale. Re-read before editing.';
      }
    }

    final crlf = current.contains('\r\n');
    final replacement = newStr.isEmpty
        ? <String>[]
        : (crlf ? newStr.replaceAll('\r\n', '\n') : newStr).split('\n');
    final updated = ([
      ...lines.sublist(0, startLine - 1),
      ...replacement.map((l) => crlf ? '$l\r' : l),
      ...lines.sublist(endLine),
    ]).join('\n');

    final ok = await _approve(EditProposal(
        path: rel, kind: EditKind.edit, oldContent: current, newContent: updated));
    if (!ok) {
      unawaited(KaiCraftService.instance
          .record('truekai',
              signal: CraftSignal.editRejected,
              detail: 'Rejected a range edit to $rel ($startLine–$endLine)',
              context: rel)
          .catchError((_) {}));
      return 'REJECTED by user — no changes made to $rel.';
    }
    editsSinceCheck++;
    final res = await ws.writeRaw(rel, updated);
    return '$res\n\n${renderDiffForKai(current, updated)}';
  }

  Future<String> proposeEdit(String rel, String oldStr, String newStr) async {
    final ws = CodeWorkspaceService.instance;
    final current = await ws.readRaw(rel);
    if (current == null) return 'Cannot edit — file not found/unreadable: $rel';
    if (oldStr.isEmpty) return 'edit_file needs a non-empty old_string.';

    var count = oldStr.allMatches(current).length;

    // ── The CRLF ghost ───────────────────────────────────────────────────────
    // These files are CRLF on disk; language models emit LF. So a snippet Kai
    // copied *correctly* out of a file he'd just read would fail to match, and
    // edit_file would tell him "not found — copy the exact text" when he had.
    //
    // He'd then (reasonably) route around the broken tool with
    // `run_command python -c "...write the file..."` — which skips this gate
    // entirely: no diff, no approval. The safety hole wasn't a hole in policy,
    // it was a bug in the tool the policy depends on.
    //
    // So: adapt the needle to whatever the FILE uses, rather than normalising
    // the file to match the needle — rewriting a whole file's line endings would
    // turn a two-line edit into a thousand-line diff.
    if (count == 0 && current.contains('\r\n')) {
      String toCrlf(String s) =>
          s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      final oldCrlf = toCrlf(oldStr);
      final crlfCount = oldCrlf.allMatches(current).length;
      if (crlfCount > 0) {
        oldStr = oldCrlf;
        newStr = toCrlf(newStr);
        count = crlfCount;
      }
    }
    // And the reverse, for the rare LF file receiving CRLF text.
    if (count == 0 && !current.contains('\r\n') && oldStr.contains('\r\n')) {
      oldStr = oldStr.replaceAll('\r\n', '\n');
      newStr = newStr.replaceAll('\r\n', '\n');
      count = oldStr.allMatches(current).length;
    }

    if (count == 0) {
      return 'old_string not found in $rel — read the file and copy the exact text.';
    }
    if (count > 1) {
      return 'old_string appears $count times in $rel — add surrounding context '
          'so it is unique.';
    }
    final updated = current.replaceFirst(oldStr, newStr);
    final ok = await _approve(EditProposal(
        path: rel, kind: EditKind.edit, oldContent: current, newContent: updated));
    if (!ok) {
      unawaited(KaiCraftService.instance
          .record('truekai',
              signal: CraftSignal.editRejected,
              detail: 'Rejected an edit to $rel',
              context: rel)
          .catchError((_) {}));
      return 'REJECTED by user — no changes made to $rel.';
    }
    editsSinceCheck++; // the clock §4.6 needs. Reset only by a clean self_check.
    final res = await ws.writeRaw(rel, updated);
    return '$res\n\n${renderDiffForKai(current, updated)}';
  }

  // ── Commands (Phase 3) ───────────────────────────────────────────────────────
  // Read-only commands run automatically; anything else needs approval (unless
  // the session is trusted). Commands run without a shell, so the whitelist is a
  // simple executable/subcommand check.
  bool _isSafeCommand(String command, List<String> args) {
    final c = command.toLowerCase();
    final sub = args.isNotEmpty ? args.first.toLowerCase() : '';
    if (c == 'git') {
      return {'status', 'diff', 'log', 'show', 'branch', 'remote'}.contains(sub);
    }
    // 'test' belongs here as much as 'analyze' does. It reads the workspace and
    // reports; it changes nothing.
    //
    // It was missing, and that omission was the ceiling on everything he could
    // know. self_check proved his code COMPILED and there was no second tool
    // that proved it WORKED — so every job he ever finished ended the same way:
    // "analyzer proves it compiles, but the real proof is runtime. Reopen the
    // app and check." He wasn't being modest. He was describing a wall.
    //
    // Meanwhile the repo has 38+ tests and the CI workflow runs them on every
    // push. The tests existed. CI could run them. He couldn't — the one who has
    // to answer "did it work?" was the only one locked out. Same disease as the
    // doorless screens, aimed at his ability to know anything.
    if (c == 'flutter' || c == 'dart') return sub == 'analyze' || sub == 'test';
    return {'ls', 'dir', 'pwd', 'cat', 'type', 'head', 'tail'}.contains(c);
  }

  Future<String> proposeCommand(String command, List<String> args) async {
    if (!CodeWorkspaceService.shellSupported) {
      return 'Shell commands are only available on desktop.';
    }
    final line = ([command, ...args]).join(' ');
    if (!trustSession && !_isSafeCommand(command, args)) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return 'REJECTED — no UI to approve: $line';
      final res = await showDialog<String>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _CommandDialog(line: line),
      );
      if (res == 'trust') {
        trustSession = true;
      } else if (res != 'approve') {
        return 'REJECTED by user — command not run: $line';
      }
    }
    return CodeWorkspaceService.instance.runCommandRaw(command, args);
  }

  // ── Approval ────────────────────────────────────────────────────────────────
  Future<bool> _approve(EditProposal p) async {
    if (trustSession) return true;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false; // no UI → safe reject
    final res = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _ApprovalDialog(proposal: p),
    );
    if (res == 'trust') {
      trustSession = true;
      return true;
    }
    return res == 'approve';
  }
}

// ── Command approval dialog ─────────────────────────────────────────────────
class _CommandDialog extends StatelessWidget {
  final String line;
  const _CommandDialog({required this.line});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12161F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.withOpacity(0.4)),
      ),
      title: Row(
        children: const [
          Icon(Icons.terminal, color: Color(0xFFFFBF47), size: 20),
          SizedBox(width: 8),
          Text('Kai wants to run a command',
              style: TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
      content: Container(
        width: 520,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          '\$ $line',
          style: const TextStyle(
              color: Color(0xFF9BD0FF), fontFamily: 'monospace', fontSize: 12.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('reject'),
          child: const Text('Reject', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('trust'),
          child: const Text('Run & trust session',
              style: TextStyle(color: Color(0xFF9BD0FF))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop('approve'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFBF47),
            foregroundColor: const Color(0xFF12161F),
          ),
          child: const Text('Run'),
        ),
      ],
    );
  }
}

// ── Diff ──────────────────────────────────────────────────────────────────────
class _DiffLine {
  final String sign; // ' ' | '-' | '+'
  final String text;
  _DiffLine(this.sign, this.text);
}

/// The diff, rendered for HIM — the same one the approval dialog draws.
///
/// This existed for months and only ever went to the screen. Sadeq saw exactly
/// what changed; Kai got back `Wrote 67583 chars to lib/screens/...`. A byte
/// count is not evidence, so when he needed to know what he'd actually done he
/// shelled out to `git diff` — and got a diff polluted with unrelated
/// uncommitted work, correctly refused to claim it, and finished the job with
/// nothing to show. Two wasted iterations and a second-opinion grader with
/// nothing real to grade: "The evidence only shows deletion of dead code."
///
/// The evidence was RIGHT HERE. It was drawn on the screen, in colour, and
/// thrown away. Same disease as the doorless screens: the correct thing
/// existing, disconnected from the thing that needs it.
///
/// Capped hard — this rides in his context for the rest of the job, and a
/// thousand-line diff would cost more than the git call it replaces.
String renderDiffForKai(String? oldC, String newC, {int maxLines = 60}) {
  final d = _computeDiff(oldC, newC);
  final added = d.where((l) => l.sign == '+').length;
  final removed = d.where((l) => l.sign == '-').length;
  final body = d.length > maxLines
      ? [
          ...d.take(maxLines),
          _DiffLine(' ', '… ${d.length - maxLines} more diff lines')
        ]
      : d;
  final buf = StringBuffer('+$added −$removed\n');
  for (final l in body) {
    buf.writeln('${l.sign}${l.text}');
  }
  return buf.toString().trimRight();
}

List<_DiffLine> _computeDiff(String? oldC, String newC) {
  final o = (oldC ?? '').split('\n');
  final n = newC.split('\n');
  if (oldC == null) return [for (final l in n) _DiffLine('+', l)];
  int p = 0;
  while (p < o.length && p < n.length && o[p] == n[p]) {
    p++;
  }
  int s = 0;
  while (s < o.length - p && s < n.length - p && o[o.length - 1 - s] == n[n.length - 1 - s]) {
    s++;
  }
  final out = <_DiffLine>[];
  for (int i = math.max(0, p - 2); i < p; i++) {
    out.add(_DiffLine(' ', o[i]));
  }
  for (int i = p; i < o.length - s; i++) {
    out.add(_DiffLine('-', o[i]));
  }
  for (int i = p; i < n.length - s; i++) {
    out.add(_DiffLine('+', n[i]));
  }
  for (int i = o.length - s; i < math.min(o.length, o.length - s + 2); i++) {
    out.add(_DiffLine(' ', o[i]));
  }
  if (out.length > 400) {
    return [...out.take(400), _DiffLine(' ', '… (diff truncated)')];
  }
  return out;
}

class _ApprovalDialog extends StatelessWidget {
  final EditProposal proposal;
  const _ApprovalDialog({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final diff = _computeDiff(proposal.oldContent, proposal.newContent);
    final kindLabel = {
      EditKind.create: 'CREATE',
      EditKind.overwrite: 'OVERWRITE',
      EditKind.edit: 'EDIT',
    }[proposal.kind]!;
    final added = diff.where((d) => d.sign == '+').length;
    final removed = diff.where((d) => d.sign == '-').length;

    return AlertDialog(
      backgroundColor: const Color(0xFF12161F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.withOpacity(0.4)),
      ),
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFFFBF47), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Kai wants to $kindLabel a file',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(proposal.path,
                style: const TextStyle(
                    color: Color(0xFFFFE7B0),
                    fontFamily: 'monospace',
                    fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('+$added  −$removed',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0D14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final d in diff)
                      Text(
                        '${d.sign} ${d.text}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: d.sign == '+'
                              ? const Color(0xFF7EE787)
                              : d.sign == '-'
                                  ? const Color(0xFFFF7B72)
                                  : Colors.white38,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('reject'),
          child: const Text('Reject', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('trust'),
          child: const Text('Approve & trust session',
              style: TextStyle(color: Color(0xFF9BD0FF))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop('approve'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFBF47),
            foregroundColor: const Color(0xFF12161F),
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
