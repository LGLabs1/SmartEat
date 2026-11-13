/// Shared, side-effect-free helpers for staff management screens.
///
/// These are kept free of Flutter/Firebase imports so they can be unit tested
/// without a widget or Firestore environment.
library;

/// Whether a user document represents an admin.
///
/// Accepts both the modern `isAdmin` flag and the legacy `role == 'admin'`.
bool isAdminUser(Map<String, dynamic> data) {
  final role = (data['role'] ?? '').toString().trim().toLowerCase();
  final dynamic raw = data['isAdmin'];
  final bool flag = raw == true ||
      raw == 1 ||
      (raw is String && raw.trim().toLowerCase() == 'true');
  return flag || role == 'admin';
}

/// Whether a user document is approved.
///
/// Missing values are treated as approved so accounts created before the
/// approval flow existed keep working.
bool isApprovedUser(Map<String, dynamic> data) {
  final dynamic raw = data['approved'];
  if (raw == null) return true;
  if (raw is bool) return raw;
  if (raw is String) return raw.trim().toLowerCase() == 'true';
  if (raw is num) return raw != 0;
  return true;
}

/// A staff member (non-admin) who still needs an admin to approve them.
bool isPendingStaff(Map<String, dynamic> data) =>
    !isAdminUser(data) && !isApprovedUser(data);

/// Display name with sensible fallbacks: full name → email → uid.
String staffDisplayName(Map<String, dynamic> data, String uid) {
  final firstName = (data['firstName'] ?? '').toString().trim();
  final lastName = (data['lastName'] ?? '').toString().trim();
  final name = '$firstName $lastName'.trim();
  if (name.isNotEmpty) return name;
  final email = (data['email'] ?? '').toString().trim();
  if (email.isNotEmpty) return email;
  return uid;
}

/// Phone number with the legacy `phoneNumber` fallback.
String staffPhone(Map<String, dynamic> data) {
  final phone = (data['phone'] ?? '').toString().trim();
  if (phone.isNotEmpty) return phone;
  return (data['phoneNumber'] ?? '').toString().trim();
}

/// The half-day rate to use for pay, falling back to half the daily rate when
/// no explicit half-day rate has been configured.
double effectiveHalfDayRate({
  required double dailyRate,
  required double halfDayRate,
}) {
  if (halfDayRate > 0) return halfDayRate;
  if (dailyRate > 0) return dailyRate / 2;
  return 0;
}

/// Gross pay for a week: full days at the daily rate plus half days at the
/// effective half-day rate.
double computeGrossPay({
  required double dailyRate,
  required double halfDayRate,
  required int fullDays,
  required int halfDays,
}) {
  final half = effectiveHalfDayRate(
    dailyRate: dailyRate,
    halfDayRate: halfDayRate,
  );
  return (dailyRate * fullDays) + (half * halfDays);
}

/// Net pay never goes negative; advances beyond gross are clamped to zero.
double computeNetPay({required double gross, required double advances}) {
  final net = gross - advances;
  return net < 0 ? 0 : net;
}

DateTime staffDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `yyyy-MM-dd` key used by attendance and payroll documents.
String staffFormatYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Only days strictly before today should be auto-marked absent.
bool shouldAutoMarkAbsent({
  required DateTime day,
  required DateTime today,
}) {
  return staffDateOnly(day).isBefore(staffDateOnly(today));
}

/// Directory filter applied to the staff list.
enum StaffDirectoryFilter { all, active, pending, inactive }

/// Which directory bucket a user belongs to.
StaffDirectoryFilter staffFilterFor({
  required Map<String, dynamic> data,
  required String profileStatus,
}) {
  if (isPendingStaff(data)) return StaffDirectoryFilter.pending;
  final status = profileStatus.trim().toLowerCase();
  if (status == 'inactive' || status == 'removed' || status == 'disabled') {
    return StaffDirectoryFilter.inactive;
  }
  return StaffDirectoryFilter.active;
}

bool staffMatchesFilter({
  required Map<String, dynamic> data,
  required String profileStatus,
  required StaffDirectoryFilter filter,
}) {
  if (filter == StaffDirectoryFilter.all) return true;
  return staffFilterFor(data: data, profileStatus: profileStatus) == filter;
}

/// Case-insensitive search across name, email, phone, uid, and position.
bool staffMatchesQuery({
  required Map<String, dynamic> data,
  required String uid,
  required String query,
  String position = '',
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = [
    uid,
    staffDisplayName(data, uid),
    (data['email'] ?? '').toString(),
    staffPhone(data),
    position,
  ].join(' ').toLowerCase();
  return haystack.contains(q);
}

/// Up to two uppercase initials for an avatar. Falls back to `?`.
String staffInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  final first = parts.first.substring(0, 1);
  final last = parts.last.substring(0, 1);
  return '$first$last'.toUpperCase();
}

/// Totals from a staff member's payout history.
///
/// Payouts without a `type` are treated as weekly payouts for backwards
/// compatibility with records created before the field existed.
({double paid, double advances, int count}) staffPayoutSummary(
  Iterable<Map<String, dynamic>> payouts,
) {
  var paid = 0.0;
  var advances = 0.0;
  var count = 0;
  for (final payout in payouts) {
    final raw = payout['amount'];
    final amount = raw is num ? raw.toDouble() : 0.0;
    final type = (payout['type'] ?? 'weekly').toString().trim().toLowerCase();
    if (type == 'advance') {
      advances += amount;
    } else {
      paid += amount;
    }
    count++;
  }
  return (paid: paid, advances: advances, count: count);
}

/// Total value of a staff meal order from its `items` list.
///
/// Each item is expected to carry numeric `price` and `quantity` fields.
double staffMealOrderTotal(Map<String, dynamic> order) {
  final items = order['items'];
  if (items is! List) return 0;
  var total = 0.0;
  for (final item in items) {
    if (item is! Map) continue;
    final price = item['price'];
    final quantity = item['quantity'];
    final unit = price is num ? price.toDouble() : 0.0;
    final count = quantity is num ? quantity.toDouble() : 0.0;
    total += unit * count;
  }
  return total;
}

/// Compact one-line description of a meal order's items.
String staffMealItemsLabel(
  Map<String, dynamic> order, {
  int maxItems = 3,
}) {
  final items = order['items'];
  if (items is! List || items.isEmpty) return 'No items';
  final parts = <String>[];
  for (final item in items) {
    if (item is! Map) continue;
    final name = (item['name'] ?? 'Item').toString().trim();
    final quantity = item['quantity'];
    final count = quantity is num ? quantity.toInt() : 1;
    parts.add(count > 1 ? '${count}× $name' : name);
  }
  if (parts.isEmpty) return 'No items';
  if (parts.length <= maxItems) return parts.join(', ');
  final remaining = parts.length - maxItems;
  return '${parts.take(maxItems).join(', ')} +$remaining more';
}

/// Counts and value for a staff member's meal order history.
///
/// `total` sums only completed orders so it reflects meals actually fulfilled.
({int pending, int completed, double total}) staffMealOrderSummary(
  Iterable<Map<String, dynamic>> orders,
) {
  var pending = 0;
  var completed = 0;
  var total = 0.0;
  for (final order in orders) {
    final status =
        (order['status'] ?? 'pending').toString().trim().toLowerCase();
    if (status == 'pending') {
      pending++;
    } else if (status == 'completed') {
      completed++;
      total += staffMealOrderTotal(order);
    }
  }
  return (pending: pending, completed: completed, total: total);
}

/// Whether an admin meal-order row matches the status filter and search query.
///
/// `statusFilter` accepts `all` (or empty) plus `pending`/`completed`/
/// `cancelled`. The query searches staff name/id, notes, and item names.
bool staffMealMatchesFilter({
  required Map<String, dynamic> order,
  required String statusFilter,
  required String query,
}) {
  final status = (order['status'] ?? 'pending').toString().trim().toLowerCase();
  final filter = statusFilter.trim().toLowerCase();
  if (filter.isNotEmpty && filter != 'all' && status != filter) return false;

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  final haystack = <String>[
    (order['staffName'] ?? '').toString(),
    (order['staffId'] ?? '').toString(),
    (order['notes'] ?? '').toString(),
  ];
  final items = order['items'];
  if (items is List) {
    for (final item in items) {
      if (item is Map) {
        haystack.add((item['name'] ?? '').toString());
      }
    }
  }
  return haystack.join(' ').toLowerCase().contains(q);
}
