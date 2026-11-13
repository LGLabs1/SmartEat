import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../models/inventory_item.dart';
import '../../../../../services/api_service.dart';
import '../../data/models/stock_movement.dart';
import '../../domain/usecases/cogs.dart';
import '../../domain/usecases/health_score.dart';
import '../../domain/usecases/inventory_value.dart';
import '../../domain/usecases/reports.dart';
import '../widgets/health_score_card.dart';

class ReportsScreen extends StatefulWidget {
  final List<InventoryItem> items;
  final List<StockMovement> movements;

  const ReportsScreen({Key? key, required this.items, required this.movements})
      : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loadingUsage = true;
  Map<String, dynamic> _usage = const {};

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final res = await ApiService.getIngredientUsageByMenuItem(days: 30);
      if (!mounted) return;
      setState(() {
        _usage = res['data'] as Map<String, dynamic>? ?? const {};
        _loadingUsage = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingUsage = false);
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);
  }

  String _qty(num? v, [String unit = '']) {
    final d = (v ?? 0).toDouble();
    final s = d % 1 == 0 ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
    return unit.trim().isEmpty ? s : '$s $unit';
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final movements = widget.movements;
    final health = InventoryHealthScoreUseCase().compute(items: items, movements: movements);
    final lowStock = LowStockReportUseCase().compute(items);
    final value = InventoryValueUseCase().computeTotalValue(items, null);
    final cogs = CogsUseCase().compute(movements);
    final restock = RestockSuggestionsUseCase().compute(items);
    double wasteCost = 0, wasteQty = 0, consumptionQty = 0, consumptionCost = 0;
    var hasSaleConsumption = false;
    for (final m in movements) {
      final qty = m.changeBase.abs();
      final cost = m.totalCostImpact.abs();
      if (m.type == StockMovementType.saleConsumption) {
        hasSaleConsumption = true;
        consumptionQty += qty;
        consumptionCost += cost;
      } else if (m.type == StockMovementType.damaged || m.type == StockMovementType.writeOff) {
        wasteQty += qty;
        wasteCost += cost;
      }
    }

    Widget sectionHeader(String title, Color color) {
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          sectionHeader('Key Metrics & Health', Colors.blue),
          HealthScoreCard(result: health),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.green),
              ),
              title: const Text('Inventory Value'),
              subtitle: const Text('Total value of current stock'),
              trailing: Text(
                _formatCurrency(value),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.trending_down, color: Colors.deepPurple),
              ),
              title: const Text('Actual COGS (sale consumption)'),
              subtitle: Text(hasSaleConsumption
                  ? 'From sale-consumption stock movements (separate from recipe-costing estimates).'
                  : 'No sale-consumption movements found; Actual COGS unavailable in this view.'),
              trailing: Text(
                _formatCurrency(cogs),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              ),
              title: const Text('Inventory Waste'),
              subtitle: Text('Damaged/write-off from movements · Qty ${_qty(wasteQty)}'),
              trailing: Text(
                _formatCurrency(wasteCost),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.point_of_sale, color: Colors.indigo),
              ),
              title: const Text('Inventory Consumption'),
              subtitle: Text(hasSaleConsumption
                  ? 'Sale-consumption qty ${_qty(consumptionQty)}'
                  : 'No sale-consumption movements recorded.'),
              trailing: Text(
                _formatCurrency(consumptionCost),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader('Stock Status Reports', Colors.orange),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Low Stock Report', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Items below reorder/minimum stock levels.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (lowStock.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('No low stock items'),
                      ),
                    )
                  else
                    ...lowStock.take(10).map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(e.item.name)),
                                Text(
                                  '${e.item.currentStock.toStringAsFixed(2)} / ${e.item.minStock.toStringAsFixed(2)} ${e.item.unit}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expiring Soon Report', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Not configured',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Restock Suggestions (Max - Current)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Recommended reorder quantities based on max stock levels.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (restock.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('No restock suggestions'),
                      ),
                    )
                  else
                    ...restock.take(10).map(
                          (s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(s.item.name)),
                                Text(
                                  '${s.suggestedQtyBase.toStringAsFixed(2)} ${s.item.unit}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader('Consumption & Usage (Recipe / Menu)', Colors.teal),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Ingredient usage per menu item',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (_loadingUsage)
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estimated from completed orders × linked recipes (last 30 days). Separate from Actual COGS/movement-based stock history.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final ingredients = List<Map<String, dynamic>>.from(
                        _usage['ingredients'] ?? const []);
                    final menuItems = List<Map<String, dynamic>>.from(
                        _usage['menuItems'] ?? const []);
                    if (!_loadingUsage &&
                        ingredients.isEmpty &&
                        menuItems.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No recipe-linked menu usage found. Link recipes to menu items and complete orders to populate this.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ingredients.isNotEmpty) ...[
                          Text('Top ingredients',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ...ingredients.take(10).map((ing) {
                            final name = (ing['name'] ?? '').toString();
                            final unit = (ing['unit'] ?? '').toString();
                            final used = (ing['usedQty'] as num?)?.toDouble() ?? 0;
                            final cost =
                                (ing['estimatedCost'] as num?)?.toDouble() ?? 0;
                            final usedBy = (ing['menuItems'] as List?) ?? const [];
                            final byText = usedBy
                                .take(2)
                                .map((m) => (m['name'] ?? '').toString())
                                .where((s) => s.isNotEmpty)
                                .join(', ');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        if (byText.isNotEmpty)
                                          Text('Used by: $byText',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_qty(used, unit),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.teal)),
                                      Text(_formatCurrency(cost),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        if (menuItems.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text('By menu item',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          ...menuItems.take(10).map((m) {
                            final name = (m['menuItemName'] ?? '').toString();
                            final sold =
                                (m['quantitySold'] as num?)?.toDouble() ?? 0;
                            final cost = (m['estimatedIngredientCost'] as num?)
                                    ?.toDouble() ??
                                0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(child: Text(name)),
                                  Text('${_qty(sold)} sold',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                  const SizedBox(width: 10),
                                  Text(_formatCurrency(cost),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader('Movement & Adjustment History', Colors.indigo),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history, color: Colors.blue),
              ),
              title: const Text('Inventory Movement History'),
              subtitle: const Text('All stock movements in one place'),
              onTap: () {},
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.brown.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune, color: Colors.brown),
              ),
              title: const Text('Stock Adjustments'),
              subtitle: const Text('Corrections, write-offs, and count adjustments'),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}
