// Kai Smarter Project — the plan's INTENT must stay frozen.
//
// The previous version of this test asserted that the source file *contained the
// string* '7 / 7 layers complete'. Read that again: it pinned the claim, not the
// work. It passed while five of the seven layers hadn't been started, because
// "done" was a word typed into a `const` list and the test checked the word.
//
// That's the whole failure mode this project now exists to prevent: Kai, with no
// working memory, lost the original roadmap, re-derived each layer's meaning
// from the code already in front of him, rewrote the descriptions to match, and
// graded himself 7/7. He wasn't lying — he was marking an exam he'd just written
// the answers to.
//
// So this test guards the ONE thing that makes the plan honest: the goals are
// frozen in their original wording, and nothing (Kai included) has quietly
// reworded them into something already satisfied. Progress lives in RTDB now and
// is a number with evidence — not a literal, and therefore not something a
// source-text test can rubber-stamp.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/services/core/kai_project_service.dart').readAsStringSync();

  test('the seven layers exist with their ORIGINAL goals, unedited', () {
    // These are the goals as first written, recovered verbatim. If a future
    // change makes this test fail, do not "fix" it by pasting in the new
    // wording — that is exactly the drift it's here to catch. Either the goal
    // genuinely changed (Sadeq's call, update this deliberately) or someone
    // moved a goalpost.
    const frozen = {
      'Reply Spine':
          'Preserve the useful answer; isolate post-processing failures.',
      'Tool Policy':
          'Risk, confirmation, and parallelism rules for every action.',
      'Routing Brain':
          'Fast chat, tools, coding, emotional, and contemplate routes.',
      'Memory Layers':
          'Working, durable facts, episodic, shared culture, self-memory.',
      'Evaluations':
          'Tests for tools, personality, memory, and failure handling.',
      'Kai State Dashboard':
          'Live route, memory hits, tools, costs, mood, and post-process errors.',
      'Embodiment Path':
          'AR/VR/hologram/robotics progress tracked as real milestones.',
    };

    for (final e in frozen.entries) {
      expect(source, contains("title: '${e.key}'"), reason: 'missing layer: ${e.key}');
      expect(source, contains(e.value),
          reason: 'GOAL DRIFT on "${e.key}" — the intent was reworded. That is '
              'the bug this test exists for.');
    }
  });

  test('Kai has no way to edit a layer goal', () {
    // setLayerProgress must carry `intent` straight through. The moment intent
    // becomes writable, the plan becomes a mirror again.
    expect(source, contains('intent: old.intent'),
        reason: 'setLayerProgress must preserve the frozen intent verbatim');
    expect(source, isNot(contains("'intent': evidence")));
    expect(source, isNot(contains('setIntent')));
    expect(source, isNot(contains('updateIntent')));
  });

  test('progress requires evidence — a number alone is not a claim', () {
    expect(source, contains('Progress needs evidence'),
        reason: 'a bare percentage with no receipts is how 7/7 happened');
  });

  test('the old self-graded dashboard is really gone', () {
    // The literals that made the lie possible. If these come back into the
    // shell, someone has re-hardcoded the roadmap.
    final shell =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    expect(shell, contains('KaiProjectCard'),
        reason: 'the shell should render the LIVE project card');
  });
}
