import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/report_period.dart';

void main() {
  group('ReportPeriod', () {
    test('normalizes a month to day one', () {
      expect(ReportPeriod.month(DateTime(2026, 11, 26, 17, 42)),
          DateTime(2026, 11, 1));
    });

    test('builds an exclusive end at the next month boundary', () {
      expect(ReportPeriod.exclusiveEnd(DateTime(2026, 12, 9)),
          DateTime(2027, 1, 1));
    });

    test('builds an inclusive end one microsecond before next month', () {
      expect(ReportPeriod.endOfMonth(DateTime(2026, 2, 9)),
          DateTime(2026, 2, 28, 23, 59, 59, 999, 999));
    });

    test('previousMonth crosses the year boundary', () {
      expect(ReportPeriod.previousMonth(DateTime(2026, 1, 15)),
          DateTime(2025, 12, 1));
    });

    test('contains treats month end as inclusive', () {
      final range = ReportPeriod.monthRange(DateTime(2026, 10, 15));
      expect(ReportPeriod.contains(range, DateTime(2026, 10, 1)), isTrue);
      expect(
          ReportPeriod.contains(range, DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(ReportPeriod.contains(range, DateTime(2026, 11, 1)), isFalse);
    });

    test('label uses the full month and year', () {
      expect(ReportPeriod.label(DateTime(2026, 11, 26)), 'November 2026');
    });
  });

  group('ReportPeriodSelection', () {
    final now = DateTime(2026, 11, 26, 15, 30);

    test('month selection uses the month range and label', () {
      final selection = ReportPeriodSelection(month: DateTime(2026, 10, 15));

      expect(selection.range(), ReportPeriod.monthRange(DateTime(2026, 10, 1)));
      expect(selection.exclusiveEnd(), DateTime(2026, 11, 1));
      expect(selection.label(), 'October 2026');
      expect(selection.compactLabel(), 'October 2026');
    });

    test('year-to-date range starts on January 1 and ends today', () {
      final selection = ReportPeriodSelection(
        month: DateTime(2026, 8, 1),
        yearToDate: true,
      );

      final range = selection.range(now: now);
      expect(range.start, DateTime(2026, 1, 1));
      expect(range.end, DateTime(2026, 11, 26, 23, 59, 59, 999, 999));
      expect(selection.exclusiveEnd(now: now), DateTime(2026, 11, 27));
      expect(selection.label(), 'All months this year');
      expect(selection.compactLabel(), 'YTD');
    });

    test('navigation follows the current month and year-to-date rules', () {
      final current = ReportPeriodSelection(month: DateTime(2026, 11, 1));
      final ytd = current.next(now: now);
      expect(ytd, isNotNull);
      expect(ytd!.yearToDate, isTrue);
      expect(ytd.next(now: now), isNull);
      expect(ytd.previous(now: now), current);

      final past = ReportPeriodSelection(month: DateTime(2026, 9, 1));
      expect(past.next(now: now),
          ReportPeriodSelection(month: DateTime(2026, 10, 1)));
      expect(past.previous(now: now),
          ReportPeriodSelection(month: DateTime(2026, 8, 1)));
    });
  });
}
