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
}
