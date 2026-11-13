import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../../models/inventory_item.dart';
import '../../../../../widgets/dashboard/empty_state.dart';
import '../../../../../widgets/dashboard/kpi_card.dart';
import '../../data/models/purchase_receipt.dart';
import '../providers/purchase_list_notifier.dart';

/// Durable purchase history (GRN). Shows every recorded receipt with a KPI
/// summary, search/filter controls, and expandable per-line breakdowns.
class PurchasesScreen extends StatefulWidget {
  final List<PurchaseReceipt> purchases;
  final List<InventoryItem> items;
  final VoidCallback? onOpenPurchaseList;
  final Future<void> Function()? onSyncToFinance;

  const PurchasesScreen({
    Key? key,
    required this.purchases,
    this.items = const [],
    this.onOpenPurchaseList,
    this.onSyncToFinance,
  }) : super(key: key);

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final TextEditingController _search = TextEditingController();
  String? _supplierFilter;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _money(double amount) =>
      NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);

  double _total(PurchaseReceipt p) =>
      p.items.fold<double>(0, (s, i) => s + (i.qtyBase * i.unitCostPerBase));

  String _itemName(String itemId) {
    for (final i in widget.items) {
      if (i.id == itemId) return i.name;
    }
    return itemId;
  }

  String _qty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  List<PurchaseReceipt> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final list = widget.purchases.where((p) {
      if (_supplierFilter != null &&
          (p.supplierName ?? '').trim() != _supplierFilter) {
        return false;
      }
      if (_dateRange != null) {
        final d = DateTime(
            p.receivedAt.year, p.receivedAt.month, p.receivedAt.day);
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month,
            _dateRange!.start.day);
        final end = DateTime(
            _dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      if (q.isNotEmpty) {
        if (!p.receiptNumber.toLowerCase().contains(q) &&
            !(p.supplierName ?? '').toLowerCase().contains(q) &&
            !(p.notes ?? '').toLowerCase().contains(q) &&
            !p.items.any(
                (i) => _itemName(i.itemId).toLowerCase().contains(q))) {
          return false;
        }
      }
      return true;
    }).toList();

    list.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listNotifier = widget.onOpenPurchaseList == null
        ? null
        : context.watch<PurchaseListNotifier>();
    final filtered = _filtered;

    final totalSpend = filtered.fold<double>(0, (s, p) => s + _total(p));
    final totalLines =
        filtered.fold<int>(0, (s, p) => s + p.items.length);
    final now = DateTime.now();
    final monthSpend = filtered
        .where((p) =>
            p.receivedAt.year == now.year && p.receivedAt.month == now.month)
        .fold<double>(0, (s, p) => s + _total(p));

    final suppliers = <String>{
      for (final p in widget.purchases)
        if ((p.supplierName ?? '').trim().isNotEmpty) p.supplierName!.trim(),
    }.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases (GRN)'),
        actions: [
          if (widget.onSyncToFinance != null)
            IconButton(
              icon: const Icon(Icons.sync_alt),
              tooltip: 'Sync purchases to Finance',
              onPressed: () => widget.onSyncToFinance!(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: KpiCard(
                        title: 'Receipts',
                        value: '${filtered.length}',
                        icon: Icons.receipt_long_outlined,
                        color: theme.colorScheme.primary,
                        description: 'Purchase receipt records in the current filter.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: KpiCard(
                        title: 'Total Spend',
                        value: _money(totalSpend),
                        icon: Icons.payments_outlined,
                        color: const Color(0xFF7C3AED),
                        description: 'Total amount from purchase receipts in the current filter.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: KpiCard(
                        title: 'This Month',
                        value: _money(monthSpend),
                        icon: Icons.calendar_month_outlined,
                        color: const Color(0xFF16A34A),
                        description: 'Purchase spend for the current month (based on receipt dates).',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: KpiCard(
                        title: 'Line Items',
                        value: '$totalLines',
                        icon: Icons.list_alt_outlined,
                        color: const Color(0xFF2563EB),
                        description: 'Total purchased line items across filtered receipts.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search by receipt, supplier, item...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dateRangeChip(context),
                    if (suppliers.isNotEmpty) _supplierDropdown(suppliers),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const ListTile(
                    leading: Icon(Icons.account_balance_wallet_outlined),
                    title: Text('Purchases post to Expenses automatically'),
                    subtitle: Text(
                      'Recording a purchase (or completing the purchase list) creates a matching expense in Finance, linked to this receipt.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.onOpenPurchaseList != null)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: ListTile(
                      onTap: widget.onOpenPurchaseList,
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: const Icon(Icons.shopping_basket_outlined,
                            color: Colors.brown),
                      ),
                      title: const Text('Purchase List'),
                      subtitle: listNotifier == null
                          ? const Text('Review & record planned purchases')
                          : listNotifier.list.isEmpty
                              ? const Text('No pending items — tap to create')
                              : Text(
                                  '${listNotifier.pendingCount} pending • ${_money(listNotifier.pendingCost)}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    ),
                  ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'No purchases yet',
                      subtitle:
                          'Purchase receipts (GRN) appear here when you record stock purchases.',
                    ),
                  )
                else
                  ...filtered.map((p) => _ReceiptCard(
                        receipt: p,
                        total: _total(p),
                        money: _money,
                        qty: _qty,
                        itemName: _itemName,
                        dateLabel: DateFormat('MMM d, yyyy • h:mm a')
                            .format(p.receivedAt),
                      )),
              ],
            ),
          ),
        ],
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

  Widget _supplierDropdown(List<String> suppliers) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String?>(
        initialValue: _supplierFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.local_shipping_outlined),
          border: OutlineInputBorder(),
        ),
        hint: const Text('All suppliers'),
        items: [
          const DropdownMenuItem(value: null, child: Text('All suppliers')),
          ...suppliers.map(
            (s) => DropdownMenuItem(value: s, child: Text(s)),
          ),
        ],
        onChanged: (v) => setState(() => _supplierFilter = v),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.receipt,
    required this.total,
    required this.money,
    required this.qty,
    required this.itemName,
    required this.dateLabel,
  });

  final PurchaseReceipt receipt;
  final double total;
  final String Function(double) money;
  final String Function(double) qty;
  final String Function(String) itemName;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.receipt_long_outlined,
              size: 20, color: scheme.primary),
        ),
        title: Text(
          receipt.receiptNumber.isEmpty ? 'Receipt' : receipt.receiptNumber,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(dateLabel, style: const TextStyle(fontSize: 12)),
            if ((receipt.supplierName ?? '').trim().isNotEmpty)
              Text(
                'Supplier: ${receipt.supplierName}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              money(total),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 3),
            _statusChip(receipt.status),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceVariant.withValues(alpha: 0.35),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (receipt.items.isEmpty)
                  const Text('No items recorded')
                else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text('Item',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('Qty',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Amount',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...receipt.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                itemName(item.itemId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${qty(item.qtyBase)} ${item.purchaseUnit ?? ''}'
                                    .trim(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                money(item.qtyBase * item.unitCostPerBase),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Total',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        money(total),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                ],
                if ((receipt.receivedBy ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Received by: ${receipt.receivedBy}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
                if ((receipt.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Notes: ${receipt.notes}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.toUpperCase();
    final color = s == 'RECEIVED' || s == 'COMPLETED'
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
