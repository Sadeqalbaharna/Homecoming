import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_project_flowchart_service.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';

void main() {
  const project = KaiProject(
    id: 'homecoming_northstar',
    name: 'Homecoming',
    why: 'One Kai, present across every body.',
    sourceOfTruthPath: 'docs/NORTHSTAR_SOURCE_OF_TRUTH.md',
    repositoryPath: r'C:\code\homecoming_app',
    activePhase: 1,
    blockers: ['Unity editor acceptance is still waiting.'],
    portfolioVisible: true,
    proofState: ProjectProofState.tested,
    layers: [
      KaiLayer(
        n: 0,
        title: 'Baseline',
        intent: 'Freeze the map.',
        checklist: ['Map accepted'],
        checklistStatus: {'Map accepted': ChecklistStatus.trusted},
        evidence: ['Reviewed by Sadeq'],
        state: CapabilityState.trusted,
      ),
      KaiLayer(
        n: 1,
        title: 'Embodiment Foundation',
        intent: 'Four bodies can coexist.',
        checklist: ['Editor acceptance'],
        checklistStatus: {'Editor acceptance': ChecklistStatus.tested},
        state: CapabilityState.tested,
      ),
      KaiLayer(
        n: 2,
        title: 'Device Transport',
        intent: 'Untethered authenticated transport.',
        checklist: ['On-device proof'],
      ),
    ],
  );

  const service = KaiProjectFlowchartService();

  test('renders the four project status categories', () {
    final html = service.buildHtml(project);

    expect(html, contains('>Completed<'));
    expect(html, contains('>In progress<'));
    expect(html, contains('>Blocker<'));
    expect(html, contains('>Future<'));
    expect(html, contains('phase--completed'));
    expect(html, contains('phase--in-progress'));
    expect(html, contains('phase--future'));
  });

  test('renders all phases in governed order with blockers separate', () {
    final html = service.buildHtml(project);

    final baseline = html.indexOf('Baseline');
    final embodiment = html.indexOf('Embodiment Foundation');
    final transport = html.indexOf('Device Transport');
    expect(baseline, greaterThan(-1));
    expect(embodiment, greaterThan(baseline));
    expect(transport, greaterThan(embodiment));
    expect(html, contains('Blockers on active phase 1'));
    expect(html, contains('Unity editor acceptance is still waiting.'));
  });

  test('tested is not silently promoted to completed', () {
    final html = service.buildHtml(project);
    final activeNodeStart =
        html.indexOf('<article class="phase phase--in-progress"');
    final activeNodeEnd = html.indexOf('</article>', activeNodeStart);
    final activeNode = html.substring(activeNodeStart, activeNodeEnd);

    expect(activeNode, contains('Embodiment Foundation'));
    expect(activeNode, contains('Tested'));
    expect(activeNode, isNot(contains('pill completed')));
  });

  test('escapes project content and has no network dependencies', () {
    const hostile = KaiProject(
      id: 'safe',
      name: '<script>alert("x")</script>',
      why: 'A&B',
      layers: [],
    );
    final html = service.buildHtml(hostile);

    expect(html, contains('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'));
    expect(html, isNot(contains('<script>')));
    expect(html, contains('A&amp;B'));
    expect(html, isNot(contains('https://')));
    expect(html, isNot(contains('fetch(')));
  });

  test('writes one deterministic html file for any project', () async {
    final directory =
        await Directory.systemTemp.createTemp('kai_flowchart_test_');
    addTearDown(() => directory.deleteSync(recursive: true));

    final file = await service.write(project, directory: directory);

    expect(file.path, endsWith('homecoming_northstar.html'));
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('<title>Homecoming'));
  });
}
