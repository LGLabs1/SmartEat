import 'package:flutter/material.dart';

import 'finance_format.dart';

class ReportPeriod {
  const ReportPeriod._();

  static const String yearToDateLabel = 'All months this year';
  static const String compactYearToDateLabel = 'YTD';

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

  static DateTimeRange yearToDateRange(DateTime anchor, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final end = DateTime(
      today.year,
      today.month,
      today.day + 1,
    ).subtract(const Duration(microseconds: 1));
    return DateTimeRange(start: DateTime(anchor.year, 1, 1), end: end);
  }

  static DateTime yearToDateExclusiveEnd(DateTime anchor, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return DateTime(today.year, today.month, today.day + 1);
  }

  static String selectionLabel(ReportPeriodSelection selection) =>
      selection.yearToDate ? yearToDateLabel : label(selection.month);

  static String compactSelectionLabel(ReportPeriodSelection selection) =>
      selection.yearToDate ? compactYearToDateLabel : label(selection.month);
}

class ReportPeriodSelection {
  const ReportPeriodSelection({
    required this.month,
    this.yearToDate = false,
  });

  final DateTime month;
  final bool yearToDate;

  DateTime get anchorMonth => ReportPeriod.month(month);

  DateTimeRange range({DateTime? now}) => yearToDate
      ? ReportPeriod.yearToDateRange(anchorMonth, now: now)
      : ReportPeriod.monthRange(anchorMonth);

  DateTime exclusiveEnd({DateTime? now}) => yearToDate
      ? ReportPeriod.yearToDateExclusiveEnd(anchorMonth, now: now)
      : ReportPeriod.exclusiveEnd(anchorMonth);

  String label() => ReportPeriod.selectionLabel(this);

  String compactLabel() => ReportPeriod.compactSelectionLabel(this);

  ReportPeriodSelection? next({DateTime? now}) {
    if (yearToDate) return null;
    final today = now ?? DateTime.now();
    final current = ReportPeriod.month(today);
    final anchor = anchorMonth;
    if (anchor == current) {
      return ReportPeriodSelection(month: anchor, yearToDate: true);
    }
    if (anchor.isBefore(current)) {
      return ReportPeriodSelection(month: ReportPeriod.exclusiveEnd(anchor));
    }
    return null;
  }

  ReportPeriodSelection? previous({DateTime? now}) {
    if (yearToDate) {
      final today = now ?? DateTime.now();
      return ReportPeriodSelection(
          month: ReportPeriod.month(today), yearToDate: false);
    }
    return ReportPeriodSelection(
        month: ReportPeriod.previousMonth(anchorMonth), yearToDate: false);
  }

  bool canGoNext({DateTime? now}) => next(now: now) != null;

  @override
  bool operator ==(Object other) =>
      other is ReportPeriodSelection &&
      other.anchorMonth == anchorMonth &&
      other.yearToDate == yearToDate;

  @override
  int get hashCode => Object.hash(anchorMonth, yearToDate);

  @override
  String toString() =>
      'ReportPeriodSelection(month: $anchorMonth, yearToDate: $yearToDate)';
}
