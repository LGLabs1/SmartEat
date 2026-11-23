import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/api_service.dart';
import 'package:smarteat/services/firebase_service.dart';

void main() {
  group('createOrder idempotency', () {
    test('duplicate document returns the existing order without deducting', () {
      final decision = planCreateOrderIdempotency(
        documentExists: true,
        documentId: 'order-7',
        existingData: const {
          'status': 'pending',
          'inventoryDeducted': false,
        },
        requestedCompleted: true,
        inventoryDeducted: false,
        hasDeductionSnapshot: false,
      );

      expect(decision.isDuplicate, isTrue);
      expect(decision.deductStock, isFalse);
      expect(decision.existingOrder?['id'], 'order-7');
      expect(decision.existingOrder?['status'], 'pending');
    });

    test('a new completed order deducts stock once', () {
      final decision = planCreateOrderIdempotency(
        documentExists: false,
        documentId: 'order-8',
        requestedCompleted: true,
        inventoryDeducted: false,
        hasDeductionSnapshot: false,
      );

      expect(decision.isDuplicate, isFalse);
      expect(decision.existingOrder, isNull);
      expect(decision.deductStock, isTrue);
    });

    test('a new pending order never deducts stock', () {
      final decision = planCreateOrderIdempotency(
        documentExists: false,
        documentId: 'order-9',
        requestedCompleted: false,
        inventoryDeducted: false,
        hasDeductionSnapshot: false,
      );

      expect(decision.deductStock, isFalse);
    });

    test('a prior deduction snapshot guards against deducting again', () {
      final decision = planCreateOrderIdempotency(
        documentExists: false,
        documentId: 'order-10',
        requestedCompleted: true,
        inventoryDeducted: false,
        hasDeductionSnapshot: true,
      );

      expect(decision.deductStock, isFalse);
    });
  });

  group('addRequestId idempotency', () {
    test('resolveAddRequestId preserves a caller supplied id', () {
      expect(resolveAddRequestId(' req-1 '), 'req-1');
    });

    test('resolveAddRequestId generates a reusable non-empty id', () {
      final generated = resolveAddRequestId(null);

      expect(generated, isNotEmpty);
      expect(resolveAddRequestId(generated), generated);
    });

    test('duplicate request ids short-circuit without changing the log', () {
      final recorded =
          appendAddRequestId(recordedAddRequestIds(const ['req-1']), 'req-1');

      expect(recorded, ['req-1']);
      expect(isDuplicateAddRequest(recorded, 'req-1'), isTrue);
      expect(isDuplicateAddRequest(recorded, 'req-2'), isFalse);
      expect(appendAddRequestId(recorded, 'req-2'), ['req-1', 'req-2']);
    });

    test('recorded request ids stay bounded', () {
      var ids = const <String>[];
      for (var i = 0; i < 25; i++) {
        ids = appendAddRequestId(ids, 'req-$i');
      }

      expect(ids, hasLength(20));
      expect(ids.last, 'req-24');
    });
  });
}
