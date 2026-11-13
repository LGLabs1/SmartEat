import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../models/inventory_item.dart';
import '../../../../../services/api_service.dart';

class ItemDetailScreen extends StatefulWidget {
  final InventoryItem item;

  const ItemDetailScreen({Key? key, required this.item}) : super(key: key);

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _loadingUsage = true;
  Map<String, dynamic>? _ingredientUsage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final res = await ApiService.getIngredientUsageByMenuItem(days: 30);
      final data = res['data'] as Map<String, dynamic>? ?? const {};
      final ingredients = List<Map<String, dynamic>>.from(
          data['ingredients'] ?? const []);
      final match = ingredients.cast<Map<String, dynamic>?>().firstWhere(
            (i) =>
                (i?['inventoryItemId'] ?? '').toString() == widget.item.id ||
                (i?['name'] ?? '').toString().trim().toLowerCase() ==
                    widget.item.name.trim().toLowerCase(),
            orElse: () => null,
          );
      if (!mounted) return;
      setState(() {
        _ingredientUsage = match;
        _loadingUsage = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingUsage = false);
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final isLowStock = item.isLowStock;
    final isOutOfStock = item.currentStock <= 0;

    final statusChip = isOutOfStock
        ? Chip(
            label: const Text('Out of Stock'),
            backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
            labelStyle: TextStyle(color: theme.colorScheme.error, fontSize: 11),
            visualDensity: VisualDensity.compact,
          )
        : isLowStock
            ? Chip(
                label: const Text('Low Stock'),
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                labelStyle: const TextStyle(color: Colors.orange, fontSize: 11),
                visualDensity: VisualDensity.compact,
              )
            : Chip(
                label: const Text('In Stock'),
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                labelStyle: const TextStyle(color: Colors.green, fontSize: 11),
                visualDensity: VisualDensity.compact,
              );

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Item',
            onPressed: () {},
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.06),
                          isOutOfStock
                              ? theme.colorScheme.error.withValues(alpha: 0.08)
                              : isLowStock
                                  ? Colors.orange.withValues(alpha: 0.08)
                                  : Colors.green.withValues(alpha: 0.06),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isOutOfStock
                                    ? theme.colorScheme.error.withValues(alpha: 0.15)
                                    : isLowStock
                                        ? Colors.orange.withValues(alpha: 0.15)
                                        : theme.colorScheme.primary.withValues(alpha: 0.15),
                                child: Icon(Icons.inventory_2_outlined,
                                    color: isOutOfStock
                                        ? theme.colorScheme.error
                                        : isLowStock
                                            ? Colors.orange
                                            : theme.colorScheme.primary,
                                    size: 20),
                              ),
                              const SizedBox(width: 10),
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
                                          item.name,
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        statusChip,
                                        if (item.sku != null && item.sku!.isNotEmpty)
                                          Chip(
                                            label: Text('SKU: ${item.sku}'),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        if (item.brand != null && item.brand!.isNotEmpty)
                                          Chip(
                                            label: Text('Brand: ${item.brand}'),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.category,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (item.description != null && item.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.description!,
                                        style: theme.textTheme.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (item.maxStock > 0) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: (item.currentStock / item.maxStock).clamp(0.0, 1.0),
                                      minHeight: 8,
                                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                      color: isOutOfStock
                                          ? theme.colorScheme.error
                                          : isLowStock
                                              ? Colors.orange
                                              : Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(item.currentStock / item.maxStock * 100).clamp(0.0, 999).toStringAsFixed(0)}%',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock
                                        ? theme.colorScheme.error
                                        : isLowStock
                                            ? Colors.orange
                                            : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CompactCard(
                      title: 'Current Stock',
                      value: '${item.currentStock.toStringAsFixed(2)} ${item.effectiveBaseUnit}',
                      valueColor: isOutOfStock ? theme.colorScheme.error : isLowStock ? Colors.orange : Colors.green,
                      icon: Icons.layers_outlined,
                      width: isWide ? 160 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Min / Reorder / Max',
                      value: '${item.minStock.toStringAsFixed(2)} / ${item.reorderPoint.toStringAsFixed(2)} / ${item.maxStock.toStringAsFixed(2)}',
                      icon: Icons.trending_down_outlined,
                      valueColor: Colors.blue,
                      width: isWide ? 220 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Safety / Lead Time',
                      value: '${item.safetyStock.toStringAsFixed(2)} / ${item.leadTimeDays}d',
                      icon: Icons.security_outlined,
                      valueColor: Colors.purple,
                      width: isWide ? 160 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Consumption',
                      value: item.consumptionMode == ConsumptionMode.recipePending
                          ? 'Recipe-pending'
                          : 'Direct',
                      icon: Icons.sync_alt_outlined,
                      valueColor: item.consumptionMode == ConsumptionMode.recipePending
                          ? Colors.orange
                          : Colors.teal,
                      width: isWide ? 140 : (constraints.maxWidth - 16) / 2,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CompactCard(
                      title: 'Unit Cost',
                      value: _formatCurrency(item.unitCost),
                      icon: Icons.payments_outlined,
                      valueColor: Colors.green.shade700,
                      width: isWide ? 140 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Selling Price',
                      value: _formatCurrency(item.sellingPrice),
                      icon: Icons.sell_outlined,
                      valueColor: Colors.amber.shade800,
                      width: isWide ? 140 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Last / Avg Cost',
                      value: '${_formatCurrency(item.lastPurchaseCost)} / ${_formatCurrency(item.avgCost)}',
                      icon: Icons.calculate_outlined,
                      valueColor: Colors.indigo,
                      width: isWide ? 220 : constraints.maxWidth,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CompactCard(
                      title: 'Consumption',
                      value: item.consumptionMode == ConsumptionMode.recipePending
                          ? 'Recipe-pending'
                          : 'Direct',
                      icon: Icons.sync_alt_outlined,
                      valueColor: item.consumptionMode == ConsumptionMode.recipePending
                          ? Colors.orange
                          : Colors.teal,
                      width: isWide ? 140 : (constraints.maxWidth - 16) / 2,
                    ),
                    if (item.purchaseUnit != null && item.purchaseUnit!.isNotEmpty)
                      _CompactCard(
                        title: 'Purchase Unit',
                        value: item.purchaseUnit!,
                        icon: Icons.shopping_cart_outlined,
                        width: isWide ? 130 : (constraints.maxWidth - 16) / 2,
                      ),
                    if (item.saleUnit != null && item.saleUnit!.isNotEmpty)
                      _CompactCard(
                        title: 'Sale Unit',
                        value: item.saleUnit!,
                        icon: Icons.local_offer_outlined,
                        width: isWide ? 120 : (constraints.maxWidth - 16) / 2,
                      ),
                    _CompactCard(
                      title: 'Conv. Factor',
                      value: item.conversionFactor.toString(),
                      icon: Icons.compare_arrows_outlined,
                      width: isWide ? 120 : (constraints.maxWidth - 16) / 2,
                    ),
                    _CompactCard(
                      title: 'Supplier',
                      value: item.supplier.isNotEmpty ? item.supplier : 'N/A',
                      icon: Icons.local_shipping_outlined,
                      width: isWide ? 200 : constraints.maxWidth,
                    ),
                  ],
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.note_outlined,
                              size: 18, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Notes',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  item.notes!,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.restaurant_menu_outlined,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Recipe / Menu Usage (last 30 days)',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            if (_loadingUsage)
                              const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Estimated from completed orders + linked recipes. Separate from Actual COGS (stock movements).',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        if (_ingredientUsage == null && !_loadingUsage)
                          Text(
                            item.consumptionMode == ConsumptionMode.recipePending
                                ? 'No usage found yet. Link this item in a recipe and complete menu sales to see usage.'
                                : 'No recipe/menu usage linked to this inventory item in the last 30 days.',
                            style: theme.textTheme.bodySmall,
                          )
                        else if (_ingredientUsage != null) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _UsageChip(
                                label: 'Used qty',
                                value:
                                    '${((_ingredientUsage!['usedQty'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ${_ingredientUsage!['unit'] ?? item.effectiveBaseUnit}',
                              ),
                              _UsageChip(
                                label: 'Est. cost',
                                value: _formatCurrency(
                                    (_ingredientUsage!['estimatedCost'] as num?)
                                            ?.toDouble() ??
                                        0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Used by menu items',
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          ...(((_ingredientUsage!['menuItems'] as List?) ?? const [])
                                  .take(8))
                              .map((m) {
                            final name = (m['name'] ?? '').toString();
                            final q = (m['usedQty'] as num?)?.toDouble() ?? 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(name)),
                                  Text(
                                      '${q.toStringAsFixed(2)} ${_ingredientUsage!['unit'] ?? ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final double width;

  const _CompactCard({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = valueColor ?? theme.colorScheme.primary;
    return SizedBox(
      width: width,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: valueColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _UsageChip extends StatelessWidget {
  const _UsageChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
