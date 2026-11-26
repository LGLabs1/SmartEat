import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/data/models/stock_movement.dart';
import 'package:smarteat/features/inventory/domain/usecases/cogs.dart';

StockMovement _consumption({
  required String id,
  required DateTime timestamp,
  required double cost,
}) {
  return StockMovement(
    id: id,
    itemId: 'inv-1',
    type: StockMovementType.saleConsumption,
    referenceType: StockMovementRefType.order,
    qtyBeforeBase: 10,
    qtyAfterBase: 8,
    changeBase: -2,
    unitCostAtEvent: cost / 2,
    totalCostImpact: -cost,
    timestamp: timestamp,
  );
}

void main() {
  group('CogsUseCase', () {
    test('sums absolute sale consumption cost impact', () {
      final cogs = CogsUseCase().compute([
        _consumption(id: 'm1', timestamp: DateTime(2026, 10, 5), cost: 12.5),
        _consumption(id: 'm2', timestamp: DateTime(2026, 10, 6), cost: 7.5),
      ]);

      expect(cogs, 20);
    });

    test('filters sale consumption by from and to dates', () {
      final movements = [
        _consumption(id: 'm1', timestamp: DateTime(2026, 9, 30), cost: 5),
        _consumption(id: 'm2', timestamp: DateTime(2026, 10, 15), cost: 8),
        _consumption(id: 'm3', timestamp: DateTime(2026, 11, 1), cost: 13),
      ];
      final cogs = CogsUseCase().compute(
        movements,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31, 23, 59, 59, 999),
      );

      expect(cogs, 8);
    });
  });
}
