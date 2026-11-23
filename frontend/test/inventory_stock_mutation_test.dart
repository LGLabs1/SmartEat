import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/data/models/stock_movement.dart';
import 'package:smarteat/features/inventory/data/repositories/inventory_remote_repository.dart';
import 'package:smarteat/services/firebase_service.dart';

void main() {
  group('signed adjustment delta payload', () {
    test('maps a positive delta to add with a positive quantity', () {
      final payload = buildDeltaStockMutation(4.5);

      expect(payload['operation'], 'add');
      expect(payload['quantity'], 4.5);
      expect(payload, isNot(contains('reasonCode')));
    });

    test('maps a negative delta to subtract with a positive quantity', () {
      final payload = buildDeltaStockMutation(-2.25);

      expect(payload['operation'], 'subtract');
      expect(payload['quantity'], 2.25);
      expect(payload, isNot(contains('reasonCode')));
    });

    test('derives before/after stock from the signed delta', () {
      const observedAfter = 17.5;

      expect(stockAfterDelta(observedAfter, -2.5), closeTo(15, 0.000001));
      expect(stockAfterDelta(observedAfter, 2.5), closeTo(20, 0.000001));
    });
  });

  group('direct sale consumption', () {
    test('uses a positive subtract quantity and lowers stock', () {
      const sold = 3.0;
      final payload = buildDeltaStockMutation(-sold);

      expect(payload['operation'], 'subtract');
      expect(payload['quantity'], sold);
      expect(stockAfterDelta(10, -sold), closeTo(7, 0.000001));
    });

    test('movement id is deterministic when a reference id is available', () {
      expect(
        directSaleMovementId('rice', 'order-42'),
        directSaleMovementId('rice', ' order-42 '),
      );
      expect(directSaleMovementId('rice', 'order-42'), 'sale_order-42_rice');
    });
  });

  group('inventory cache normalization', () {
    test('encodes Firestore Timestamps before cache serialization', () {
      final when = DateTime(2026, 11, 22, 10, 30);
      final rows = <Map<String, dynamic>>[
        {
          'id': 'movement-1',
          'timestamp': Timestamp.fromDate(when),
          'createdAt': Timestamp.fromDate(when),
          'meta': <String, dynamic>{
            'syncedAt': Timestamp.fromDate(when),
            'labels': <dynamic>[Timestamp.fromDate(when)],
          },
        },
      ];

      final normalized = normalizeInventoryCacheRows(rows);
      final encoded = jsonEncode(normalized);

      expect(encoded, contains(when.toIso8601String()));
      expect(jsonDecode(encoded).first['meta']['syncedAt'],
          when.toIso8601String());
      expect(StockMovement.fromJson(normalized.first).timestamp, when);
    });
  });

  group('stock operation guard', () {
    test('accepts only add, subtract and set', () {
      expect(
        computeStockAfterOperation(
          currentStock: 10,
          quantity: 2,
          operation: 'add',
        ),
        12,
      );
      expect(
        computeStockAfterOperation(
          currentStock: 10,
          quantity: 2,
          operation: 'subtract',
        ),
        8,
      );
      expect(
        computeStockAfterOperation(
          currentStock: 10,
          quantity: 2,
          operation: 'set',
        ),
        2,
      );
      expect(
        () => computeStockAfterOperation(
          currentStock: 10,
          quantity: 2,
          operation: 'Sale consumption',
        ),
        throwsArgumentError,
      );
    });

    test('rejects updates that would leave negative stock', () {
      expect(
        () => computeStockAfterOperation(
          currentStock: 1,
          quantity: 2,
          operation: 'subtract',
        ),
        throwsArgumentError,
      );
      expect(
        () => computeStockAfterOperation(
          currentStock: 1,
          quantity: -2,
          operation: 'set',
        ),
        throwsArgumentError,
      );
    });
  });
}
