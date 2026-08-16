import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_factory_daily_lane.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';
import 'package:homecoming_app/widgets/kai_project_portfolio.dart';

void main() {
  test('BoothSignal stations preserve the sponsor/live proof boundary', () {
    const lane = boothSignalFactoryDailyLane;
    expect(lane.productId, 'boothsignal');
    expect(lane.stations.map((station) => station.id), [
      'build',
      'qa_packaging',
      'publish_gate',
      'gumroad_listing',
      'first_payment',
    ]);
    expect(lane.stations[0].state, KaiFactoryDailyStationState.tested);
    expect(lane.stations[1].state, KaiFactoryDailyStationState.tested);
    expect(
      lane.stations[2].state,
      KaiFactoryDailyStationState.sponsorCompleted,
    );
    expect(lane.stations[3].state, KaiFactoryDailyStationState.verifiedLive);
    expect(
      lane.stations[3].proof,
      KaiFactoryDailyProofState.verifiedLive,
    );
    expect(lane.activeStation.id, 'first_payment');
    expect(lane.nextGate.id, 'first_payment');
    expect(lane.nextGate.state, KaiFactoryDailyStationState.active);
    expect(lane.hasSettledPayment, isFalse);
    expect(lane.revenueProof, contains('no sale'));
    expect(lane.revenueProof, contains('fee'));
    expect(lane.revenueProof, contains('revenue'));
  });

  test('typed product lanes advance the Factory line without merging lanes',
      () {
    final boothSignal = boothSignalFactoryDailyLane.factoryMaturity;
    expect(boothSignal.activePhase, KaiFactoryLinePhase.telemetry);
    expect(boothSignal.reachedPhases, KaiFactoryLinePhase.throughDispatch);
    expect(boothSignal.evidencePhases, [KaiFactoryLinePhase.telemetry]);
    expect(
      boothSignal.activeProof,
      KaiFactoryLineActiveProof.unverified,
    );

    final line = deriveFactoryLineMaturity([
      findMyTableFactoryMaturity,
      boothSignal,
    ]);
    expect(line.leadingProduct.productId, 'boothsignal');
    expect(line.activePhase, KaiFactoryLinePhase.telemetry);
    expect(line.reachedPhases, [0, 1, 2, 3, 4, 5, 6]);
    expect(line.evidencePhases, [7]);
    expect(line.reachedPhases, isNot(contains(KaiFactoryLinePhase.telemetry)));
    expect(
      line.reachedPhases,
      isNot(contains(KaiFactoryLinePhase.moneyInBank)),
    );

    expect(
        findMyTableFactoryMaturity.activePhase, KaiFactoryLinePhase.blueprint);
    expect(KaiProjectService.factoryPacketAcceptedPhasesForTest, [0]);
    expect(KaiProjectService.factoryBlueprintEvidencePhasesForTest, [1]);
    expect(KaiProjectService.factoryLineMaturityForTest.activePhase, 7);
    expect(KaiProjectService.factoryLineMaturityForTest.reachedPhases,
        [0, 1, 2, 3, 4, 5, 6]);
    expect(KaiProjectService.factoryPhasesForTest.length, 9);
  });

  test('listing prose cannot advance the line without typed listing evidence',
      () {
    const unverifiedListingLane = KaiFactoryDailyLane(
      productId: 'unverified-listing',
      productName: 'Unverified Listing',
      stations: [
        KaiFactoryDailyStation(
          id: 'build',
          label: 'Build',
          state: KaiFactoryDailyStationState.tested,
          proof: KaiFactoryDailyProofState.tested,
          detail: 'Tested build.',
        ),
        KaiFactoryDailyStation(
          id: 'qa_packaging',
          label: 'QA + Packaging',
          state: KaiFactoryDailyStationState.tested,
          proof: KaiFactoryDailyProofState.tested,
          detail: 'Tested package.',
        ),
        KaiFactoryDailyStation(
          id: 'publish_gate',
          label: 'Publish Gate',
          state: KaiFactoryDailyStationState.sponsorCompleted,
          proof: KaiFactoryDailyProofState.sponsorConfirmed,
          detail: 'Sponsor completed.',
        ),
        KaiFactoryDailyStation(
          id: 'gumroad_listing',
          label: 'Gumroad Listing',
          state: KaiFactoryDailyStationState.future,
          proof: KaiFactoryDailyProofState.unverified,
          detail: 'This prose says ACTIVE on Gumroad, but has no typed proof.',
        ),
        KaiFactoryDailyStation(
          id: 'first_payment',
          label: 'First Payment',
          state: KaiFactoryDailyStationState.future,
          proof: KaiFactoryDailyProofState.unverified,
          detail: 'Future.',
          isNextGate: true,
        ),
      ],
      revenueProof: 'UNVERIFIED',
      hasSettledPayment: false,
    );

    expect(
      unverifiedListingLane.factoryMaturity.activePhase,
      KaiFactoryLinePhase.signalScan,
    );
    expect(unverifiedListingLane.factoryMaturity.reachedPhases, isEmpty);
  });

  testWidgets('Factory Daily panel renders every station without overflow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: KaiFactoryDailyLanePanel(
                lane: boothSignalFactoryDailyLane,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('FACTORY DAILY / BOOTHSIGNAL'), findsOneWidget);
    expect(find.textContaining('BUILD  •  TESTED'), findsOneWidget);
    expect(find.textContaining('QA + PACKAGING  •  TESTED'), findsOneWidget);
    expect(
      find.textContaining('PUBLISH GATE  •  SPONSOR-COMPLETED'),
      findsOneWidget,
    );
    expect(find.textContaining('GUMROAD LISTING  •  VERIFIED LIVE'),
        findsOneWidget);
    expect(
      find.textContaining('FIRST PAYMENT  •  ACTIVE  •  NEXT GATE'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('factory-daily-revenue-proof')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
