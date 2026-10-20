import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../../models/inventory_item.dart';
import '../../data/models/purchase_receipt.dart';
import '../providers/purchase_list_notifier.dart';

class PurchasesScreen extends StatelessWidget {
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

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);
  }

  double _calculateTotal(PurchaseReceipt p) {
    return p.items.fold<double>(0, (sum, item) {
      return sum + (item.qtyBase * item.unitCostPerBase);
    });
  }

  String _getItemName(String itemId) {
    for (final i in items) {
      if (i.id == itemId) return i.name;
    }
    return itemId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listNotifier = onOpenPurchaseList == null
        ? null
        : context.watch<PurchaseListNotifier>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases (GRN)'),
        actions: [
          if (onSyncToFinance != null)
            IconButton(
              icon: const Icon(Icons.sync_alt),
              tooltip: 'Sync purchases to Finance',
              onPressed: () => onSyncToFinance!(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            child: const ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined),
              title: Text('Purchases post to Expenses automatically'),
              subtitle: Text(
                'Recording a purchase (or completing the purchase list) creates a matching expense in Finance, linked to this receipt.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (onOpenPurchaseList != null)
            Card(
              child: ListTile(
                onTap: onOpenPurchaseList,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.shopping_basket_outlined, color: Colors.brown),
                ),
                title: const Text('Purchase List'),
                subtitle: listNotifier == null
                    ? const Text('Review & record planned purchases')
                    : listNotifier.list.isEmpty
                        ? const Text('No pending items — tap to create')
                        : Text(
                            '${listNotifier.pendingCount} pending • ${_formatCurrency(listNotifier.pendingCost)}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              ),
            ),
          if (onOpenPurchaseList != null) const SizedBox(height: 16),
          if (purchases.isEmpty)
            _buildEmptyState(context)
          else
            ...purchases.reversed.map((p) {
              final total = _calculateTotal(p);
              return Card(
                child: ExpansionTile(
                  title: Text(p.receiptNumber),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('MMM d, yyyy • h:mm a').format(p.receivedAt),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (p.supplierName != null && p.supplierName!.isNotEmpty)
                        Text('Supplier: ${p.supplierName}'),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        label: Text(p.status.toUpperCase()),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (p.items.isEmpty)
                            const Text('No items recorded')
                          else
                            ...p.items.map((item) => ListTile(
                                  dense: true,
                                  title: Text(_getItemName(item.itemId)),
                                  subtitle: Text(
                                    '${item.qtyBase % 1 == 0 ? item.qtyBase.toInt() : item.qtyBase.toString()} ${item.purchaseUnit ?? ''}'.trim(),
                                  ),
                                  trailing: Text(_formatCurrency(
                                      item.qtyBase * item.unitCostPerBase)),
                                )),
                          if (p.notes != null && p.notes!.isNotEmpty) ...[
                            const Divider(),
                            Text('Notes: ${p.notes}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Purchases Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Purchase receipts (GRN) will appear here when you record stock purchases.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
