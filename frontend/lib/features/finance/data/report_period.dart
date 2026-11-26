import 'package:flutter/material.dart';

import 'finance_format.dart';

class ReportPeriod {
  const ReportPeriod._();

  static DateTime month(DateTime value) => DateTime(value.year, value.month, 1);

  static DateTime exclusiveEnd(DateTime value) =>
      DateTime(value.year, value.month + 1, 1);

  static DateTime endOfMonth(DateTime value) =>
      exclusiveEnd(value).subtract(const Duration(microseconds: 1));

  static DateTimeRange monthRange(DateTime value) =>
      DateTimeRange(start: month(value), end: endOfMonth(value));

  static DateTime previousMonth(DateTime value) =>
      DateTime(value.year, value.month - 1, 1);

  static DateTimeRange previousMonthRange(DateTime value) =>
      monthRange(previousMonth(value));

  static DateTimeRange? monthRangeOrNull(DateTime? value) =>
      value == null ? null : monthRange(value);

  static bool contains(DateTimeRange range, DateTime value) =>
      !value.isBefore(range.start) && !value.isAfter(range.end);

  static String label(DateTime value) =>
      '${FinanceFormat.monthLabel(value.month)} ${value.year}';
}
