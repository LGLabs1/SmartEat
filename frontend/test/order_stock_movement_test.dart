import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/domain/services/order_stock_movement.dart';

void main() {
  group('order consumption stock movements', () {
    test('movement id is deterministic per order and item', () {
      expect(
        orderConsumptionMovementId('order-42', 'item-7'),
        'sale_order-42_item-7',
      );
      expect(
        orderConsumptionMovementId('order-42', 'item-7'),
        orderConsumptionMovementId(' order-42 ', ' item-7 '),
      );
    });

    test('payload records before, after, delta, cost, and order reference', () {
      final timestamp = DateTime(2026, 11, 23, 10, 30);
      final movement = buildOrderConsumptionMovement(
        orderId: 'order-42',
        eateryId: 'eatery-1',
        itemId: 'item-7',
        qtyBeforeBase: 12,
        qtyAfterBase: 9.5,
        changeBase: -2.5,
        unitCostAtEvent: 20,
        timestamp: timestamp,
        performedBy: 'uid-1',
      );

      expect(movement['id'], 'sale_order-42_item-7');
      expect(movement['eateryId'], 'eatery-1');
      expect(movement['itemId'], 'item-7');
      expect(movement['type'], 'saleConsumption');
      expect(movement['referenceType'], 'order');
      expect(movement['referenceId'], 'order-42');
      expect(movement['qtyBeforeBase'], 12);
      expect(movement['qtyAfterBase'], 9.5);
      expect(movement['changeBase'], -2.5);
      expect(movement['unitCostAtEvent'], 20);
      expect(movement['totalCostImpact'], -50);
      expect(movement['performedBy'], 'uid-1');
      expect(movement['timestamp'], timestamp);
      expect(movement['createdAt'], timestamp);
    });
  });
}
