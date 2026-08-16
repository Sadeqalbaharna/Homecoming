library;

enum KaiFactoryDailyStationState {
  tested,
  sponsorCompleted,
  verifiedLive,
  active,
  future;

  String get label => switch (this) {
        tested => 'TESTED',
        sponsorCompleted => 'SPONSOR-COMPLETED',
        verifiedLive => 'VERIFIED LIVE',
        active => 'ACTIVE',
        future => 'FUTURE',
      };
}

enum KaiFactoryDailyProofState {
  tested,
  sponsorConfirmed,
  verifiedLive,
  liveUnverified,
  unverified;

  String get label => switch (this) {
        tested => 'TESTED',
        sponsorConfirmed => 'SPONSOR-CONFIRMED',
        verifiedLive => 'VERIFIED LIVE',
        liveUnverified => 'LIVE UNVERIFIED',
        unverified => 'UNVERIFIED',
      };
}

class KaiFactoryDailyStation {
  final String id;
  final String label;
  final KaiFactoryDailyStationState state;
  final KaiFactoryDailyProofState proof;
  final String detail;
  final bool isNextGate;

  const KaiFactoryDailyStation({
    required this.id,
    required this.label,
    required this.state,
    required this.proof,
    required this.detail,
    this.isNextGate = false,
  });
}

class KaiFactoryDailyLane {
  final String productId;
  final String productName;
  final List<KaiFactoryDailyStation> stations;
  final String revenueProof;
  final bool hasSettledPayment;

  const KaiFactoryDailyLane({
    required this.productId,
    required this.productName,
    required this.stations,
    required this.revenueProof,
    required this.hasSettledPayment,
  });

  KaiFactoryDailyStation get activeStation => stations.singleWhere(
      (station) => station.state == KaiFactoryDailyStationState.active);

  KaiFactoryDailyStation get nextGate =>
      stations.singleWhere((station) => station.isNextGate);

  KaiFactoryProductMaturity get factoryMaturity {
    final build = stations.singleWhere((station) => station.id == 'build');
    final qaPackaging =
        stations.singleWhere((station) => station.id == 'qa_packaging');
    final publishGate =
        stations.singleWhere((station) => station.id == 'publish_gate');
    final listing =
        stations.singleWhere((station) => station.id == 'gumroad_listing');

    final hasTestedBuild = build.state == KaiFactoryDailyStationState.tested &&
        build.proof == KaiFactoryDailyProofState.tested;
    final hasTestedPackage =
        qaPackaging.state == KaiFactoryDailyStationState.tested &&
            qaPackaging.proof == KaiFactoryDailyProofState.tested;
    final hasSponsorApproval =
        publishGate.state == KaiFactoryDailyStationState.sponsorCompleted &&
            publishGate.proof == KaiFactoryDailyProofState.sponsorConfirmed;
    final hasVerifiedLiveListing =
        listing.state == KaiFactoryDailyStationState.verifiedLive &&
            listing.proof == KaiFactoryDailyProofState.verifiedLive;

    if (hasTestedBuild &&
        hasTestedPackage &&
        hasSponsorApproval &&
        hasVerifiedLiveListing) {
      return KaiFactoryProductMaturity(
        productId: productId,
        productName: productName,
        activePhase: KaiFactoryLinePhase.telemetry,
        reachedPhases: KaiFactoryLinePhase.throughDispatch,
        evidencePhases: const [KaiFactoryLinePhase.telemetry],
        activeProof: KaiFactoryLineActiveProof.unverified,
      );
    }

    return KaiFactoryProductMaturity(
      productId: productId,
      productName: productName,
      activePhase: KaiFactoryLinePhase.signalScan,
      reachedPhases: const [],
      evidencePhases: const [],
      activeProof: KaiFactoryLineActiveProof.unverified,
    );
  }
}

abstract final class KaiFactoryLinePhase {
  static const signalScan = 0;
  static const blueprint = 1;
  static const assembly = 2;
  static const qaGate = 3;
  static const packaging = 4;
  static const approval = 5;
  static const dispatch = 6;
  static const telemetry = 7;
  static const moneyInBank = 8;

  static const throughApproval = [
    signalScan,
    blueprint,
    assembly,
    qaGate,
    packaging,
    approval,
  ];

  static const throughDispatch = [
    ...throughApproval,
    dispatch,
  ];
}

enum KaiFactoryLineActiveProof {
  tested,
  liveUnverified,
  verifiedLive,
  unverified,
}

class KaiFactoryProductMaturity {
  final String productId;
  final String productName;
  final int activePhase;
  final List<int> reachedPhases;
  final List<int> evidencePhases;
  final KaiFactoryLineActiveProof activeProof;

  const KaiFactoryProductMaturity({
    required this.productId,
    required this.productName,
    required this.activePhase,
    required this.reachedPhases,
    required this.evidencePhases,
    required this.activeProof,
  });
}

class KaiFactoryLineMaturity {
  final KaiFactoryProductMaturity leadingProduct;
  final List<KaiFactoryProductMaturity> productLanes;

  const KaiFactoryLineMaturity({
    required this.leadingProduct,
    required this.productLanes,
  });

  int get activePhase => leadingProduct.activePhase;
  List<int> get reachedPhases => leadingProduct.reachedPhases;
  List<int> get evidencePhases => leadingProduct.evidencePhases;
  KaiFactoryLineActiveProof get activeProof => leadingProduct.activeProof;
}

KaiFactoryLineMaturity deriveFactoryLineMaturity(
  List<KaiFactoryProductMaturity> productLanes,
) {
  if (productLanes.isEmpty) {
    throw ArgumentError.value(
        productLanes, 'productLanes', 'must not be empty');
  }
  final ordered = List<KaiFactoryProductMaturity>.of(productLanes)
    ..sort((a, b) {
      final phaseOrder = b.activePhase.compareTo(a.activePhase);
      return phaseOrder != 0 ? phaseOrder : a.productId.compareTo(b.productId);
    });
  return KaiFactoryLineMaturity(
    leadingProduct: ordered.first,
    productLanes: List.unmodifiable(ordered),
  );
}

const findMyTableFactoryMaturity = KaiFactoryProductMaturity(
  productId: 'find_my_table',
  productName: 'Find My Table',
  activePhase: KaiFactoryLinePhase.blueprint,
  reachedPhases: [KaiFactoryLinePhase.signalScan],
  evidencePhases: [KaiFactoryLinePhase.blueprint],
  activeProof: KaiFactoryLineActiveProof.tested,
);

const boothSignalFactoryDailyLane = KaiFactoryDailyLane(
  productId: 'boothsignal',
  productName: 'BoothSignal',
  stations: [
    KaiFactoryDailyStation(
      id: 'build',
      label: 'Build',
      state: KaiFactoryDailyStationState.tested,
      proof: KaiFactoryDailyProofState.tested,
      detail: 'Offline product core and buyer artifact are tested.',
    ),
    KaiFactoryDailyStation(
      id: 'qa_packaging',
      label: 'QA + Packaging',
      state: KaiFactoryDailyStationState.tested,
      proof: KaiFactoryDailyProofState.tested,
      detail:
          'Buyer ZIP, storefront assets, copy, and launch packet are package-ready.',
    ),
    KaiFactoryDailyStation(
      id: 'publish_gate',
      label: 'Publish Gate',
      state: KaiFactoryDailyStationState.sponsorCompleted,
      proof: KaiFactoryDailyProofState.sponsorConfirmed,
      detail: 'Sponsor reports the public-action gate completed.',
    ),
    KaiFactoryDailyStation(
      id: 'gumroad_listing',
      label: 'Gumroad Listing',
      state: KaiFactoryDailyStationState.verifiedLive,
      proof: KaiFactoryDailyProofState.verifiedLive,
      detail:
          'Publicly purchasable at https://salbaharna.gumroad.com/l/boothsignal; \$9 listing with 10 saved tags.',
    ),
    KaiFactoryDailyStation(
      id: 'first_payment',
      label: 'First Payment',
      state: KaiFactoryDailyStationState.active,
      proof: KaiFactoryDailyProofState.unverified,
      detail:
          'Active next gate: first external settled payment and reconciled receipt.',
      isNextGate: true,
    ),
  ],
  revenueProof:
      'UNVERIFIED — no sale, fee, refund, receipt, settlement, or revenue is evidenced.',
  hasSettledPayment: false,
);
