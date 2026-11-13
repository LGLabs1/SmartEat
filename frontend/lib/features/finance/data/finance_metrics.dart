import 'finance_format.dart';

/// Pure computation helpers for finance dashboards and reports.
///
/// These operate on the raw maps returned by [ApiService] so they can be
/// unit tested without a widget or Firebase binding.
class FinanceMetrics {
  FinanceMetrics._();

  static const String manualSource = 'manual';
  static const String inventorySource = 'inventory_purchase';

  static String source(Map<String, dynamic> expense) {
    final src =
        (expense['source'] ?? '').toString().trim().toLowerCase();
    if (src.isEmpty || src == manualSource) return manualSource;
    return src;
  }

  static bool isLinkedPurchase(Map<String, dynamic> expense) =>
      source(expense) == inventorySource;

  static double amountOf(Map<String, dynamic> m) =>
      (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0;

  static const String payablePaymentSource = 'payable_payment';

  static bool isPayablePayment(Map<String, dynamic> expense) =>
      source(expense) == payablePaymentSource;

  /// Whether a payable has no fixed amount (e.g. utilities billed by usage).
  ///
  /// Prefers the explicit `isVariable` flag but also treats a missing or
  /// non-positive `amount` as variable so legacy rows keep working.
  static bool isVariablePayable(Map<String, dynamic> payable) {
    if (payable['isVariable'] == true) return true;
    if (payable['isVariable'] == false) return amountOf(payable) <= 0;
    return amountOf(payable) <= 0;
  }

  /// Best-available expected amount for a variable bill, used only for
  /// projections/labels. Prefers the latest actual, then a manual estimate,
  /// then a stored rolling average.
  static double estimatedAmountOf(Map<String, dynamic> payable) {
    if (!isVariablePayable(payable)) return amountOf(payable);
    for (final key in ['lastAmount', 'estimateAmount', 'averageAmount']) {
      final v = payable[key];
      if (v is num && v > 0) return v.toDouble();
    }
    return 0.0;
  }

  static bool isPaid(Map<String, dynamic> payable) =>
      (payable['status'] ?? 'unpaid').toString().toLowerCase().trim() == 'paid';

  static DateTime? expenseDate(Map<String, dynamic> e) =>
      FinanceFormat.asDate(e['date']) ?? FinanceFormat.asDate(e['createdAt']);

  /// Sum of expenses whose date falls within [start]..[end] inclusive.
  static double sumExpenses(
    List<Map<String, dynamic>> expenses, {
    DateTime? start,
    DateTime? end,
  }) {
    return expenses.where((e) {
      final d = expenseDate(e);
      if (d == null) return false;
      if (start != null && d.isBefore(start)) return false;
      if (end != null && d.isAfter(end)) return false;
      return true;
    }).fold<double>(0, (sum, e) => sum + amountOf(e));
  }

  static double monthExpenses(
    List<Map<String, dynamic>> expenses,
    DateTime month,
  ) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return sumExpenses(expenses, start: start, end: end);
  }

  /// Percentage change versus the previous month. Returns 0 when there is no
  /// comparable baseline, and clamps to +/-999 to keep badges sane.
  static double monthOverMonth(
    List<Map<String, dynamic>> expenses,
    DateTime month,
  ) {
    final current = monthExpenses(expenses, month);
    final prev = monthExpenses(
      expenses,
      DateTime(month.year, month.month - 1, 1),
    );
    if (prev == 0) return 0;
    final change = ((current - prev) / prev) * 100;
    return change.clamp(-999, 999);
  }

  /// Expense totals grouped by category, sorted descending.
  static List<MapEntry<String, double>> expensesByCategory(
    List<Map<String, dynamic>> expenses,
  ) {
    final map = <String, double>{};
    for (final e in expenses) {
      final category = (e['category'] ?? 'Other').toString().trim();
      final key = category.isEmpty ? 'Other' : category;
      map[key] = (map[key] ?? 0) + amountOf(e);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Unpaid payables due on or before [end] (or with no due date).
  ///
  /// Variable-amount bills are excluded because their cost is unknown until
  /// the bill is actually paid; see [estimatedOutstanding] for a projection.
  static double outstandingPayables(
    List<Map<String, dynamic>> payables, {
    DateTime? end,
  }) {
    return payables.where((p) {
      if (isPaid(p)) return false;
      if (isVariablePayable(p)) return false;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) return true;
      if (end != null && due.isAfter(end)) return false;
      return true;
    }).fold<double>(0, (sum, p) => sum + amountOf(p));
  }

  /// Projected cost of unpaid variable bills that are due within the same
  /// window as [outstandingPayables], using their estimate/last actual. Kept
  /// separate so it never inflates hard AP totals.
  static double estimatedOutstanding(
    List<Map<String, dynamic>> payables, {
    DateTime? end,
  }) {
    return payables.where((p) {
      if (isPaid(p)) return false;
      if (!isVariablePayable(p)) return false;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) return true;
      if (end != null && due.isAfter(end)) return false;
      return true;
    }).fold<double>(0, (sum, p) => sum + estimatedAmountOf(p));
  }

  /// Total amount of unpaid payables that are past their due date.
  ///
  /// Excludes variable bills (unknown actual cost) like [outstandingPayables].
  static double overdueAmount(
    List<Map<String, dynamic>> payables, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    return payables.where((p) {
      if (isPaid(p)) return false;
      if (isVariablePayable(p)) return false;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) return false;
      return due.isBefore(cutoff);
    }).fold<double>(0, (sum, p) => sum + amountOf(p));
  }

  /// Count of unpaid payables due within [days] and not yet overdue.
  static int upcomingCount(
    List<Map<String, dynamic>> payables, {
    int days = 7,
    DateTime? now,
  }) {
    return upcomingPayables(payables, days: days, now: now).length;
  }

  static List<Map<String, dynamic>> upcomingPayables(
    List<Map<String, dynamic>> payables, {
    int days = 7,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    final limit = cutoff.add(Duration(days: days));
    return payables.where((p) {
      if (isPaid(p)) return false;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) return false;
      final d = DateTime(due.year, due.month, due.day);
      return !d.isBefore(cutoff) && !d.isAfter(limit);
    }).toList();
  }

  /// AP aging buckets keyed by label. Buckets are exclusive of paid payables.
  static Map<String, double> agingBuckets(
    List<Map<String, dynamic>> payables, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    final buckets = <String, double>{
      'Current': 0,
      '1-30 days': 0,
      '31-60 days': 0,
      '60+ days': 0,
    };
    for (final p in payables) {
      if (isPaid(p)) continue;
      if (isVariablePayable(p)) continue;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) {
        buckets['Current'] = buckets['Current']! + amountOf(p);
        continue;
      }
      final d = DateTime(due.year, due.month, due.day);
      if (!d.isBefore(cutoff)) {
        buckets['Current'] = buckets['Current']! + amountOf(p);
        continue;
      }
      final overdueDays = cutoff.difference(d).inDays;
      if (overdueDays <= 30) {
        buckets['1-30 days'] = buckets['1-30 days']! + amountOf(p);
      } else if (overdueDays <= 60) {
        buckets['31-60 days'] = buckets['31-60 days']! + amountOf(p);
      } else {
        buckets['60+ days'] = buckets['60+ days']! + amountOf(p);
      }
    }
    return buckets;
  }

  /// Daily expense totals across a trailing window ending today.
  static List<MapEntry<DateTime, double>> dailyTrend(
    List<Map<String, dynamic>> expenses, {
    int days = 14,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(Duration(days: days - 1));
    final totals = <DateTime, double>{};
    for (var i = 0; i < days; i++) {
      totals[start.add(Duration(days: i))] = 0;
    }
    for (final e in expenses) {
      final d = expenseDate(e);
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      totals[day] = (totals[day] ?? 0) + amountOf(e);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  static Duration? daysUntilDue(
    Map<String, dynamic> payable, {
    DateTime? now,
  }) {
    final due = FinanceFormat.asDate(payable['dueDate']);
    if (due == null) return null;
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);
    final d = DateTime(due.year, due.month, due.day);
    return d.difference(cutoff);
  }

  /// Parsed, most-recent-first list of recorded actual payments for a variable
  /// bill. Entries are `{amount, date}` maps; malformed rows are skipped.
  static List<MapEntry<double, DateTime?>> payableHistory(
    Map<String, dynamic> payable,
  ) {
    final raw = payable['amountHistory'];
    if (raw is! List) return const [];
    final entries = <MapEntry<double, DateTime?>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final amount = item['amount'];
      if (amount is! num || amount <= 0) continue;
      entries.add(
        MapEntry(amount.toDouble(), FinanceFormat.asDate(item['date'])),
      );
    }
    // Newest first when dates are present; undated entries stay at the end.
    entries.sort((a, b) {
      final ad = a.value;
      final bd = b.value;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return entries;
  }
}
