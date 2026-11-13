import 'package:flutter/material.dart';

import '../../../../theme.dart';

/// Semantic colors for finance statuses, mapped to the app theme tokens so
/// every tab styles overdue/paid/due states identically.
class FinanceStatus {
  FinanceStatus._();

  static const Color paid = AppTheme.success;
  static const Color overdue = AppTheme.error;
  static const Color dueSoon = AppTheme.warning;
  static const Color neutral = Color(0xFF64748B);
  static const Color linked = AppTheme.primary;
  static const Color billPayment = Color(0xFF7C3AED);

  static Color payable(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'unpaid').toString().toLowerCase().trim();
    if (status == 'paid') return paid;
    final due = _asDate(p['dueDate']);
    if (due == null) return neutral;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(due.year, due.month, due.day);
    if (d.isBefore(today)) return overdue;
    return dueSoon;
  }

  static String payableLabel(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'unpaid').toString().toLowerCase().trim();
    if (status == 'paid') return 'Paid';
    final due = _asDate(p['dueDate']);
    if (due == null) return 'Unpaid';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(due.year, due.month, due.day);
    if (d.isBefore(today)) return 'Overdue';
    return 'Due';
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

/// Small rounded status chip used across expenses and payables rows.
class FinanceStatusBadge extends StatelessWidget {
  const FinanceStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
