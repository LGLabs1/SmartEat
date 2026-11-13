import 'package:flutter/material.dart';

/// A labelled progress bar for category spend (or budget usage).
class FinanceCategoryBar extends StatelessWidget {
  const FinanceCategoryBar({
    super.key,
    required this.category,
    required this.amount,
    required this.percent,
    required this.color,
    this.budget,
    this.money,
  });

  final String category;
  final double amount;
  final double percent;
  final Color color;

  /// Optional budget for this category, shown as helper text.
  final double? budget;
  final String Function(num)? money;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overBudget = budget != null && budget! > 0 && amount > budget!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money == null
                    ? '${percent.toStringAsFixed(1)}%'
                    : '${percent.toStringAsFixed(1)}% • ${money!(amount)}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                overBudget ? scheme.error : color,
              ),
              minHeight: 8,
            ),
          ),
          if (budget != null && budget! > 0) ...[
            const SizedBox(height: 4),
            Text(
              overBudget
                  ? 'Over budget${money == null ? '' : ' • limit ${money!(budget!)}'}'
                  : 'Budget${money == null ? '' : ' • ${money!(budget!)}'}',
              style: TextStyle(
                fontSize: 11,
                color: overBudget ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: overBudget ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A simple label/value row used inside detail sheets and dialogs.
class FinanceDetailRow extends StatelessWidget {
  const FinanceDetailRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a finance category to a stable accent color for bars and icons.
Color financeCategoryColor(String category) {
  const colors = {
    'Ingredients': Color(0xFFF97316),
    'Utilities': Color(0xFFF59E0B),
    'Rent': Color(0xFF1E88E5),
    'Salaries': Color(0xFF16A34A),
    'Equipment': Color(0xFF8B5CF6),
    'Maintenance': Color(0xFF92400E),
    'Marketing': Color(0xFFEC4899),
    'Supplies': Color(0xFF14B8A6),
    'Transportation': Color(0xFF6366F1),
    'Taxes': Color(0xFFEF5350),
    'Insurance': Color(0xFF06B6D4),
    'Bills': Color(0xFF0EA5E9),
    'Other': Color(0xFF64748B),
  };
  return colors[category] ?? const Color(0xFF1E88E5);
}

IconData financeCategoryIcon(String category) {
  const icons = {
    'Ingredients': Icons.restaurant,
    'Utilities': Icons.electric_bolt,
    'Rent': Icons.home,
    'Salaries': Icons.people,
    'Equipment': Icons.build,
    'Maintenance': Icons.handyman,
    'Marketing': Icons.campaign,
    'Supplies': Icons.inventory,
    'Transportation': Icons.local_shipping,
    'Taxes': Icons.account_balance,
    'Insurance': Icons.shield,
    'Bills': Icons.receipt_long,
    'Other': Icons.more_horiz,
  };
  return icons[category] ?? Icons.receipt;
}
