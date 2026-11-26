import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/business_kpis.dart';
import 'package:smarteat/features/finance/data/report_period.dart';

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

  group('BusinessKpis date-aware reports', () {
    test('actualCogsFromMovements uses absolute cost impact', () {
      final cogs = BusinessKpis.actualCogsFromMovements([
        {
          'type': 'saleConsumption',
          'timestamp': '2026-10-05T10:00:00.000Z',
          'totalCostImpact': -12.5,
        },
      ]);

      expect(cogs.amount, 12.5);
      expect(cogs.isEstimated, isFalse);
    });

    test('resolveCogs estimates only selected month performance', () {
      final range = ReportPeriod.monthRange(DateTime(2026, 10, 15));
      final cogs = BusinessKpis.resolveCogs(
        stockMovements: const [],
        itemPerformance: [
          {
            'date': '2026-10-04',
            'revenue': 100.0,
            'quantitySold': 2,
            'costPerServing': 5.0,
          },
          {
            'date': '2026-11-04',
            'revenue': 200.0,
            'quantitySold': 2,
            'costPerServing': 9.0,
          },
        ],
        start: range.start,
        end: range.end,
      );

      expect(cogs.isEstimated, isTrue);
      expect(cogs.amount, 10);
    });

    test('inventoryKpi reconstructs stock through asOf', () {
      final kpi = BusinessKpis.inventoryKpi(
        inventoryItems: [
          {
            'id': 'inv-1',
            'currentStock': 99,
            'lastPurchaseCost': 10,
          },
        ],
        damagedItems: const [],
        stockMovements: [
          {
            'itemId': 'inv-1',
            'changeBase': 5,
            'timestamp': '2026-10-02T10:00:00.000Z',
          },
          {
            'itemId': 'inv-1',
            'changeBase': -2,
            'timestamp': '2026-11-02T10:00:00.000Z',
          },
        ],
        asOf: ReportPeriod.endOfMonth(DateTime(2026, 10, 1)),
      );

      expect(kpi.inventoryValue, 50);
    });

    test('payablesKpi asOf limits outstanding to bills due by month end', () {
      final kpi = BusinessKpis.payablesKpi(
        [
          {
            'amount': 100,
            'status': 'unpaid',
            'dueDate': '2026-10-15T00:00:00.000Z',
          },
          {
            'amount': 200,
            'status': 'unpaid',
            'dueDate': '2026-11-15T00:00:00.000Z',
          },
        ],
        asOf: ReportPeriod.endOfMonth(DateTime(2026, 10, 1)),
      );

      expect(kpi.outstanding, 100);
    });

    test('forecastKpi anchorMonth filters dated forecast points', () {
      final kpi = BusinessKpis.forecastKpi(
        salesForecast: [
          {
            'date': '2026-10-01T00:00:00.000Z',
            'predictedRevenue': 100,
          },
          {
            'date': '2026-11-01T00:00:00.000Z',
            'predictedRevenue': 999,
          },
        ],
        menuProfitRowsData: const [],
        anchorMonth: DateTime(2026, 10, 1),
      );

      expect(kpi.forecastRevenue, 100);
    });
  });
}
