import 'package:flutter/material.dart';
import '../../../../../models/inventory_item.dart';
import '../widgets/inventory_table.dart';
import '../widgets/purchase_dialog.dart';
import '../widgets/category_cards.dart';
import '../widgets/add_item_dialog.dart';
import '../../data/models/purchase_receipt.dart';
import '../../data/models/stock_adjustment.dart';

class ItemsListScreen extends StatefulWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onItemTap;
  final ValueChanged<PurchaseReceipt>? onPurchase;
  final ValueChanged<StockAdjustment>? onAdjustment;
  final ValueChanged<InventoryItem>? onAddItem;

  const ItemsListScreen({
    Key? key,
    required this.items,
    required this.onItemTap,
    this.onPurchase,
    this.onAdjustment,
    this.onAddItem,
  }) : super(key: key);

  @override
  State<ItemsListScreen> createState() => _ItemsListScreenState();
}

class _ItemsListScreenState extends State<ItemsListScreen> {
  bool _showGrid = true;
  String _selectedCategory = 'All';
  String? _selectedStockStatus;

  List<String> _getCategories() {
    final defaultCats = ['Vegetables', 'Meat', 'Dairy', 'Grains', 'Spices', 'Beverages'];
    return defaultCats;
  }

  List<InventoryItem> _filtered() {
    if (_selectedStockStatus == 'low') {
      return widget.items.where((i) => i.isLowStock && i.currentStock > 0).toList();
    } else if (_selectedStockStatus == 'out') {
      return widget.items.where((i) => i.currentStock <= 0).toList();
    } else if (_selectedCategory == 'All') {
      return widget.items;
    }
    return widget.items.where((i) => i.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _getCategories();
    final filtered = _filtered();
    return Scaffold(
      appBar: AppBar(
        title: Text(_showGrid ? 'Inventory' : 'Inventory (List)'),
        actions: [
          IconButton(
            icon: Icon(_showGrid ? Icons.view_list : Icons.grid_view),
            tooltip: _showGrid ? 'Switch to List View' : 'Switch to Grid View',
            onPressed: () => setState(() => _showGrid = !_showGrid),
          ),
          if (widget.onPurchase != null)
            IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: 'New Purchase',
              onPressed: () async {
                final r = await showDialog<PurchaseReceipt>(
                  context: context,
                  builder: (c) => const PurchaseDialog(),
                );
                if (r != null) widget.onPurchase!(r);
              },
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Item',
            onPressed: () async {
              final result = await showDialog<InventoryItem>(
                context: context,
                builder: (_) => AddItemDialog(
                  initialCategory: _selectedCategory != 'All' ? _selectedCategory : null,
                ),
              );
              if (result != null && widget.onAddItem != null) {
                widget.onAddItem!(result);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _showGrid
            ? _buildGrid(context, categories)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to Categories'),
                          onPressed: () {
                            setState(() {
                              _showGrid = true;
                              _selectedCategory = 'All';
                              _selectedStockStatus = null;
                            });
                          },
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Expanded(child: InventoryTable(items: filtered, onRowTap: widget.onItemTap)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog<InventoryItem>(
            context: context,
            builder: (_) => AddItemDialog(
              initialCategory: _selectedCategory != 'All' ? _selectedCategory : null,
            ),
          );
          if (result != null && widget.onAddItem != null) {
            widget.onAddItem!(result);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<String> categories) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100
            ? 4
            : width >= 800
                ? 3
                : width >= 520
                    ? 2
                    : 1;
        final cats = categories.toList();
        final lowStockItems = widget.items.where((i) => i.isLowStock && i.currentStock > 0).toList();
        final outOfStockItems = widget.items.where((i) => i.currentStock <= 0).toList();
        final damagedCount = 0;
        return ListView(
          children: [
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: crossAxisCount == 1 ? 3.4 : 1.6,
              ),
              children: [
                StockStatusCard(
                  title: 'All Inventory',
                  itemCount: widget.items.length,
                  icon: Icons.inventory_2_outlined,
                  accent: Theme.of(context).colorScheme.primary,
                  onTap: () {
                    setState(() {
                      _selectedStockStatus = 'all';
                      _selectedCategory = 'All';
                      _showGrid = false;
                    });
                  },
                ),
                StockStatusCard(
                  title: 'Low Stock',
                  itemCount: lowStockItems.length,
                  icon: Icons.warning_amber_rounded,
                  accent: Theme.of(context).colorScheme.secondary,
                  onTap: () {
                    setState(() {
                      _selectedStockStatus = 'low';
                      _selectedCategory = 'All';
                      _showGrid = false;
                    });
                  },
                ),
                StockStatusCard(
                  title: 'Out of Stock',
                  itemCount: outOfStockItems.length,
                  icon: Icons.error_outline,
                  accent: Theme.of(context).colorScheme.error,
                  onTap: () {
                    setState(() {
                      _selectedStockStatus = 'out';
                      _selectedCategory = 'All';
                      _showGrid = false;
                    });
                  },
                ),
                StockStatusCard(
                  title: 'Damaged Items',
                  itemCount: damagedCount,
                  icon: Icons.report_problem_outlined,
                  accent: Colors.deepOrange.shade700,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: crossAxisCount == 1 ? 3.4 : 1.6,
              ),
              itemCount: cats.length,
              itemBuilder: (context, index) {
                final category = cats[index];
                final itemsInCategory =
                    widget.items.where((i) => i.category == category).toList();
                final lowStockCount = itemsInCategory.where((i) => i.isLowStock).length;
                return CategoryCard(
                  category: category,
                  itemCount: itemsInCategory.length,
                  lowStockCount: lowStockCount,
                  onTap: () {
                    setState(() {
                      _selectedStockStatus = null;
                      _selectedCategory = category;
                      _showGrid = false;
                    });
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}
