import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/business_kpis.dart';

void main() {
  group('BusinessKpis.menuProfitRows', () {
    test('reads analytics aliases and falls back to unit costing', () {
      final rows = BusinessKpis.menuProfitRows([
        {
          'name': 'Iced Coffee',
          'revenueLast30Days': 250.0,
          'soldLast30Days': 25,
          'costPerServing': null,
          'costPerUnit': 5.0,
        },
      ]);

      expect(rows, hasLength(1));
      expect(rows.first.revenue, 250);
      expect(rows.first.quantity, 25);
      expect(rows.first.hasCosting, isTrue);
      expect(rows.first.estimatedCogs, 125);
    });

    test('prefers explicit serving cost over unit cost', () {
      final rows = BusinessKpis.menuProfitRows([
        {
          'name': 'Frappe',
          'revenue': 200.0,
          'quantitySold': 10,
          'costPerServing': 8.0,
          'costPerUnit': 20.0,
        },
      ]);

      expect(rows.first.estimatedCogs, 80);
    });

    test('uses direct inventory unit cost when recipe cost is absent', () {
      final rows = BusinessKpis.menuProfitRows([
        {
          'name': 'Bottled Coffee',
          'revenue': 300.0,
          'quantitySold': 3,
          'price': 100.0,
          'inventoryItemId': 'inv-1',
          'directUnitCost': 60.0,
          'costingSource': 'direct_inventory',
        },
      ]);

      expect(rows.first.hasCosting, isTrue);
      expect(rows.first.estimatedCogs, 180);
      expect(rows.first.profit, 120);
      expect(rows.first.profitPerItem, 40);
    });

    test('keeps recipe cost ahead of direct inventory cost', () {
      final rows = BusinessKpis.menuProfitRows([
        {
          'name': 'Latte',
          'revenue': 100.0,
          'quantitySold': 2,
          'costPerServing': 20.0,
          'directUnitCost': 60.0,
        },
      ]);

      expect(rows.first.estimatedCogs, 40);
      expect(rows.first.profitPerItem, 30);
    });

    test('marks rows without any costing as missing', () {
      final rows = BusinessKpis.menuProfitRows([
        {
          'name': 'Uncosted Item',
          'revenue': 100.0,
          'quantitySold': 2,
        },
      ]);

      expect(rows.first.hasCosting, isFalse);
      expect(rows.first.estimatedCogs, 0);
    });
  });
}
