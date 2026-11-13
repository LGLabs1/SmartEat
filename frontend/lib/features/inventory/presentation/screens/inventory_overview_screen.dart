import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../models/inventory_item.dart';
import '../../data/models/stock_movement.dart';
import '../../domain/usecases/health_score.dart';
import '../../domain/usecases/inventory_value.dart';
import '../../domain/usecases/reports.dart';
import '../widgets/health_score_card.dart';

class InventoryOverviewScreen extends StatelessWidget {
  final List<InventoryItem> items;
  final List<StockMovement> movements;
  final VoidCallback onViewReports;
  final VoidCallback onViewLowStock;
  final VoidCallback onViewMovements;

  const InventoryOverviewScreen({
    Key? key,
    required this.items,
    required this.movements,
    required this.onViewReports,
    required this.onViewLowStock,
    required this.onViewMovements,
  }) : super(key: key);

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final health = InventoryHealthScoreUseCase()
        .compute(items: items, movements: movements);
    final value = InventoryValueUseCase().computeTotalValue(items, null);
    final lowStock = LowStockReportUseCase().compute(items);
    final restock = RestockSuggestionsUseCase().compute(items);

    final activeItems = items.where((i) => i.isActive).toList();
    final outOfStock = lowStock.where((e) => e.isOutOfStock).length;
    final recent = movements.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    double wasteCost = 0, consumptionCost = 0;
    var hasSaleConsumption = false;
    for (final m in movements) {
      final cost = m.totalCostImpact.abs();
      if (m.type == StockMovementType.saleConsumption) {
        hasSaleConsumption = true;
        consumptionCost += cost;
      } else if (m.type == StockMovementType.damaged || m.type == StockMovementType.writeOff) {
        wasteCost += cost;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Overview'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart),
            onPressed: onViewReports,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HealthScoreCard(result: health),
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _StatChip(
                  label: 'Value',
                  value: _formatCurrency(value),
                  description: 'Estimated current inventory value based on on-hand quantity and unit cost.',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.green,
                  onTap: onViewReports,
                ),
                _StatChip(
                  label: 'Items',
                  value: '${activeItems.length}',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.blue,
                  onTap: onViewLowStock,
                ),
                _StatChip(
                  label: 'Low stock',
                  value: '${lowStock.length}',
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  onTap: onViewLowStock,
                ),
                _StatChip(
                  label: 'Out of stock',
                  value: '$outOfStock',
                  icon: Icons.remove_shopping_cart_outlined,
                  color: Colors.red,
                  onTap: onViewLowStock,
                ),
                _StatChip(
                  label: 'Waste',
                  value: _formatCurrency(wasteCost),
                  icon: Icons.delete_sweep_outlined,
                  color: Colors.redAccent,
                  onTap: onViewReports,
                  description: 'Inventory waste cost from damaged/write-off records.' ,
                ),
                _StatChip(
                  label: hasSaleConsumption ? 'Consumption' : 'Consumption (N/A)',
                  value: _formatCurrency(consumptionCost),
                  icon: Icons.point_of_sale,
                  color: Colors.indigo,
                  onTap: onViewReports,
                  description: 'Inventory consumption cost from sale-consumption stock movements. N/A when not recorded.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Recent Activity', Colors.indigo, onViewMovements),
          Card(
            child: recent.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No recent movements')),
                  )
                : Column(
                    children: recent
                        .take(5)
                        .map((m) => _MovementTile(movement: m, items: items))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Restock Suggestions', Colors.brown, onViewReports),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommended reorder quantities based on max stock levels.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (restock.isEmpty)
                    Text(
                      'No restock suggestions',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...restock.take(5).map(
                          (s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(s.item.name)),
                                Text(
                                  '${s.suggestedQtyBase.toStringAsFixed(2)} ${s.item.unit}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    Color color,
    VoidCallback onView,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ),
          TextButton(onPressed: onView, child: const Text('View all')),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? description;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    Widget withTip(Widget child) => description == null ? child : Tooltip(message: description!, preferBelow: false, waitDuration: const Duration(milliseconds: 300), child: child);
    return withTip(Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  final List<InventoryItem> items;

  const _MovementTile({required this.movement, required this.items});

  String _itemName() {
    for (final i in items) {
      if (i.id == movement.itemId) return i.name;
    }
    return movement.itemId;
  }

  (String, IconData, Color) _typeInfo() {
    switch (movement.type) {
      case StockMovementType.purchase:
        return ('Purchase', Icons.add_circle_outline, Colors.green);
      case StockMovementType.adjustIncrease:
        return ('Adjust (+)', Icons.arrow_upward, Colors.teal);
      case StockMovementType.adjustDecrease:
        return ('Adjust (-)', Icons.arrow_downward, Colors.deepOrange);
      case StockMovementType.saleConsumption:
        return ('Consumption', Icons.point_of_sale, Colors.indigo);
      case StockMovementType.writeOff:
        return ('Write-off', Icons.delete_outline, Colors.red);
      case StockMovementType.damaged:
        return ('Damaged', Icons.broken_image_outlined, Colors.red);
      case StockMovementType.countCorrection:
        return ('Count Correction', Icons.fact_check_outlined, Colors.blueGrey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _typeInfo();
    final sign = movement.changeBase >= 0 ? '+' : '';
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(_itemName()),
      subtitle: Text(
        '$label • ${DateFormat('MMM d, h:mm a').format(movement.timestamp.toLocal())}',
      ),
      trailing: Text(
        '$sign${movement.changeBase.toStringAsFixed(2)}',
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
