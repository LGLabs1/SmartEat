import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../models/inventory_item.dart';
import '../../../../../widgets/dashboard/empty_state.dart';
import '../../../../../widgets/dashboard/kpi_card.dart';
import '../../data/models/stock_movement.dart';

String movementTypeLabel(StockMovementType type) {
  switch (type) {
    case StockMovementType.purchase:
      return 'Purchase';
    case StockMovementType.adjustIncrease:
      return 'Adjustment (+)';
    case StockMovementType.adjustDecrease:
      return 'Adjustment (-)';
    case StockMovementType.saleConsumption:
      return 'Sale Consumption';
    case StockMovementType.writeOff:
      return 'Write-off';
    case StockMovementType.damaged:
      return 'Damaged/Waste';
    case StockMovementType.countCorrection:
      return 'Count Correction';
  }
}

/// Full, filterable audit trail of every stock movement (purchases,
/// adjustments, sale consumption, write-offs). Movements are grouped by day
/// with a daily net total, and a KPI strip summarises the filtered window.
class MovementsScreen extends StatefulWidget {
  final List<StockMovement> movements;
  final List<InventoryItem> items;

  const MovementsScreen({
    Key? key,
    required this.movements,
    this.items = const [],
  }) : super(key: key);

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  final TextEditingController _search = TextEditingController();
  String _typeFilter = 'all';
  String? _itemFilter;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _itemName(String itemId) {
    for (final i in widget.items) {
      if (i.id == itemId) return i.name;
    }
    return itemId.isEmpty ? 'Item' : itemId;
  }

  bool _isIncrease(StockMovementType type) {
    return type == StockMovementType.purchase ||
        type == StockMovementType.adjustIncrease ||
        type == StockMovementType.countCorrection;
  }

  Color _typeColor(StockMovementType type) {
    switch (type) {
      case StockMovementType.purchase:
        return const Color(0xFF2563EB);
      case StockMovementType.adjustIncrease:
      case StockMovementType.countCorrection:
        return const Color(0xFF16A34A);
      case StockMovementType.adjustDecrease:
      case StockMovementType.writeOff:
      case StockMovementType.damaged:
      case StockMovementType.saleConsumption:
        return const Color(0xFFDC2626);
    }
  }

  IconData _typeIcon(StockMovementType type) {
    switch (type) {
      case StockMovementType.purchase:
        return Icons.shopping_cart_outlined;
      case StockMovementType.adjustIncrease:
        return Icons.add_circle_outline;
      case StockMovementType.adjustDecrease:
        return Icons.remove_circle_outline;
      case StockMovementType.saleConsumption:
        return Icons.point_of_sale_outlined;
      case StockMovementType.writeOff:
        return Icons.delete_outline;
      case StockMovementType.damaged:
        return Icons.warning_amber_outlined;
      case StockMovementType.countCorrection:
        return Icons.rule_outlined;
    }
  }

  String _money(double v) =>
      NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(v);

  String _qty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  List<StockMovement> get _filtered {
    final q = _search.text.trim().toLowerCase();
    var list = widget.movements.where((m) {
      if (_typeFilter == 'increase' && !_isIncrease(m.type)) return false;
      if (_typeFilter == 'decrease' && _isIncrease(m.type)) return false;
      if (_typeFilter == 'purchase' && m.type != StockMovementType.purchase) {
        return false;
      }
      if (_typeFilter == 'adjust' &&
          m.type != StockMovementType.adjustIncrease &&
          m.type != StockMovementType.adjustDecrease) {
        return false;
      }
      if (_itemFilter != null && m.itemId != _itemFilter) return false;
      if (_dateRange != null) {
        final d = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
        final start = DateTime(
            _dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
        final end = DateTime(
            _dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      if (q.isNotEmpty) {
        final name = _itemName(m.itemId).toLowerCase();
        final ref = (m.referenceId ?? '').toLowerCase();
        final notes = (m.notes ?? '').toLowerCase();
        final reason = (m.reasonCode ?? '').toLowerCase();
        if (!name.contains(q) &&
            !ref.contains(q) &&
            !notes.contains(q) &&
            !reason.contains(q) &&
            !movementTypeLabel(m.type).toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    final unitsIn = filtered
        .where((m) => m.changeBase > 0)
        .fold<double>(0, (s, m) => s + m.changeBase);
    final unitsOut = filtered
        .where((m) => m.changeBase < 0)
        .fold<double>(0, (s, m) => s + m.changeBase.abs());
    final spend = filtered
        .where((m) => m.type == StockMovementType.purchase)
        .fold<double>(0, (s, m) => s + (m.changeBase * m.unitCostAtEvent));

    // Group the filtered movements by calendar day (most recent first).
    final groups = <DateTime, List<StockMovement>>{};
    for (final m in filtered) {
      final day = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      groups.putIfAbsent(day, () => []).add(m);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('Movement History')),
      body: Column(
        children: [
          _buildHeader(context, theme, filtered.length, unitsIn, unitsOut, spend),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.history,
                      title: 'No movement history',
                      subtitle:
                          'Stock movements from purchases, adjustments, and sales appear here as inventory changes.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final day = days[i];
                      final rows = groups[day]!;
                      final net =
                          rows.fold<double>(0, (s, m) => s + m.changeBase);
                      return _DayGroup(
                        day: day,
                        netChange: net,
                        count: rows.length,
                        children: rows
                            .map((m) => _MovementCard(
                                  movement: m,
                                  itemName: _itemName(m.itemId),
                                  isIncrease: _isIncrease(m.type),
                                  color: _typeColor(m.type),
                                  icon: _typeIcon(m.type),
                                  qty: _qty,
                                  money: _money,
                                ))
                            .toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    int count,
    double unitsIn,
    double unitsOut,
    double spend,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KpiCard(
                  title: 'Movements',
                  value: '$count',
                  icon: Icons.swap_vert,
                  color: theme.colorScheme.primary,
                  description: 'Number of stock movement records in the current filter/range.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiCard(
                  title: 'Units In',
                  value: _qty(unitsIn),
                  icon: Icons.arrow_upward,
                  color: const Color(0xFF16A34A),
                  description: 'Quantity added by inbound movements (e.g., purchases/adjustments in) in the current view.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiCard(
                  title: 'Units Out',
                  value: _qty(unitsOut),
                  icon: Icons.arrow_downward,
                  color: const Color(0xFFDC2626),
                  description: 'Quantity removed by outbound movements (e.g., sale consumption, damage, write-off) in the current view.',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KpiCard(
                  title: 'Purchase Spend',
                  value: _money(spend),
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF7C3AED),
                  description: 'Total cost impact from purchase/inbound costed movements in the current view.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search by item, reference, notes...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _typeChip('All', 'all'),
                _typeChip('Increases', 'increase'),
                _typeChip('Decreases', 'decrease'),
                _typeChip('Purchases', 'purchase'),
                _typeChip('Adjustments', 'adjust'),
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
              _itemDropdown(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _typeFilter == value,
        onSelected: (_) => setState(() => _typeFilter = value),
      ),
    );
  }

  Widget _dateRangeChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasRange = _dateRange != null;
    return ActionChip(
      avatar: Icon(Icons.date_range,
          size: 16, color: hasRange ? scheme.primary : null),
      label: Text(
        hasRange
            ? '${DateFormat('MMM d').format(_dateRange!.start)} → ${DateFormat('MMM d').format(_dateRange!.end)}'
            : 'Date range',
      ),
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: _dateRange,
        );
        if (picked != null) setState(() => _dateRange = picked);
      },
    );
  }

  Widget _itemDropdown(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String?>(
        initialValue: _itemFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.inventory_2_outlined),
          border: OutlineInputBorder(),
        ),
        hint: const Text('All items'),
        items: [
          const DropdownMenuItem(value: null, child: Text('All items')),
          ...items.map(
            (i) => DropdownMenuItem(value: i.id, child: Text(i.name)),
          ),
        ],
        onChanged: (v) => setState(() => _itemFilter = v),
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.netChange,
    required this.count,
    required this.children,
  });

  final DateTime day;
  final double netChange;
  final int count;
  final List<Widget> children;

  String _dayLabel(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return DateFormat('EEEE, MMM d, yyyy').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final netPositive = netChange >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dayLabel(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (netPositive
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${netPositive ? '+' : ''}${netChange % 1 == 0 ? netChange.toInt() : netChange.toStringAsFixed(2)} net',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: netPositive
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.itemName,
    required this.isIncrease,
    required this.color,
    required this.icon,
    required this.qty,
    required this.money,
  });

  final StockMovement movement;
  final String itemName;
  final bool isIncrease;
  final Color color;
  final IconData icon;
  final String Function(double) qty;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = movement;
    final hasCost = m.totalCostImpact.abs() > 0 ||
        (m.unitCostAtEvent > 0 && m.type == StockMovementType.purchase);
    final costValue = m.type == StockMovementType.purchase
        ? m.changeBase * m.unitCostAtEvent
        : m.totalCostImpact;

    final meta = <String>[
      if (m.performedBy != null && m.performedBy!.trim().isNotEmpty)
        'by ${m.performedBy}',
      if (m.referenceId != null && m.referenceId!.trim().isNotEmpty)
        'ref ${m.referenceId}',
    ].join(' • ');

    final note = (m.notes != null && m.notes!.trim().isNotEmpty)
        ? m.notes!.trim()
        : (m.reasonCode != null && m.reasonCode!.trim().isNotEmpty
            ? m.reasonCode!.trim()
            : null);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          movementTypeLabel(m.type),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        DateFormat('h:mm a').format(m.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${qty(m.qtyBeforeBase)} → ${qty(m.qtyAfterBase)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
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
                Text(
                  '${isIncrease ? '+' : '-'}${qty(m.changeBase.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                if (hasCost) ...[
                  const SizedBox(height: 2),
                  Text(
                    money(costValue.abs()),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
