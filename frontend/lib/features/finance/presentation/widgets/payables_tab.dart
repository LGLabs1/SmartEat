import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../../../widgets/dashboard/empty_state.dart';
import '../../../../widgets/dashboard/section_card.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'finance_status.dart';

/// Payables list segmented into Upcoming / Overdue / Paid with an AP aging
/// summary card.
class FinancePayablesTab extends StatelessWidget {
  const FinancePayablesTab({
    super.key,
    required this.payables,
    required this.isAdmin,
    required this.fmt,
    required this.segment,
    required this.onSegmentChanged,
    required this.onAdd,
    required this.onOpen,
    required this.onExport,
  });

  final List<Map<String, dynamic>> payables;
  final bool isAdmin;
  final FinanceFormat fmt;
  final String segment;
  final ValueChanged<String> onSegmentChanged;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final aging = FinanceMetrics.agingBuckets(payables);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool isOverdue(Map<String, dynamic> p) {
      if (FinanceMetrics.isPaid(p)) return false;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) return false;
      return DateTime(due.year, due.month, due.day).isBefore(today);
    }

    final upcoming = payables
        .where((p) => !FinanceMetrics.isPaid(p) && !isOverdue(p))
        .toList();
    final overdue = payables.where(isOverdue).toList();
    final paid = payables.where(FinanceMetrics.isPaid).toList();

    final items = switch (segment) {
      'overdue' => overdue,
      'paid' => paid,
      _ => upcoming,
    }..sort((a, b) {
        final ad = FinanceFormat.asDate(a['dueDate']);
        final bd = FinanceFormat.asDate(b['dueDate']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Payables',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Export CSV',
                    onPressed: onExport,
                    icon: const Icon(Icons.download_outlined),
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
              _AgingCard(aging: aging, fmt: fmt),
              const SizedBox(height: 12),
              Row(
                children: [
                  _segmented(
                    context,
                    'Upcoming',
                    upcoming.length,
                    'upcoming',
                  ),
                  const SizedBox(width: 8),
                  _segmented(context, 'Overdue', overdue.length, 'overdue'),
                  const SizedBox(width: 8),
                  _segmented(context, 'Paid', paid.length, 'paid'),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyState(
                    icon: Icons.payment_outlined,
                    title: 'Nothing here',
                    subtitle: 'No payables in this category.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _PayableCard(
                    payable: items[index],
                    fmt: fmt,
                    onOpen: () => onOpen(items[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _segmented(
    BuildContext context,
    String label,
    int count,
    String value,
  ) {
    return Expanded(
      child: SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: value,
            label: Text('$label ($count)'),
          ),
        ],
        selected: {segment},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onSegmentChanged(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _AgingCard extends StatelessWidget {
  const _AgingCard({required this.aging, required this.fmt});

  final Map<String, double> aging;
  final FinanceFormat fmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final order = ['Current', '1-30 days', '31-60 days', '60+ days'];
    final colors = {
      'Current': AppTheme.success,
      '1-30 days': AppTheme.warning,
      '31-60 days': const Color(0xFFF97316),
      '60+ days': AppTheme.error,
    };

    return SectionCard(
      title: 'Accounts Payable Aging',
      icon: Icons.hourglass_bottom_rounded,
      iconColor: AppTheme.warning,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final key in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[key],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    fmt.money(aging[key] ?? 0),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({
    required this.payable,
    required this.fmt,
    required this.onOpen,
  });

  final Map<String, dynamic> payable;
  final FinanceFormat fmt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (payable['name'] ?? 'Payable').toString();
    final isVariable = FinanceMetrics.isVariablePayable(payable);
    final amount = FinanceMetrics.amountOf(payable);
    final estimate = FinanceMetrics.estimatedAmountOf(payable);
    final due = FinanceFormat.asDate(payable['dueDate']);
    final frequency = (payable['frequency'] ?? '').toString();
    final notes = (payable['notes'] ?? '').toString();
    final color = FinanceStatus.payable(payable);
    final label = FinanceStatus.payableLabel(payable);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: label == 'Overdue'
              ? AppTheme.error.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  label == 'Paid'
                      ? Icons.check_circle_outline
                      : label == 'Overdue'
                          ? Icons.error_outline
                          : Icons.schedule_outlined,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${due == null ? 'No due date' : 'Due: ${FinanceFormat.date(due)}'}'
                      '${frequency.isEmpty ? '' : ' • $frequency'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isVariable)
                    _VariableAmount(estimate: estimate, fmt: fmt)
                  else
                    Text(
                      fmt.money(amount),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(height: 4),
                  FinanceStatusBadge(label: label, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact right-aligned display for a variable bill: a "Variable" label with
/// an optional estimated amount beneath it.
class _VariableAmount extends StatelessWidget {
  const _VariableAmount({required this.estimate, required this.fmt});

  final double estimate;
  final FinanceFormat fmt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Variable',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (estimate > 0)
          Text(
            'Est. ${fmt.money(estimate)}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
