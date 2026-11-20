import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/domain/services/unit_conversion.dart';

void main() {
  group('UnitConversion.normalizeUnit', () {
    test('normalizes aliases and casing', () {
      expect(UnitConversion.normalizeUnit(' KG '), 'kg');
      expect(UnitConversion.normalizeUnit('Grams'), 'g');
      expect(UnitConversion.normalizeUnit('millilitres'), 'ml');
      expect(UnitConversion.normalizeUnit('Pieces'), 'pcs');
      expect(UnitConversion.normalizeUnit(''), '');
    });
  });

  group('UnitConversion.convert', () {
    test('converts within the mass family', () {
      expect(UnitConversion.convert(1.5, 'kg', 'g'), closeTo(1500, 0.0001));
      expect(UnitConversion.convert(500, 'g', 'kg'), closeTo(0.5, 0.0001));
      expect(UnitConversion.convert(250, 'mg', 'g'), closeTo(0.25, 0.0001));
    });

    test('converts within the volume family', () {
      expect(UnitConversion.convert(2, 'l', 'ml'), closeTo(2000, 0.0001));
      expect(UnitConversion.convert(750, 'ml', 'l'), closeTo(0.75, 0.0001));
      expect(UnitConversion.convert(1, 'dl', 'ml'), closeTo(100, 0.0001));
    });

    test('returns the value for matching units', () {
      expect(UnitConversion.convert(3, 'pcs', 'pieces'), 3);
    });

    test('throws for incompatible families', () {
      expect(
        () => UnitConversion.convert(1, 'kg', 'ml'),
        throwsA(isA<UnitConversionException>()),
      );
      expect(
        () => UnitConversion.convert(1, 'pcs', 'g'),
        throwsA(isA<UnitConversionException>()),
      );
    });
  });

  group('UnitConversion.costPerUnit', () {
    test('converts inventory cost to recipe unit cost', () {
      final cost = UnitConversion.costPerUnit(
        inventoryUnitCost: 100,
        inventoryUnit: 'kg',
        recipeUnit: 'g',
      );
      expect(cost, closeTo(0.1, 0.0001));
    });

    test('keeps cost when units match', () {
      final cost = UnitConversion.costPerUnit(
        inventoryUnitCost: 12.5,
        inventoryUnit: 'bottle',
        recipeUnit: 'bottles',
      );
      expect(cost, closeTo(12.5, 0.0001));
    });
  });
}
