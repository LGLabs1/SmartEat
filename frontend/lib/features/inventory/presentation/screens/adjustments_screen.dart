import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smarteat/models/inventory_item.dart';
import 'package:smarteat/theme.dart';
import 'package:smarteat/widgets/dashboard/empty_state.dart';
import 'package:smarteat/widgets/dashboard/kpi_card.dart';
import 'package:smarteat/widgets/responsive_search_field.dart';
import 'package:smarteat/widgets/smart_eat_header.dart';

import '../../data/models/stock_adjustment.dart';
import '../widgets/adjustment_dialog.dart';

class AdjustmentsScreen extends StatefulWidget {
  final List<StockAdjustment> adjustments;
  final List<InventoryItem> items;
  final bool showAppBar;
  final ValueChanged<StockAdjustment>? onAdjustStock;
  final String? performedBy;

  const AdjustmentsScreen({
    Key? key,
    required this.adjustments,
    this.items = const [],
    this.showAppBar = true,
    this.onAdjustStock,
    this.performedBy,
  }) : super(key: key);

  @override
  State<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

class _AdjustmentsScreenState extends State<AdjustmentsScreen> {
  final _search = TextEditingController();
  String _typeFilter = 'all';

  static const _reasonLabels = {
    'overcount': 'Overcount',
    'spoilage': 'Spoilage',
    'theft': 'Theft',
    'donation': 'Donation',
    'countFix': 'Count correction',
    'other': 'Other',
  };

  List<StockAdjustment> get _visibleAdjustments {
    final query = _search.text.trim().toLowerCase();
    final rows = widget.adjustments.where((adjustment) {
      if (_typeFilter == 'increase' && adjustment.deltaBase <= 0) return false;
      if (_typeFilter == 'decrease' && adjustment.deltaBase >= 0) return false;
      if (query.isEmpty) return true;
      return _itemName(adjustment.itemId).toLowerCase().contains(query) ||
          adjustment.adjustmentNumber.toLowerCase().contains(query) ||
          _reasonLabel(adjustment.reasonCode).toLowerCase().contains(query) ||
          (adjustment.notes ?? '').toLowerCase().contains(query) ||
          (adjustment.performedBy ?? '').toLowerCase().contains(query);
    }).toList();
    rows.sort((a, b) => b.performedAt.compareTo(a.performedAt));
    return rows;
  }

  String _itemName(String itemId) {
    for (final item in widget.items) {
      if (item.id == itemId) return item.name;
    }
    return itemId.isEmpty ? 'Unknown item' : itemId;
  }

  String _reasonLabel(String code) => _reasonLabels[code] ?? code;

  String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  String _formatDelta(double delta) =>
      '${delta >= 0 ? '+' : '-'}${_qty(delta.abs())}';

  Future<void> _openAdjustment() async {
    if (widget.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an inventory item first.')),
      );
      return;
    }
    final adjustment = await showDialog<StockAdjustment>(
      context: context,
      builder: (_) => AdjustmentDialog(
        items: widget.items,
        performedBy: widget.performedBy,
      ),
    );
    if (adjustment != null) widget.onAdjustStock?.call(adjustment);
  }

  Widget _adjustButton({bool compact = false}) {
    return FilledButton.icon(
      key: const Key('adjustments-adjust-stock-button'),
      onPressed: _openAdjustment,
      icon: Icon(Icons.add_circle_outline, size: compact ? 16 : 18),
      label: const Text('Adjust Stock'),
      style: FilledButton.styleFrom(
        visualDensity:
            compact ? VisualDensity.compact : const VisualDensity(vertical: -1),
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _typeFilter == value,
        onSelected: (_) => setState(() => _typeFilter = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _visibleAdjustments;
    final unitsIn = widget.adjustments
        .where((a) => a.deltaBase > 0)
        .fold<double>(0, (sum, a) => sum + a.deltaBase);
    final unitsOut = widget.adjustments
        .where((a) => a.deltaBase < 0)
        .fold<double>(0, (sum, a) => sum - a.deltaBase);
    final net = widget.adjustments.fold<double>(
      0,
      (sum, a) => sum + a.deltaBase,
    );

    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: widget.showAppBar
            ? SmartEatHeader(
                titleText: 'Stock Adjustments',
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stock Adjustments'),
                    Text(
                      '${widget.adjustments.length} manual corrections',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                actions: [_adjustButton(compact: true)],
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.showAppBar)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stock Adjustments',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${widget.adjustments.length} manual corrections',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _adjustButton(),
                      ],
                    ),
                  if (!widget.showAppBar) const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;
                      final width = wide
                          ? (constraints.maxWidth - 24) / 4
                          : (constraints.maxWidth - 8) / 2;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: width,
                            child: KpiCard(
                              title: 'Adjustments',
                              value: '${widget.adjustments.length}',
                              icon: Icons.tune,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: KpiCard(
                              title: 'Units In',
                              value: _qty(unitsIn),
                              icon: Icons.arrow_upward,
                              color: AppTheme.sageSuccess,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: KpiCard(
                              title: 'Units Out',
                              value: _qty(unitsOut),
                              icon: Icons.arrow_downward,
                              color: theme.colorScheme.error,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: KpiCard(
                              title: 'Net Change',
                              value: _formatDelta(net),
                              icon: Icons.swap_vert,
                              color: AppTheme.sageAccent,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ResponsiveSearchField(
                    tooltip: 'Search adjustments',
                    fieldBuilder: (context, {required bool autofocus}) =>
                        TextField(
                      autofocus: autofocus,
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search by item, reference, reason, notes...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', 'all'),
                        _filterChip('Increases', 'increase'),
                        _filterChip('Decreases', 'decrease'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? EmptyState(
                      icon: Icons.tune,
                      title: 'No manual adjustments yet',
                      subtitle:
                          'Use Adjust Stock to record count corrections, spoilage, donations, and other manual changes.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _adjustmentCard(rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adjustmentCard(StockAdjustment adjustment) {
    final theme = Theme.of(context);
    final increase = adjustment.deltaBase >= 0;
    final color = increase ? AppTheme.sageSuccess : theme.colorScheme.error;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(
                increase ? Icons.add : Icons.remove,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _itemName(adjustment.itemId),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (adjustment.adjustmentNumber.isNotEmpty)
                        Chip(
                          label: Text(adjustment.adjustmentNumber),
                          visualDensity: VisualDensity.compact,
                          labelStyle: const TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_reasonLabel(adjustment.reasonCode)} • ${adjustment.performedBy ?? 'admin'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a')
                        .format(adjustment.performedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_qty(adjustment.qtyBeforeBase)} → ${_qty(adjustment.qtyAfterBase)} ${_unitFor(adjustment.itemId)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (adjustment.notes != null && adjustment.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        adjustment.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDelta(adjustment.deltaBase),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _unitFor(String itemId) {
    for (final item in widget.items) {
      if (item.id == itemId) return item.effectiveBaseUnit;
    }
    return '';
  }
}
