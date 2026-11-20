import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/order_history_dates.dart';

void main() {
  group('OrderHistoryDates.key', () {
    test('formats a date key with padded month and day', () {
      expect(
        OrderHistoryDates.key(DateTime(2026, 3, 7, 14, 30)),
        '2026-03-07',
      );
    });

    test('uses an unknown key for missing dates', () {
      expect(OrderHistoryDates.key(null), OrderHistoryDates.unknownKey);
    });
  });

  group('OrderHistoryDates.availableKeys', () {
    test('sorts dates newest first and unknown dates last', () {
      final keys = OrderHistoryDates.availableKeys([
        DateTime(2026, 11, 17),
        null,
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 19, 8),
        DateTime(2026, 11, 18),
      ]);

      expect(keys, [
        '2026-11-19',
        '2026-11-18',
        '2026-11-17',
        OrderHistoryDates.unknownKey,
      ]);
    });
  });

  group('OrderHistoryDates.label', () {
    test('labels today and yesterday relative to now', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      expect(
        OrderHistoryDates.label(OrderHistoryDates.key(today)),
        startsWith('Today • '),
      );
      expect(
        OrderHistoryDates.label(OrderHistoryDates.key(yesterday)),
        startsWith('Yesterday • '),
      );
    });

    test('labels other dates with month, day, and year', () {
      expect(
        OrderHistoryDates.label('2026-03-07'),
        'Mar 7, 2026',
      );
    });

    test('handles unknown and malformed keys', () {
      expect(
        OrderHistoryDates.label(OrderHistoryDates.unknownKey),
        'Unknown date',
      );
      expect(OrderHistoryDates.label('not-a-date'), 'not-a-date');
    });
  });

  group('OrderHistoryDates.filterLabel', () {
    test('uses All dates for null or the all key', () {
      expect(OrderHistoryDates.filterLabel(null), 'All dates');
      expect(
        OrderHistoryDates.filterLabel(OrderHistoryDates.allKey),
        'All dates',
      );
    });

    test('uses the date label for a specific date', () {
      expect(
        OrderHistoryDates.filterLabel('2026-03-07'),
        'Mar 7, 2026',
      );
    });
  });

  group('OrderHistoryDates.groupByDate', () {
    test('groups items by date in newest-first order', () {
      final items = [
        {'id': 'a', 'date': DateTime(2026, 11, 18)},
        {'id': 'b', 'date': DateTime(2026, 11, 19)},
        {'id': 'c', 'date': DateTime(2026, 11, 18, 9)},
      ];

      final grouped = OrderHistoryDates.groupByDate<Map<String, dynamic>>(
        items,
        (item) => item['date'] as DateTime?,
      );

      expect(grouped.keys.toList(), ['2026-11-19', '2026-11-18']);
      expect(grouped['2026-11-19']!.map((e) => e['id']), ['b']);
      expect(grouped['2026-11-18']!.map((e) => e['id']), ['a', 'c']);
    });
  });
}
