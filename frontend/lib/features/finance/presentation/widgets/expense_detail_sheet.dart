import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'finance_category_bar.dart';
import 'finance_status.dart';

/// Bottom sheet showing full expense details. Linked inventory-purchase
/// expenses expose a "View purchase" action that navigates to Inventory.
class ExpenseDetailSheet extends StatelessWidget {
  const ExpenseDetailSheet({
    super.key,
    required this.expense,
    required this.fmt,
    required this.isAdmin,
    this.onDelete,
    this.onViewPurchase,
  });

  final Map<String, dynamic> expense;
  final FinanceFormat fmt;
  final bool isAdmin;
  final VoidCallback? onDelete;
  final VoidCallback? onViewPurchase;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> expense,
    required FinanceFormat fmt,
    required bool isAdmin,
    VoidCallback? onDelete,
    VoidCallback? onViewPurchase,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ExpenseDetailSheet(
        expense: expense,
        fmt: fmt,
        isAdmin: isAdmin,
        onDelete: onDelete,
        onViewPurchase: onViewPurchase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (expense['name'] ?? '').toString();
    final category = (expense['category'] ?? '').toString();
    final amount = FinanceMetrics.amountOf(expense);
    final date = FinanceMetrics.expenseDate(expense);
    final notes = (expense['notes'] ?? '').toString();
    final supplier = (expense['supplierName'] ?? '').toString().trim();
    final receipt = (expense['receiptNumber'] ?? '').toString().trim();
    final method = (expense['paymentMethod'] ?? '').toString().trim();
    final status = (expense['paymentStatus'] ?? '').toString().trim();
    final source = FinanceMetrics.source(expense);
    final linked = FinanceMetrics.isLinkedPurchase(expense);
    final linkedPurchaseId =
        (expense['linkedPurchaseId'] ?? '').toString().trim();

    final title = name.trim().isEmpty
        ? (category.isEmpty ? 'Expense' : category)
        : name;

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
                      color: financeCategoryColor(category)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      financeCategoryIcon(category),
                      color: financeCategoryColor(category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FinanceStatusBadge(
                    label: linked ? 'Inventory' : 'Manual',
                    color: linked
                        ? FinanceStatus.linked
                        : FinanceStatus.neutral,
                    icon: linked ? Icons.link : Icons.edit_note,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fmt.money(amount),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Divider(height: 28),
              FinanceDetailRow('Category',
                  category.isEmpty ? 'Uncategorised' : category),
              FinanceDetailRow('Date',
                  date == null ? 'Not set' : FinanceFormat.date(date)),
              if (supplier.isNotEmpty) FinanceDetailRow('Supplier', supplier),
              if (receipt.isNotEmpty) FinanceDetailRow('Receipt', receipt),
              if (method.isNotEmpty)
                FinanceDetailRow('Payment Method', method),
              if (status.isNotEmpty) FinanceDetailRow('Payment Status', status),
              FinanceDetailRow('Source', source),
              if (linkedPurchaseId.isNotEmpty)
                FinanceDetailRow('Linked Purchase', linkedPurchaseId),
              if (notes.isNotEmpty) FinanceDetailRow('Notes', notes),
              const SizedBox(height: 16),
              if (linked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FinanceStatus.linked.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 16, color: FinanceStatus.linked),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Auto-posted from an inventory purchase. Delete the '
                          'purchase receipt to keep the books consistent.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (linked && onViewPurchase != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onViewPurchase,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('View Purchase'),
                      ),
                    ),
                  if (!linked && isAdmin && onDelete != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
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
