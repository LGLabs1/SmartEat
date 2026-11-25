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
  });
}
