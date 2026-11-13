import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../../../widgets/dashboard/empty_state.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'finance_category_bar.dart';
import 'finance_status.dart';

/// Searchable/filterable expense list with source, category and date filters.
class FinanceExpensesTab extends StatelessWidget {
  const FinanceExpensesTab({
    super.key,
    required this.expenses,
    required this.isAdmin,
    required this.fmt,
    required this.sourceFilter,
    required this.categoryFilter,
    required this.dateRange,
    required this.searchQuery,
    required this.onSourceFilterChanged,
    required this.onCategoryFilterChanged,
    required this.onDateRangeChanged,
    required this.onSearchChanged,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
    required this.onViewPurchase,
    this.onUnpayBill,
  });

  final List<Map<String, dynamic>> expenses;
  final bool isAdmin;
  final FinanceFormat fmt;
  final String sourceFilter;
  final String? categoryFilter;
  final DateTimeRange? dateRange;
  final String searchQuery;
  final ValueChanged<String> onSourceFilterChanged;
  final ValueChanged<String?> onCategoryFilterChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final ValueChanged<Map<String, dynamic>> onViewPurchase;
  final ValueChanged<Map<String, dynamic>>? onUnpayBill;

  @override
  Widget build(BuildContext context) {
    final categories = <String>{for (final e in expenses) (e['category'] ?? '').toString()}
      ..removeWhere((c) => c.trim().isEmpty);

    var filtered = expenses.where((e) {
      // Source filter
      final linked = FinanceMetrics.isLinkedPurchase(e);
      final bill = FinanceMetrics.isPayablePayment(e);
      if (sourceFilter == FinanceMetrics.inventorySource && !linked) {
        return false;
      }
      if (sourceFilter == FinanceMetrics.payablePaymentSource && !bill) {
        return false;
      }
      if (sourceFilter == FinanceMetrics.manualSource && (linked || bill)) {
        return false;
      }

      // Category filter
      if (categoryFilter != null &&
          (e['category'] ?? '').toString() != categoryFilter) {
        return false;
      }

      // Date range
      if (dateRange != null) {
        final d = FinanceMetrics.expenseDate(e);
        if (d == null) return false;
        if (d.isBefore(dateRange!.start)) return false;
        if (d.isAfter(
          dateRange!.end.add(const Duration(days: 1)),
        )) {
          return false;
        }
      }

      // Search
      final q = searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        const fields = [
          'name',
          'category',
          'notes',
          'supplierName',
          'receiptNumber',
        ];
        var hit = false;
        for (final f in fields) {
          if ((e[f] ?? '').toString().toLowerCase().contains(q)) {
            hit = true;
            break;
          }
        }
        if (!hit) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final ad = FinanceMetrics.expenseDate(a);
      final bd = FinanceMetrics.expenseDate(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final total =
        filtered.fold<double>(0, (sum, e) => sum + FinanceMetrics.amountOf(e));
    final manualCount = filtered
        .where((e) =>
            !FinanceMetrics.isLinkedPurchase(e) &&
            !FinanceMetrics.isPayablePayment(e))
        .length;
    final linkedCount = filtered.where(FinanceMetrics.isLinkedPurchase).length;
    final billCount = filtered.where(FinanceMetrics.isPayablePayment).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmt.money(total),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${filtered.length} expenses',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search expenses...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip(
                      context,
                      label: 'All (${filtered.length})',
                      selected: sourceFilter == 'all',
                      onTap: () => onSourceFilterChanged('all'),
                    ),
                    _chip(
                      context,
                      label: 'Manual ($manualCount)',
                      icon: Icons.edit_note,
                      selected: sourceFilter == FinanceMetrics.manualSource,
                      onTap: () =>
                          onSourceFilterChanged(FinanceMetrics.manualSource),
                    ),
                    _chip(
                      context,
                      label: 'Inventory ($linkedCount)',
                      icon: Icons.inventory_2_outlined,
                      selected:
                          sourceFilter == FinanceMetrics.inventorySource,
                      onTap: () =>
                          onSourceFilterChanged(FinanceMetrics.inventorySource),
                    ),
                    _chip(
                      context,
                      label: 'Bills ($billCount)',
                      icon: Icons.receipt_long_outlined,
                      selected:
                          sourceFilter == FinanceMetrics.payablePaymentSource,
                      onTap: () => onSourceFilterChanged(
                          FinanceMetrics.payablePaymentSource),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dateRangeChip(context),
                  _categoryDropdown(context, categories.toList()..sort()),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No matching expenses',
                    subtitle: 'Adjust your filters or add a new expense.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _ExpenseCard(
                    expense: filtered[index],
                    fmt: fmt,
                    isAdmin: isAdmin,
                    onOpen: () => onOpen(filtered[index]),
                    onDelete: () => onDelete(filtered[index]),
                    onViewPurchase: () => onViewPurchase(filtered[index]),
                    onUnpay: onUnpayBill == null
                        ? null
                        : () => onUnpayBill!(filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _dateRangeChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRange = dateRange != null;
    return ActionChip(
      avatar: Icon(
        Icons.date_range,
        size: 16,
        color: hasRange ? scheme.primary : null,
      ),
      label: Text(
        hasRange
            ? '${FinanceFormat.date(dateRange!.start)} → ${FinanceFormat.date(dateRange!.end)}'
            : 'Date range',
      ),
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: dateRange,
        );
        if (picked != null) onDateRangeChanged(picked);
      },
    );
  }

  Widget _categoryDropdown(BuildContext context, List<String> categories) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        value: categoryFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.category_outlined),
          border: OutlineInputBorder(),
        ),
        hint: const Text('Category'),
        items: [
          const DropdownMenuItem(value: null, child: Text('All categories')),
          ...categories.map(
            (c) => DropdownMenuItem(value: c, child: Text(c)),
          ),
        ],
        onChanged: onCategoryFilterChanged,
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.fmt,
    required this.isAdmin,
    required this.onOpen,
    required this.onDelete,
    required this.onViewPurchase,
    this.onUnpay,
  });

  final Map<String, dynamic> expense;
  final FinanceFormat fmt;
  final bool isAdmin;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onViewPurchase;
  final VoidCallback? onUnpay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (expense['name'] ?? '').toString();
    final category = (expense['category'] ?? '').toString();
    final amount = FinanceMetrics.amountOf(expense);
    final date = FinanceMetrics.expenseDate(expense);
    final notes = (expense['notes'] ?? '').toString();
    final supplier = (expense['supplierName'] ?? '').toString().trim();
    final method = (expense['paymentMethod'] ?? '').toString().trim();
    final linked = FinanceMetrics.isLinkedPurchase(expense);
    final bill = FinanceMetrics.isPayablePayment(expense);
    final accent = bill ? FinanceStatus.billPayment : financeCategoryColor(category);

    final details = <String>[
      if (date != null) FinanceFormat.date(date),
      if (category.trim().isNotEmpty) category,
      if (supplier.isNotEmpty) supplier,
      if (method.isNotEmpty) method,
    ].join(' • ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  linked
                      ? Icons.inventory_2_outlined
                      : bill
                          ? Icons.receipt_long_outlined
                          : financeCategoryIcon(category),
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.trim().isEmpty
                                ? (category.isEmpty ? 'Expense' : category)
                                : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (linked) ...[
                          const SizedBox(width: 6),
                          const FinanceStatusBadge(
                            label: 'Linked',
                            color: FinanceStatus.linked,
                            icon: Icons.link,
                          ),
                        ],
                        if (bill) ...[
                          const SizedBox(width: 6),
                          const FinanceStatusBadge(
                            label: 'Bill',
                            color: FinanceStatus.billPayment,
                            icon: Icons.receipt_long_outlined,
                          ),
                        ],
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmt.money(amount),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 4),
                if (linked)
                  IconButton(
                    tooltip: 'Linked to an inventory purchase. Delete the '
                        'purchase receipt instead.',
                    onPressed: onViewPurchase,
                    icon: const Icon(Icons.lock_outline),
                  )
                else if (bill)
                  IconButton(
                    tooltip: 'Recorded from a bill payment. Mark the bill '
                        'unpaid to remove it.',
                    onPressed: onUnpay ?? onDelete,
                    icon: const Icon(Icons.undo),
                  )
                else
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
