import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'finance_category_bar.dart';
import 'finance_status.dart';

/// Bottom sheet showing payable details with role-gated actions.
class PayableDetailSheet extends StatelessWidget {
  const PayableDetailSheet({
    super.key,
    required this.payable,
    required this.fmt,
    required this.isAdmin,
    this.onEdit,
    this.onDelete,
    this.onTogglePaid,
  });

  final Map<String, dynamic> payable;
  final FinanceFormat fmt;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePaid;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> payable,
    required FinanceFormat fmt,
    required bool isAdmin,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onTogglePaid,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PayableDetailSheet(
        payable: payable,
        fmt: fmt,
        isAdmin: isAdmin,
        onEdit: onEdit,
        onDelete: onDelete,
        onTogglePaid: onTogglePaid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (payable['name'] ?? 'Bill').toString();
    final amount = FinanceMetrics.amountOf(payable);
    final isVariable = FinanceMetrics.isVariablePayable(payable);
    final estimate = FinanceMetrics.estimatedAmountOf(payable);
    final history = FinanceMetrics.payableHistory(payable);
    final due = FinanceFormat.asDate(payable['dueDate']);
    final frequency = (payable['frequency'] ?? '').toString();
    final vendor = (payable['vendor'] ?? '').toString();
    final notes = (payable['notes'] ?? '').toString();
    final isPaid = FinanceMetrics.isPaid(payable);
    final color = FinanceStatus.payable(payable);
    final label = FinanceStatus.payableLabel(payable);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isPaid
                          ? Icons.check_circle_outline
                          : label == 'Overdue'
                              ? Icons.error_outline
                              : Icons.schedule_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FinanceStatusBadge(label: label, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isVariable ? 'Variable amount' : fmt.money(amount),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: isVariable ? scheme.onSurfaceVariant : null,
                  fontStyle: isVariable ? FontStyle.italic : null,
                ),
              ),
              if (isVariable && estimate > 0)
                Text(
                  'Estimated ${fmt.money(estimate)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const Divider(height: 28),
              FinanceDetailRow('Due Date',
                  due == null ? 'Not set' : FinanceFormat.date(due)),
              FinanceDetailRow('Frequency',
                  frequency.isEmpty ? 'Not set' : frequency),
              FinanceDetailRow('Amount Type', isVariable ? 'Variable' : 'Fixed'),
              if (vendor.isNotEmpty) FinanceDetailRow('Vendor', vendor),
              if (notes.isNotEmpty) FinanceDetailRow('Notes', notes),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Recent Amounts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in history.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value == null
                                ? 'Recorded'
                                : FinanceFormat.date(entry.value!),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          fmt.money(entry.key),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              if (isAdmin)
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onTogglePaid,
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isPaid ? scheme.onSurfaceVariant : AppTheme.success,
                            ),
                            icon: Icon(
                              isPaid ? Icons.undo_outlined : Icons.check_outlined,
                            ),
                            label: Text(isPaid ? 'Mark Unpaid' : 'Mark Paid'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete Payable'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
