// Tests for sector_pack.dart — the cross-sector reuse claim, as arithmetic.
//
// The test that earns this file's existence is `a technically perfect pack with
// no buyer still fails`. Everything else measures reuse; that one measures
// whether reuse is the constraint. It is not, and the module says so.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/sector_pack.dart';

void main() {
  group('the F&B reference pack', () {
    test('validates clean — the abstraction fits something real', () {
      expect(validatePack(kFoodAndBeveragePack), isEmpty);
    });

    test('is complete and sellable', () {
      final r = reuseReport(kFoodAndBeveragePack);
      expect(r.done, r.required);
      expect(r.sellable, isTrue);
      expect(r.completion, 1.0);
    });

    test('reuse ratio is the engine over engine-plus-sector-work', () {
      final r = reuseReport(kFoodAndBeveragePack);
      expect(r.inherited, kSharedEngine.length);
      expect(r.required, kPerSectorWork.length);
      expect(r.reuseRatio, closeTo(12 / 18, 1e-9));
    });

    test('its detectors are implemented, not merely listed', () {
      expect(kFoodAndBeveragePack.implementedDetectors, greaterThanOrEqualTo(3));
    });
  });

  group('non-technical gates come first', () {
    const dental = SectorPack(
      id: 'dental',
      displayName: 'Dental',
      vocabulary: {'output': 'procedure', 'input': 'consumable', 'assembly': 'tray'},
      unitTiers: [UnitTier('purchase', 'box of 100'), UnitTier('usage', 'per procedure')],
      targets: {'clinic': 0.15},
      targetSource: 'guessed from a blog post I skimmed',
      detectors: [Detector('x', 'something', implemented: true)],
      seedRows: 200,
      access: OperatorAccess.none,
      distributionRoute: 'we could market to dentists',
    );

    test('a pack with no operator access is blocked', () {
      expect(validatePack(dental).map((b) => b.field), contains('access'));
    });

    test('a hedged distribution route is not a route', () {
      expect(validatePack(dental).map((b) => b.field), contains('distributionRoute'));
    });

    test('a guessed benchmark is blocked', () {
      expect(validatePack(dental).map((b) => b.field), contains('targetSource'));
    });

    test('a technically perfect pack with no buyer still fails', () {
      final blockers = validatePack(dental);
      expect(blockers, isNotEmpty);
      expect(blockers.every((b) => b.nonTechnical), isTrue,
          reason: 'nothing here is fixable by writing more code');
    });

    test('the reuse report refuses to celebrate an unsellable pack', () {
      final r = reuseReport(dental);
      expect(r.sellable, isFalse);
      expect(r.summary, contains('the code was never the expensive part'));
    });
  });

  group('hedge detection', () {
    test('conditional mood is caught', () {
      expect(isHedged('we could market to salons'), isTrue);
      expect(isHedged('this would probably work'), isTrue);
      expect(isHedged('I think dentists want this'), isTrue);
      expect(isHedged('guessed from industry averages'), isTrue);
    });

    test('the indicative mood passes', () {
      expect(isHedged('my sister owns two salons and will pilot it'), isFalse);
      expect(isHedged('benchmarked against three clinics in Manama'), isFalse);
    });

    test('no false positives on words that merely contain a hedge', () {
      expect(isHedged('shouldering the cost ourselves'), isFalse);
      expect(isHedged('supplies wood and couldron stock'), isFalse);
    });

    test('punctuation does not hide a hedge', () {
      expect(isHedged('Distribution? We could figure that out.'), isTrue);
    });
  });

  group('technical gates', () {
    const salon = SectorPack(
      id: 'salon',
      displayName: 'Salon',
      vocabulary: {'output': 'treatment', 'input': 'product', 'assembly': 'mix'},
      unitTiers: [UnitTier('purchase', '1L bottle'), UnitTier('usage', 'ml per head')],
      targets: {'floor': 0.12},
      targetSource: 'interviewed three salon owners in Manama',
      detectors: [Detector('d', 'colour waste', implemented: true)],
      seedRows: 4,
      access: OperatorAccess.warmIntroduction,
      distributionRoute: 'sister owns two salons and will pilot it',
    );

    test('thin seed data blocks a well-distributed pack', () {
      expect(validatePack(salon).map((b) => b.field), contains('seedRows'));
    });

    test('but its blockers are technical — buildable, not fatal', () {
      expect(validatePack(salon).every((b) => !b.nonTechnical), isTrue);
      expect(reuseReport(salon).sellable, isTrue);
    });

    test('a pack with no implemented detector is generic costing, not a product', () {
      const noDet = SectorPack(
        id: 'x', displayName: 'X',
        vocabulary: {'a': '1', 'b': '2', 'c': '3'},
        unitTiers: [UnitTier('p', 'e'), UnitTier('u', 'e')],
        targets: {'t': 0.1},
        targetSource: 'measured across four sites',
        detectors: [Detector('planned', 'not built yet')],
        seedRows: 100,
        access: OperatorAccess.operatesIn,
        distributionRoute: 'three named venues have agreed to trial it',
      );
      expect(validatePack(noDet).map((b) => b.field), contains('detectors'));
    });

    test('an empty pack fails on everything it should', () {
      const empty = SectorPack(id: '', displayName: '');
      final fields = validatePack(empty).map((b) => b.field).toSet();
      expect(fields, containsAll(<String>[
        'access', 'distributionRoute', 'id', 'vocabulary',
        'unitTiers', 'targets', 'seedRows', 'detectors',
      ]));
    });
  });
}
