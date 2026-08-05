import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_cortex_view.dart';

void main() {
  test('native brain map exposes atlas chamber navigation affordances', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('class _MemoryAtlasHud extends StatelessWidget'));
    expect(source, contains('LIVING MEMORY ATLAS'));
    expect(source, contains('tap a memory to enter its chamber'));
    expect(source, contains('RESET ATLAS'));
    expect(source, contains('ENTER CHAMBER'));
    expect(source, contains("_hudChip('semantic zoom', semanticZoomBand)"));
    expect(source, contains("_hudChip('quest path', 'AR cockpit')"));
  });

  test('native atlas HUD exposes semantic zoom bands', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('String get _semanticZoomBand'));
    expect(source, contains("return 'constellation'"));
    expect(source, contains("return 'memory chamber'"));
    expect(source, contains("return 'neighbourhood'"));
    expect(source, contains('required this.semanticZoomBand'));
  });

  test('atlas can reset and focus the InteractiveViewer camera into a chamber', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('static const double _memoryChamberFocusScale = 2.15'));
    expect(source, contains('TransformationController _controller'));
    expect(source, contains('void _travelToMemoryChamber('));
    expect(source, contains('void _focusMemoryChamber('));
    expect(source, contains('center.dx - graphPoint.dx * scale'));
    expect(source, contains('center.dy - graphPoint.dy * scale'));
    expect(source, contains('setState(() => _atlasZoom = scale)'));
    expect(source, contains('void _resetAtlasView()'));
    expect(source, contains('setState(() => _atlasZoom = 1.0)'));
    expect(source, contains('Matrix4.identity()'));
  });

  test('atlas accepts persisted spatial positions before falling back to generated layout', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('Offset? _readPersistedAtlasPosition(Map<String, dynamic> raw)'));
    expect(source, contains("raw['atlasPosition']"));
    expect(source, contains("atlasPosition['x']"));
    expect(source, contains("atlasPosition['y']"));
    expect(source, contains("raw['atlasX'] ?? raw['x']"));
    expect(source, contains("raw['atlasY'] ?? raw['y']"));
    expect(source, contains('_readPersistedAtlasPosition(raw) ?? fallbackPos'));
  });

  test('atlas drag writes spatial positions back to the graph record', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('Future<void> Function(String nodeId, Offset position) onNodePositioned'));
    expect(source, contains('Future<void> _finishNodeDrag() async'));
    expect(source, contains('await widget.onNodePositioned(node.id, position)'));
    expect(source, contains('(position - startPosition).distance > 1'));
    expect(source, contains("rawNode['atlasPosition'] = {'x': position.dx, 'y': position.dy}"));
    expect(source, contains(".ref('knowledge_graph/\${widget.personaId}/nodes/\$nodeIndex')"));
    expect(source, contains("'atlasPosition': {'x': position.dx, 'y': position.dy}"));
    expect(source, contains("'atlasX': position.dx"));
    expect(source, contains("'atlasY': position.dy"));
  });

  test('atlas drag exposes save feedback in the HUD', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('String? _atlasPositionStatus'));
    expect(source, contains("_atlasPositionStatus = 'saving…'"));
    expect(source, contains("setState(() => _atlasPositionStatus = 'saved')"));
    expect(source, contains("setState(() => _atlasPositionStatus = 'save failed')"));
    expect(source, contains('required this.positionStatus'));
    expect(source, contains("_hudChip('atlas position', positionStatus!)"));
  });

  test('native brain map focuses selected cortex neighborhoods', () {
    final source = File('lib/screens/brain_3d_screen.dart').readAsStringSync();

    expect(source, contains('_focusedNodeIdsFor'));
    expect(source, contains('_paintFocusReticle'));
    expect(source, contains('focusActive && !focused'));
    expect(source, contains('? 0.86'));
    expect(source, contains('0.025'));
  });

  test('desktop dashboard exposes an obvious Atlas access door', () {
    final source = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();

    expect(source, contains("title: 'ATLAS'"));
    expect(source, contains("child: const Text('OPEN ATLAS')"));
    expect(source, contains('KaiCortexScreen(personaId: _kPersona)'));
  });

  test('mobile home exposes Atlas and opens the Living Memory Atlas route', () {
    final source = File('lib/main_mobile.dart').readAsStringSync();

    expect(source, contains("label: 'Atlas'"));
    expect(source, contains('KaiCortexScreen(personaId: _personaId)'));
    expect(source, isNot(contains("label: 'Brain'")));
    expect(source, isNot(contains('Brain3DScreen(personaId: _personaId)')));
  });

  test('desktop native fallback keeps Atlas identity visible in compact mode', () {
    final source = File('lib/widgets/kai_graph_3d.dart').readAsStringSync();

    expect(source, contains('class _CompactAtlasBadge extends StatelessWidget'));
    expect(source, contains("'ATLAS'"));
    expect(source, contains(r"'$nodeCount memories · $edgeCount links'"));
    expect(source, contains('widget.compact\n                        ? _CompactAtlasBadge'));
  });

  testWidgets('full-screen cortex route presents Living Memory Atlas beta identity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: KaiCortexScreen(personaId: 'test-persona'),
    ));

    expect(find.text('Living Memory Atlas · Beta'), findsOneWidget);
    expect(find.text('Kai · Cortex'), findsNothing);
  });
}
