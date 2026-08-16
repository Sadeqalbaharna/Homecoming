import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_status_card.dart';

void main() {
  test('active cortex rail mounts the consolidated status surface', () {
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final active = shell.substring(
      shell.indexOf('Widget _cortexPane()'),
      shell.indexOf('Widget _legacyCortexPane()'),
    );
    expect(active, contains('KaiStatusCard('));
    expect(active, contains('SingleChildScrollView('));
    expect(active, isNot(contains('KaiPresenceCard(')));
    expect(shell, contains("import '../widgets/kai_status_card.dart';"));
    final dashboardRow = shell.substring(
      shell.indexOf('Row(', shell.indexOf('KaiInnerMonologue(')),
      shell.indexOf('_cortexPane(),') + '_cortexPane(),'.length,
    );
    expect(
      dashboardRow,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
  });

  testWidgets('collapsed status occupies less than half a tall rail',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(330, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF050B12),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topCenter,
            child: KaiStatusCard(
              personaId: 'test-kai',
              handsLabel: 'HANDS ON',
              handsColor: const Color(0xFF54F6A3),
              onOpenAtlas: () {},
              atlasPreview: const ColoredBox(color: Color(0xFF081824)),
              expandedDetails: const SizedBox(height: 220),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final collapsed = tester.getSize(find.byKey(const Key('kai-status-card')));
    expect(collapsed.height, lessThan(488));
    expect(find.text('KAI STATUS'), findsOneWidget);
    expect(find.text('HANDS ON'), findsOneWidget);
    expect(find.text('ATLAS'), findsOneWidget);
    expect(find.byKey(const Key('kai-status-personality-mini-map')),
        findsOneWidget);
    expect(find.byKey(const Key('kai-status-mood-strip')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('kai-status-details-toggle')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('kai-status-expanded-details')), findsOneWidget);
    final expanded = tester.getSize(find.byKey(const Key('kai-status-card')));
    expect(expanded.height, greaterThan(collapsed.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Atlas remains an explicit action', (tester) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(330, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KaiStatusCard(
          personaId: 'test-kai',
          onOpenAtlas: () => opened = true,
          atlasPreview: const SizedBox(),
          expandedDetails: const SizedBox(),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('kai-status-open-atlas')));
    expect(opened, isTrue);
  });
}
