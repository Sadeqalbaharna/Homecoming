// Full, inspectable execution map behind a portfolio card.
//
// Windows has no embedded WebView implementation in this app, so the map is a
// self-contained local HTML document opened by the default browser. It has no
// network dependencies and derives every project fact from KaiProject.
library;

import 'dart:io';

import 'kai_project_service.dart';

class KaiProjectFlowchartService {
  const KaiProjectFlowchartService();

  /// Builds a complete offline document. Public for deterministic testing.
  String buildHtml(KaiProject project) {
    final name = _escape(project.name.isEmpty ? project.id : project.name);
    final phases = [...project.layers]..sort((a, b) => a.n.compareTo(b.n));
    final nodes = <String>[];

    for (var index = 0; index < phases.length; index++) {
      final phase = phases[index];
      final status = _statusFor(project, phase);
      final css = switch (status) {
        _PhaseStatus.completed => 'completed',
        _PhaseStatus.inProgress => 'in-progress',
        _PhaseStatus.future => 'future',
      };
      final label = switch (status) {
        _PhaseStatus.completed => 'Completed',
        _PhaseStatus.inProgress => 'In progress',
        _PhaseStatus.future => 'Future',
      };
      final gates = phase.checklist.isEmpty
          ? '<li class="muted">No frozen exit gate recorded.</li>'
          : phase.checklist.map((item) {
              final state =
                  phase.checklistStatus[item] ?? ChecklistStatus.pending;
              return '<li><b>${_escape(state.label)}</b>${_escape(item)}</li>';
            }).join();
      final evidence = phase.evidence.isEmpty
          ? '<li class="muted">No evidence recorded yet.</li>'
          : phase.evidence.map((item) => '<li>${_escape(item)}</li>').join();

      nodes.add('''
        <article class="phase phase--$css" aria-label="Phase ${phase.n}: ${_escape(phase.title)}, $label">
          <div class="top"><span class="number">${phase.n}</span><span class="pill $css">$label</span></div>
          <h2>${_escape(phase.title)}</h2>
          <p class="outcome">${_escape(phase.intent)}</p>
          <div class="proof"><span>${phase.honestProgress}% gate evidence</span><span>${_escape(phase.state.label)}</span></div>
          ${phase.stamp.trim().isEmpty ? '' : '<p class="stamp">${_escape(phase.stamp)}</p>'}
          <details>
            <summary>Exit gate and evidence</summary>
            <h3>Exit gate</h3><ul class="gate">$gates</ul>
            <h3>Evidence</h3><ul>$evidence</ul>
          </details>
        </article>
        ${index == phases.length - 1 ? '' : '<div class="connector" aria-hidden="true">&#8594;</div>'}
      ''');
    }

    final blockers = project.blockers.isEmpty
        ? '<section class="blockers clear"><strong><i></i>No blockers recorded</strong></section>'
        : '''<section class="blockers" aria-label="Blockers">
          <strong><i></i>Blockers on active phase ${project.activePhase}</strong>
          <ul>${project.blockers.map((item) => '<li>${_escape(item)}</li>').join()}</ul>
        </section>''';

    final source = _escape(project.sourceOfTruthPath);
    final repository = _escape(project.repositoryPath);
    return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$name — Project flowchart</title>
  <style>
    :root{color-scheme:dark;--bg:#071018;--panel:#0d1923;--ink:#e8f1f5;--muted:#91a3ad;--line:#263945;--complete:#42d38b;--active:#ffb548;--blocked:#ff5d68;--future:#7e919c;--cyan:#44d8ee}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;color:var(--ink);background:radial-gradient(circle at 18% 4%,rgba(68,216,238,.10),transparent 30rem),linear-gradient(rgba(68,216,238,.035) 1px,transparent 1px),linear-gradient(90deg,rgba(68,216,238,.035) 1px,transparent 1px),var(--bg);background-size:auto,40px 40px,40px 40px,auto;font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
    main{width:min(1800px,96vw);margin:auto;padding:46px 0 70px}header{display:grid;grid-template-columns:1fr auto;gap:24px;align-items:end}.eyebrow{color:var(--cyan);font-size:12px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}h1{margin:8px 0;font-size:clamp(34px,5vw,72px);line-height:.96}.why{max-width:900px;color:#b8c7cf;font-size:18px;line-height:1.55}
    .meta{min-width:290px;padding:16px;border:1px solid var(--line);background:rgba(13,25,35,.88);border-radius:16px}.meta div{display:flex;justify-content:space-between;gap:18px;padding:5px 0;font-size:12px}.meta span:first-child{color:var(--muted)}.meta span:last-child{text-align:right;word-break:break-word}
    .legend{display:flex;flex-wrap:wrap;gap:10px;margin:28px 0 18px}.legend span,.pill{border:1px solid currentColor;border-radius:999px;padding:6px 10px;font-size:11px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}.legend span:before{content:'';display:inline-block;width:8px;height:8px;margin-right:7px;border-radius:50%;background:currentColor}.completed{color:var(--complete)}.in-progress{color:var(--active)}.blocker{color:var(--blocked)}.future{color:var(--future)}
    .flowchart{display:flex;align-items:stretch;overflow-x:auto;padding:16px 4px 28px;scroll-snap-type:x proximity}.phase{flex:0 0 310px;min-height:370px;padding:20px;border:1px solid var(--line);border-top-width:5px;border-radius:18px;background:linear-gradient(145deg,rgba(17,34,45,.97),rgba(9,18,26,.97));scroll-snap-align:start;box-shadow:0 18px 44px rgba(0,0,0,.24)}.phase--completed{border-top-color:var(--complete)}.phase--in-progress{border-color:rgba(255,181,72,.54);border-top-color:var(--active);box-shadow:0 0 34px rgba(255,181,72,.10),0 18px 44px rgba(0,0,0,.24)}.phase--future{border-top-color:var(--future);opacity:.78}
    .top,.proof{display:flex;justify-content:space-between;align-items:center;gap:12px}.number{display:grid;place-items:center;width:42px;height:42px;border:1px solid var(--cyan);border-radius:12px;color:var(--cyan);font-size:20px;font-weight:900}.phase h2{min-height:58px;margin:18px 0 10px;font-size:23px;line-height:1.2}.outcome{min-height:92px;color:#bdcad1;line-height:1.5}.proof{margin-top:16px;padding-top:12px;border-top:1px solid var(--line);color:var(--muted);font-size:11px}.stamp{color:var(--active);font-size:12px;font-style:italic}
    details{margin-top:16px;border-top:1px dashed var(--line);padding-top:12px}summary{cursor:pointer;color:var(--cyan);font-size:12px;font-weight:800}details h3{margin:14px 0 5px;color:var(--muted);font-size:10px;letter-spacing:.1em;text-transform:uppercase}ul{margin:7px 0;padding-left:20px;color:#bdcad1;font-size:12px;line-height:1.5}.gate b{display:inline-block;min-width:66px;margin-right:7px;color:var(--cyan);font-size:9px;text-transform:uppercase}.muted{color:var(--muted);font-style:italic}.connector{flex:0 0 48px;display:grid;place-items:center;color:var(--cyan);font-size:28px;opacity:.66}
    .blockers{margin-top:6px;padding:18px 20px;border:1px solid rgba(255,93,104,.52);border-left:6px solid var(--blocked);border-radius:14px;background:rgba(64,17,24,.45)}.blockers strong{color:var(--blocked);font-size:12px;letter-spacing:.08em;text-transform:uppercase}.blockers i{display:inline-block;width:10px;height:10px;margin-right:9px;border-radius:50%;background:currentColor;box-shadow:0 0 14px currentColor}.blockers ul{margin-bottom:0;color:#ffd3d6}.blockers.clear{border-color:rgba(66,211,139,.35);border-left-color:var(--complete);background:rgba(16,55,42,.34)}.blockers.clear strong{color:var(--complete)}footer{margin-top:22px;color:var(--muted);font-size:11px}
    @media(max-width:760px){main{padding-top:28px}header{grid-template-columns:1fr}.meta{min-width:0}.phase{flex-basis:min(84vw,310px)}.connector{flex-basis:34px}}@media print{body{background:#fff;color:#111}main{width:100%;padding:10px}.flowchart{overflow:visible;flex-wrap:wrap;gap:10px}.connector{display:none}.phase{flex:1 1 290px;break-inside:avoid;box-shadow:none}}
  </style>
</head>
<body><main>
  <header><div><div class="eyebrow">Kai project execution map</div><h1>$name</h1><p class="why">${_escape(project.why)}</p></div>
    <aside class="meta">
      <div><span>Project proof</span><span>${_escape(project.proofState.label)}</span></div>
      <div><span>Accepted phases</span><span>${project.acceptedPhases} / ${project.layers.length}</span></div>
      <div><span>Active phase</span><span>${project.activePhase < 0 ? 'Unstated' : project.activePhase}</span></div>
      ${source.isEmpty ? '' : '<div><span>Source of truth</span><span>$source</span></div>'}
      ${repository.isEmpty ? '' : '<div><span>Repository</span><span>$repository</span></div>'}
    </aside>
  </header>
  <section class="legend" aria-label="Status legend"><span class="completed">Completed</span><span class="in-progress">In progress</span><span class="blocker">Blocker</span><span class="future">Future</span></section>
  <section class="flowchart" aria-label="$name project phases">${nodes.join()}</section>
  $blockers
  <footer>Generated from the same frozen project phases and live proof state used by the Homecoming desktop portfolio. This diagram is a view, not a second tracker.</footer>
</main></body></html>''';
  }

  Future<File> write(KaiProject project, {Directory? directory}) async {
    final target = directory ??
        Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}homecoming_project_flowcharts',
        );
    await target.create(recursive: true);
    final safeId = project.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
      '${target.path}${Platform.pathSeparator}${safeId.isEmpty ? 'project' : safeId}.html',
    );
    return file.writeAsString(buildHtml(project), flush: true);
  }

  Future<File> open(KaiProject project) async {
    final file = await write(project);
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        [file.path],
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isMacOS) {
      await Process.start('open', [file.path], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start(
        'xdg-open',
        [file.path],
        mode: ProcessStartMode.detached,
      );
    } else {
      throw UnsupportedError('Project flowcharts require a desktop platform.');
    }
    return file;
  }

  static _PhaseStatus _statusFor(KaiProject project, KaiLayer phase) {
    if (phase.honestProgress >= 100) return _PhaseStatus.completed;
    if (phase.n == project.activePhase) return _PhaseStatus.inProgress;
    return _PhaseStatus.future;
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

enum _PhaseStatus { completed, inProgress, future }
