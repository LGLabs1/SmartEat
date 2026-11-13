import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../models/inventory_item.dart';
import '../../data/models/stock_adjustment.dart';

class AdjustmentsScreen extends StatelessWidget {
  final List<StockAdjustment> adjustments;
  final List<InventoryItem> items;

  const AdjustmentsScreen({
    Key? key,
    required this.adjustments,
    this.items = const [],
  }) : super(key: key);

  String _getItemName(String itemId) {
    try {
      final item = items.firstWhere((i) => i.id == itemId);
      return item.name;
    } catch (_) {
      return itemId.isEmpty ? 'Item' : itemId;
    }
  }

  String _formatDelta(double delta) {
    return delta >= 0 ? '+' : '';
  }

  Color _getDeltaColor(double delta, BuildContext context) {
    if (delta >= 0) {
      return Colors.green.shade700;
    }
    return Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Adjustments')),
      body: adjustments.isEmpty
          ? _buildEmptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: adjustments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final a = adjustments[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getDeltaColor(a.deltaBase, context).withValues(alpha: 0.1),
                      child: Icon(
                        a.deltaBase >= 0 ? Icons.add : Icons.remove,
                        color: _getDeltaColor(a.deltaBase, context),
                      ),
                    ),
                    title: Text(_getItemName(a.itemId)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adj: '),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM d, yyyy • h:mm a').format(a.performedAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (a.reasonCode.isNotEmpty)
                          Text('Reason: ', maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (a.notes != null && a.notes!.isNotEmpty)
                          Text(a.notes!, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                    trailing: Text(
                      _formatDelta(a.deltaBase),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getDeltaColor(a.deltaBase, context),
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
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
              Icons.tune,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Adjustments Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Stock adjustments (corrections, write-offs, count corrections) will appear here when recorded.',
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
