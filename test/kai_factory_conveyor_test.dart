import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_factory_conveyor.dart';

void main() {
  testWidgets('approval station is the interactive human gate', (tester) async {
    int? tappedStation;
    final stations = <KaiFactoryStationVisual>[
      const KaiFactoryStationVisual(
        name: 'SIGNAL SCAN',
        icon: Icons.radar,
        status: KaiFactoryStationStatus.complete,
      ),
      const KaiFactoryStationVisual(
        name: 'BLUEPRINT',
        icon: Icons.schema_outlined,
        status: KaiFactoryStationStatus.complete,
      ),
      const KaiFactoryStationVisual(
        name: 'ASSEMBLY',
        icon: Icons.precision_manufacturing_outlined,
        status: KaiFactoryStationStatus.complete,
      ),
      const KaiFactoryStationVisual(
        name: 'QA GATE',
        icon: Icons.fact_check_outlined,
        status: KaiFactoryStationStatus.complete,
      ),
      const KaiFactoryStationVisual(
        name: 'PACKAGING',
        icon: Icons.inventory_2_outlined,
        status: KaiFactoryStationStatus.complete,
      ),
      const KaiFactoryStationVisual(
        name: 'APPROVAL',
        icon: Icons.approval_outlined,
        status: KaiFactoryStationStatus.waitingApproval,
        pendingBoxes: 1,
      ),
      const KaiFactoryStationVisual(
        name: 'DISPATCH',
        icon: Icons.local_shipping_outlined,
        status: KaiFactoryStationStatus.queued,
      ),
      const KaiFactoryStationVisual(
        name: 'TELEMETRY',
        icon: Icons.query_stats_outlined,
        status: KaiFactoryStationStatus.queued,
      ),
      const KaiFactoryStationVisual(
        name: 'FEEDBACK',
        icon: Icons.loop,
        status: KaiFactoryStationStatus.queued,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: KaiFactoryConveyor(
              stations: stations,
              currentIndex: 5,
              lineRunning: false,
              interactiveIndex: 5,
              onStationTap: (index) => tappedStation = index,
            ),
          ),
        ),
      ),
    );

    expect(find.text('WAITING APPROVAL'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('factory-box-count-5')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('factory-box-count-0')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('6 APPROVAL'));
    await tester.pump();

    expect(tappedStation, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
