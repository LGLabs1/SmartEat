import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared formatting helpers for the finance feature.
///
/// Kept free of Flutter widget imports so it can be reused from dialogs,
/// tabs and the export service without pulling in UI concerns.
class FinanceFormat {
  FinanceFormat(this.currencySymbol);

  final String currencySymbol;

  String money(num? v, {bool showDashForZero = false}) {
    if (v == null || v == 0) {
      if (showDashForZero) return '${currencySymbol}-.--';
      return '${currencySymbol}0.00';
    }
    return '$currencySymbol${v.toStringAsFixed(2)}';
  }

  /// Compact display for chart labels / tight rows (e.g. ₱1.2k).
  String moneyCompact(num? v) {
    if (v == null || v == 0) return '${currencySymbol}0';
    final abs = v.abs();
    if (abs >= 1000000) {
      return '$currencySymbol${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      return '$currencySymbol${(v / 1000).toStringAsFixed(1)}k';
    }
    return '$currencySymbol${v.toStringAsFixed(0)}';
  }

  static DateTime? asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static String date(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String daySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  static const List<String> monthsLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String monthLabel(int month) =>
      monthsLong[(month - 1).clamp(0, 11)];
}
