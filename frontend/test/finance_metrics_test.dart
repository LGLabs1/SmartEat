import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/finance_export_service.dart';
import 'package:smarteat/features/finance/data/finance_format.dart';
import 'package:smarteat/features/finance/data/finance_metrics.dart';

Map<String, dynamic> _expense({
  required double amount,
  required DateTime date,
  String category = 'Ingredients',
  String source = 'manual',
}) {
  return {
    'amount': amount,
    'category': category,
    'source': source,
    'date': date.toIso8601String(),
  };
}

Map<String, dynamic> _payable({
  required double amount,
  DateTime? dueDate,
  String status = 'unpaid',
}) {
  return {
    'amount': amount,
    'status': status,
    'dueDate': dueDate?.toIso8601String(),
  };
}

void main() {
  group('FinanceMetrics source', () {
    test('blank source defaults to manual', () {
      expect(FinanceMetrics.source({}), FinanceMetrics.manualSource);
    });

    test('inventory source is detected and linked', () {
      final e = {'source': 'inventory_purchase'};
      expect(FinanceMetrics.source(e), FinanceMetrics.inventorySource);
      expect(FinanceMetrics.isLinkedPurchase(e), isTrue);
    });

    test('payable payment source is detected as a bill payment', () {
      final e = {'source': 'payable_payment', 'linkedPayableId': 'p1'};
      expect(FinanceMetrics.source(e), FinanceMetrics.payablePaymentSource);
      expect(FinanceMetrics.isPayablePayment(e), isTrue);
      expect(FinanceMetrics.isLinkedPurchase(e), isFalse);
    });

    test('manual expenses are neither linked nor bill payments', () {
      final e = {'source': 'manual'};
      expect(FinanceMetrics.isPayablePayment(e), isFalse);
      expect(FinanceMetrics.isLinkedPurchase(e), isFalse);
    });
  });

  group('FinanceMetrics sums', () {
    test('monthExpenses only counts matching month', () {
      final expenses = [
        _expense(amount: 100, date: DateTime(2025, 3, 5)),
        _expense(amount: 50, date: DateTime(2025, 3, 25)),
        _expense(amount: 999, date: DateTime(2025, 2, 28)),
      ];
      expect(FinanceMetrics.monthExpenses(expenses, DateTime(2025, 3, 1)),
          150);
    });

    test('monthOverMonth computes percentage change', () {
      final expenses = [
        _expense(amount: 200, date: DateTime(2025, 3, 5)),
        _expense(amount: 100, date: DateTime(2025, 2, 5)),
      ];
      expect(
        FinanceMetrics.monthOverMonth(expenses, DateTime(2025, 3, 1)),
        closeTo(100, 0.001),
      );
    });

    test('monthOverMonth is zero without a baseline', () {
      final expenses = [
        _expense(amount: 200, date: DateTime(2025, 3, 5)),
      ];
      expect(
        FinanceMetrics.monthOverMonth(expenses, DateTime(2025, 3, 1)),
        0,
      );
    });

    test('expensesByCategory groups and sorts descending', () {
      final expenses = [
        _expense(amount: 30, date: DateTime(2025, 3, 1), category: 'Rent'),
        _expense(amount: 10, date: DateTime(2025, 3, 1), category: 'Rent'),
        _expense(
            amount: 70, date: DateTime(2025, 3, 1), category: 'Utilities'),
      ];
      final grouped = FinanceMetrics.expensesByCategory(expenses);
      expect(grouped.first.key, 'Utilities');
      expect(grouped.first.value, 70);
      expect(grouped.last.value, 40);
    });
  });

  group('FinanceMetrics payables', () {
    final now = DateTime(2025, 3, 15);

    test('isPaid reflects status', () {
      expect(FinanceMetrics.isPaid({'status': 'Paid'}), isTrue);
      expect(FinanceMetrics.isPaid({'status': 'unpaid'}), isFalse);
    });

    test('overdueAmount counts only past-due unpaid', () {
      final payables = [
        _payable(amount: 100, dueDate: DateTime(2025, 3, 10)),
        _payable(amount: 50, dueDate: DateTime(2025, 3, 20)),
        _payable(amount: 999, dueDate: DateTime(2025, 3, 1), status: 'paid'),
      ];
      expect(FinanceMetrics.overdueAmount(payables, now: now), 100);
    });

    test('agingBuckets classify by days overdue', () {
      final payables = [
        _payable(amount: 10, dueDate: DateTime(2025, 3, 15)), // current
        _payable(amount: 20, dueDate: DateTime(2025, 3, 1)), // 14 days
        _payable(amount: 30, dueDate: DateTime(2025, 1, 31)), // 43 days
        _payable(amount: 40, dueDate: DateTime(2024, 12, 1)), // 60+
      ];
      final buckets = FinanceMetrics.agingBuckets(payables, now: now);
      expect(buckets['Current'], 10);
      expect(buckets['1-30 days'], 20);
      expect(buckets['31-60 days'], 30);
      expect(buckets['60+ days'], 40);
    });

    test('upcomingPayables excludes overdue and paid', () {
      final payables = [
        _payable(amount: 10, dueDate: DateTime(2025, 3, 18)),
        _payable(amount: 20, dueDate: DateTime(2025, 3, 10)),
        _payable(amount: 30, dueDate: DateTime(2025, 3, 20), status: 'paid'),
      ];
      final upcoming =
          FinanceMetrics.upcomingPayables(payables, days: 7, now: now);
      expect(upcoming.length, 1);
      expect(FinanceMetrics.amountOf(upcoming.first), 10);
    });
  });

  group('FinanceMetrics variable payables', () {
    final now = DateTime(2025, 3, 15);

    test('flags variable by explicit flag or zero amount', () {
      expect(
        FinanceMetrics.isVariablePayable({'isVariable': true, 'amount': 100}),
        isTrue,
      );
      expect(
        FinanceMetrics.isVariablePayable({'amount': 0}),
        isTrue,
      );
      expect(
        FinanceMetrics.isVariablePayable({'isVariable': false, 'amount': 500}),
        isFalse,
      );
    });

    test('estimatedAmountOf prefers last, then estimate, then average', () {
      expect(
        FinanceMetrics.estimatedAmountOf({
          'isVariable': true,
          'lastAmount': 120,
          'estimateAmount': 100,
          'averageAmount': 90,
        }),
        120,
      );
      expect(
        FinanceMetrics.estimatedAmountOf({
          'isVariable': true,
          'estimateAmount': 100,
          'averageAmount': 90,
        }),
        100,
      );
      expect(
        FinanceMetrics.estimatedAmountOf({'isVariable': true, 'averageAmount': 90}),
        90,
      );
      expect(FinanceMetrics.estimatedAmountOf({'amount': 0}), 0);
    });

    test('variable bills excluded from hard totals but counted separately', () {
      final payables = [
        _payable(amount: 200, dueDate: DateTime(2025, 3, 20)),
        {
          'amount': 0,
          'isVariable': true,
          'estimateAmount': 150,
          'dueDate': DateTime(2025, 3, 20).toIso8601String(),
        },
      ];
      final end = DateTime(2025, 3, 31);
      expect(FinanceMetrics.outstandingPayables(payables, end: end), 200);
      expect(FinanceMetrics.estimatedOutstanding(payables, end: end), 150);
    });

    test('overdue and aging exclude variable bills', () {
      final payables = [
        _payable(amount: 100, dueDate: DateTime(2025, 3, 10)),
        {
          'amount': 0,
          'isVariable': true,
          'estimateAmount': 75,
          'dueDate': DateTime(2025, 3, 1).toIso8601String(),
        },
      ];
      expect(FinanceMetrics.overdueAmount(payables, now: now), 100);
      final buckets = FinanceMetrics.agingBuckets(payables, now: now);
      expect(buckets['1-30 days'], 100);
      expect(buckets['60+ days'], 0);
    });

    test('payableHistory parses and sorts newest-first', () {
      final history = FinanceMetrics.payableHistory({
        'amountHistory': [
          {'amount': 50, 'date': DateTime(2025, 1, 1).toIso8601String()},
          {'amount': 80, 'date': DateTime(2025, 3, 1).toIso8601String()},
          {'amount': 0, 'date': DateTime(2025, 2, 1).toIso8601String()},
          'garbage',
        ],
      });
      expect(history.length, 2);
      expect(history.first.key, 80);
      expect(history.last.key, 50);
    });
  });

  group('FinanceMetrics dailyTrend', () {
    test('produces a continuous window with zeros for empty days', () {
      final now = DateTime(2025, 3, 15);
      final expenses = [
        _expense(amount: 25, date: DateTime(2025, 3, 15)),
        _expense(amount: 10, date: DateTime(2025, 3, 13)),
      ];
      final trend =
          FinanceMetrics.dailyTrend(expenses, days: 3, now: now);
      expect(trend.length, 3);
      expect(trend.first.key, DateTime(2025, 3, 13));
      expect(trend.first.value, 10);
      expect(trend[1].value, 0);
      expect(trend.last.value, 25);
    });
  });

  group('FinanceExportService', () {
    test('expenses CSV has header and rows', () {
      final fmt = FinanceFormat('₱');
      final csv = FinanceExportService.buildExpensesCsv([
        {
          'name': 'Electricity, March',
          'category': 'Utilities',
          'amount': 123.5,
          'date': DateTime(2025, 3, 5).toIso8601String(),
          'supplierName': 'Meralco',
          'paymentMethod': 'Cash',
        },
      ], fmt);
      final lines = csv.trim().split('\n');
      expect(lines.first, contains('Date,Name,Category'));
      expect(lines[1], contains('"Electricity, March"'));
      expect(lines[1], contains('123.50'));
    });

    test('payables CSV reflects paid status', () {
      final fmt = FinanceFormat('₱');
      final csv = FinanceExportService.buildPayablesCsv([
        {
          'name': 'Rent',
          'amount': 5000,
          'status': 'paid',
          'dueDate': DateTime(2025, 3, 1).toIso8601String(),
        },
      ], fmt);
      expect(csv, contains('paid'));
      expect(csv, contains('5000.00'));
    });
  });
}
