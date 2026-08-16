import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_transcript_echo_guard.dart';

void main() {
  test('consumes one exact local user and Kai echo', () {
    final guard = KaiTranscriptEchoGuard();
    guard.expect(fromKai: false, text: 'goggles on');
    guard.expect(fromKai: true, text: 'Hands attached.');

    expect(
      guard.consumeIfExpected(fromKai: false, text: 'goggles on'),
      isTrue,
    );
    expect(
      guard.consumeIfExpected(fromKai: true, text: 'Hands attached.'),
      isTrue,
    );
    expect(
      guard.consumeIfExpected(fromKai: true, text: 'Hands attached.'),
      isFalse,
      reason: 'a second identical message may be a real later message',
    );
  });

  test('does not consume another body or different text', () {
    final guard = KaiTranscriptEchoGuard();
    guard.expect(fromKai: false, text: 'local turn');

    expect(
      guard.consumeIfExpected(fromKai: true, text: 'local turn'),
      isFalse,
    );
    expect(
      guard.consumeIfExpected(fromKai: false, text: 'other turn'),
      isFalse,
    );
  });

  test('normalizes line endings but preserves content identity', () {
    final guard = KaiTranscriptEchoGuard();
    guard.expect(fromKai: true, text: 'one\r\n\r\ntwo');

    expect(
      guard.consumeIfExpected(fromKai: true, text: ' one\n\ntwo '),
      isTrue,
    );
  });

  test('expired expectations do not hide later real messages', () {
    final guard = KaiTranscriptEchoGuard(ttl: const Duration(seconds: 5));
    final start = DateTime.utc(2026, 8, 8, 9);
    guard.expect(fromKai: true, text: 'same words', now: start);

    expect(
      guard.consumeIfExpected(
        fromKai: true,
        text: 'same words',
        now: start.add(const Duration(seconds: 6)),
      ),
      isFalse,
    );
  });

  test('cancel removes an expectation when the stream won the race', () {
    final guard = KaiTranscriptEchoGuard();
    guard.expect(fromKai: true, text: 'reply');
    guard.cancel(fromKai: true, text: 'reply');

    expect(
      guard.consumeIfExpected(fromKai: true, text: 'reply'),
      isFalse,
    );
  });

  test('desktop advances the history cursor before dropping expected echoes',
      () {
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final watcher = shell.substring(
      shell.indexOf('void _watchDesktopHistory()'),
      shell.indexOf('void dispose()'),
    );

    final cursorAdvance = watcher.indexOf('_lastDesktopHistoryMillis = lines');
    final emptyReturn = watcher.indexOf('if (fresh.isEmpty) return;');
    expect(cursorAdvance, greaterThan(-1));
    expect(emptyReturn, greaterThan(cursorAdvance),
        reason: 'consumed one-shot echoes must not return on the next poll');
    expect(watcher, contains('_transcriptEchoGuard.consumeIfExpected'));
  });
}
