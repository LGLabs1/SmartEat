import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../models/inventory_item.dart';
import '../../../../../services/api_service.dart';
import '../../../../../services/receipt_printer_service.dart';
import '../../../../../theme.dart';
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

  Future<void> _printReport() async {
    final items = widget.items;
    final movements = widget.movements;
    final health = InventoryHealthScoreUseCase()
        .compute(items: items, movements: movements);
    final lowStock = LowStockReportUseCase().compute(items);
    final value = InventoryValueUseCase().computeTotalValue(items, null);
    final cogs = CogsUseCase().compute(movements);
    final restock = RestockSuggestionsUseCase().compute(items);

    double wasteQty = 0;
    double wasteCost = 0;
    double consumptionQty = 0;
    double consumptionCost = 0;
    for (final movement in movements) {
      final qty = movement.changeBase.abs();
      final cost = movement.totalCostImpact.abs();
      if (movement.type == StockMovementType.saleConsumption) {
        consumptionQty += qty;
        consumptionCost += cost;
      } else if (movement.type == StockMovementType.damaged ||
          movement.type == StockMovementType.writeOff) {
        wasteQty += qty;
        wasteCost += cost;
      }
    }

    final lines = <String>[
      'Generated: ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
      '${ReceiptPrinterService.documentSection}KEY METRICS',
      'Health score: ${health.score.toStringAsFixed(0)}/100 (${health.band})',
      'Inventory value: ${_formatCurrency(value)}',
      'Actual COGS: ${_formatCurrency(cogs)}',
      'Consumption: ${_qty(consumptionQty)} / ${_formatCurrency(consumptionCost)}',
      'Waste: ${_qty(wasteQty)} / ${_formatCurrency(wasteCost)}',
      ReceiptPrinterService.documentDivider,
      '${ReceiptPrinterService.documentSection}LOW STOCK (${lowStock.length})',
      if (lowStock.isEmpty)
        'None'
      else
        ...lowStock.take(8).map(
              (entry) =>
                  '${entry.isOutOfStock ? "OUT" : "LOW"} ${entry.item.name}: '
                  '${_qty(entry.item.currentStock, entry.item.effectiveBaseUnit)} '
                  '(min ${_qty(entry.item.minStock, entry.item.effectiveBaseUnit)})',
            ),
      ReceiptPrinterService.documentDivider,
      '${ReceiptPrinterService.documentSection}RESTOCK (${restock.length})',
      if (restock.isEmpty)
        'None'
      else
        ...restock.take(8).map(
              (entry) =>
                  '${entry.item.name}: +${_qty(entry.suggestedQtyBase, entry.item.effectiveBaseUnit)}',
            ),
    ];

    final ingredients = (_usage['ingredients'] as List?) ?? const [];
    if (ingredients.isNotEmpty) {
      lines
        ..add(ReceiptPrinterService.documentDivider)
        ..add(
            '${ReceiptPrinterService.documentSection}TOP INGREDIENT USAGE (30D)');
      for (final raw in ingredients.take(6)) {
        if (raw is! Map) continue;
        final name = (raw['name'] ?? '').toString();
        final qty =
            _qty(raw['usedQty'] as num?, (raw['unit'] ?? '').toString());
        final cost = (raw['estimatedCost'] as num?)?.toDouble() ?? 0;
        lines.add('$name: $qty / ${_formatCurrency(cost)}');
      }
    }

    final result = await ReceiptPrinterService.printDocument(
      title: 'Inventory Report',
      subtitle: 'Stock health, value, and consumption summary',
      lines: lines,
      footer: 'SmartEat Inventory Reports',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.printed
              ? 'Inventory report sent to printer.'
              : result.error ?? 'Could not print inventory report.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final movements = widget.movements;
    final health = InventoryHealthScoreUseCase()
        .compute(items: items, movements: movements);
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
      } else if (m.type == StockMovementType.damaged ||
          m.type == StockMovementType.writeOff) {
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
      appBar: AppBar(
        title: const Text('Inventory Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print report',
            onPressed: _printReport,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          sectionHeader('Key Metrics & Health', AppTheme.sageAccent),
          HealthScoreCard(result: health),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.sageSuccess.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppTheme.sageSuccess),
              ),
              title: const Text('Inventory Value'),
              subtitle: const Text('Total value of current stock'),
              trailing: Text(
                _formatCurrency(value),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.sageSuccess),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.trending_down,
                    color: Colors.deepPurpleAccent),
              ),
              title: const Text('Actual COGS (sale consumption)'),
              subtitle: Text(hasSaleConsumption
                  ? 'From sale-consumption stock movements (separate from recipe-costing estimates).'
                  : 'No sale-consumption movements found; Actual COGS unavailable in this view.'),
              trailing: Text(
                _formatCurrency(cogs),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurpleAccent),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep_outlined,
                    color: AppTheme.error),
              ),
              title: const Text('Inventory Waste'),
              subtitle: Text(
                  'Damaged/write-off from movements · Qty ${_qty(wasteQty)}'),
              trailing: Text(
                _formatCurrency(wasteCost),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.error),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.sageAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.point_of_sale, color: AppTheme.sageAccent),
              ),
              title: const Text('Inventory Consumption'),
              subtitle: Text(hasSaleConsumption
                  ? 'Sale-consumption qty ${_qty(consumptionQty)}'
                  : 'No sale-consumption movements recorded.'),
              trailing: Text(
                _formatCurrency(consumptionCost),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.sageAccent),
              ),
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader('Stock Status Reports', AppTheme.warning),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Low Stock Report',
                      style: Theme.of(context).textTheme.titleMedium),
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.warning),
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
                  Text('Expiring Soon Report',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Not configured',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
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
                  Text('Restock Suggestions (Reorder Target - Current)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Recommended reorder quantities based on max stock, reorder point, or minimum stock levels.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (restock.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.warning),
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
          sectionHeader(
              'Consumption & Usage (Recipe / Menu)', AppTheme.sageCyan),
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
                            final used =
                                (ing['usedQty'] as num?)?.toDouble() ?? 0;
                            final cost =
                                (ing['estimatedCost'] as num?)?.toDouble() ?? 0;
                            final usedBy =
                                (ing['menuItems'] as List?) ?? const [];
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
                                              color: AppTheme.sageCyan)),
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
          sectionHeader('Movement & Adjustment History', AppTheme.sageAccent),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.sageAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history, color: AppTheme.sageAccent),
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
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune, color: AppTheme.warning),
              ),
              title: const Text('Stock Adjustments'),
              subtitle:
                  const Text('Corrections, write-offs, and count adjustments'),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}
