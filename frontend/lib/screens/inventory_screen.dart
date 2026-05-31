import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/inventory_item.dart';
import '../services/auth_provider.dart';
import '../widgets/skeleton_loaders.dart';
import '../utils/error_messages.dart';
import 'damaged_items_screen.dart';

class InventoryScreen extends StatefulWidget {
  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onBackNeeded;
  final bool isInDetailView;
  final Function(VoidCallback resetFn)? onResetRequest;

  const InventoryScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onBackNeeded,
    this.isInDetailView = false,
    this.onResetRequest,
  }) : super(key: key);

  @override
  State<InventoryScreen> createState() => InventoryScreenState();
}

class _InventoryTable extends StatefulWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onRowTap;

  const _InventoryTable({
    Key? key,
    required this.items,
    required this.onRowTap,
  }) : super(key: key);

  @override
  State<_InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<_InventoryTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  late List<InventoryItem> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = List<InventoryItem>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant _InventoryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _sorted = List<InventoryItem>.from(widget.items);
      if (_sortColumnIndex != null) {
        _applySort(_sortColumnIndex!, _sortAscending);
      }
    }
  }

  String _lc(String s) => s.toLowerCase();

  void _applySort(int columnIndex, bool ascending) {
    int cmp(Comparable a, Comparable b) =>
        ascending ? a.compareTo(b) : b.compareTo(a);

    _sorted.sort((a, b) {
      switch (columnIndex) {
        case 0:
          return cmp(_lc(a.name), _lc(b.name));
        case 1:
          return cmp(_lc(a.category), _lc(b.category));
        case 2:
          return cmp(_lc(a.unit), _lc(b.unit));
        case 3:
          return cmp(a.unitCost, b.unitCost);
        case 4:
          return cmp(a.currentStock, b.currentStock);
        default:
          return 0;
      }
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort(columnIndex, ascending);
    });
  }

  Widget _headerLabel(BuildContext context, String text) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: Colors.grey.shade900,
            ) ??
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
          color: Colors.grey.shade900,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text.toUpperCase(), style: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = 760.0;
        final headingBg = Colors.grey.shade200;
        final dataStyle = Theme.of(context).textTheme.bodyMedium;

        final table = DataTableTheme(
          data: DataTableThemeData(
            headingRowColor: WidgetStatePropertyAll(headingBg),
            headingTextStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: Colors.grey.shade900,
                ),
            dataTextStyle: dataStyle,
            dividerThickness: 0.8,
          ),
          child: DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columnSpacing: 20,
            horizontalMargin: 14,
            headingRowHeight: 44,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            columns: [
              DataColumn(
                label: _headerLabel(context, 'Item Name'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'Group'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'UoM'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'Cost / Unit'),
                numeric: true,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'On Hand'),
                numeric: true,
                onSort: (i, asc) => _onSort(i, asc),
              ),
            ],
            rows: _sorted.map((item) {
              final isLowStock = item.isLowStock;
              final stockStyle = TextStyle(
                fontWeight: FontWeight.w700,
                color: isLowStock ? Colors.red.shade700 : Colors.green.shade700,
              );
              return DataRow(
                onSelectChanged: (_) => widget.onRowTap(item),
                cells: [
                  DataCell(Text(item.name)),
                  DataCell(Text(item.category)),
                  DataCell(Text(item.unit)),
                  DataCell(Text('₱${item.unitCost.toStringAsFixed(2)}')),
                  DataCell(
                    Text('${item.currentStock}${item.unit}', style: stockStyle),
                  ),
                ],
              );
            }).toList(),
          ),
        );

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth < minWidth
                      ? minWidth
                      : constraints.maxWidth,
                ),
                child: table,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InventoryItemDetailsCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onUpdateStock;
  final VoidCallback? onDelete;

  const _InventoryItemDetailsCard({
    Key? key,
    required this.item,
    required this.onEdit,
    required this.onUpdateStock,
    this.onDelete,
  }) : super(key: key);

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isLowStock = item.isLowStock;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.category,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onUpdateStock,
                  icon: const Icon(Icons.inventory),
                  label: const Text('Stock'),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StockInfoCard(
                    title: 'Current Stock',
                    value: '${item.currentStock}${item.unit}',
                    color: isLowStock ? Colors.red : Colors.green,
                    icon: isLowStock ? Icons.warning : Icons.check_circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StockInfoCard(
                    title: 'Unit Cost',
                    value: '₱${item.unitCost.toStringAsFixed(2)}',
                    color: Colors.blue,
                    icon: Icons.attach_money,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StockInfoCard(
                    title: 'Min Stock',
                    value: '${item.minStock}${item.unit}',
                    color: Colors.orange,
                    icon: Icons.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StockInfoCard(
                    title: 'Total Value',
                    value: '₱${item.totalValue.toStringAsFixed(2)}',
                    color: Colors.indigo,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.event_available,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last restock: ${_fmtDateTime(item.updatedAt.toLocal())}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            if (item.supplier.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.business, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Supplier: ${item.supplier}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String category;
  final int itemCount;
  final int lowStockCount;
  final VoidCallback onTap;

  const _CategoryCard({
    Key? key,
    required this.category,
    required this.itemCount,
    required this.lowStockCount,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = lowStockCount > 0;

    IconData icon;
    switch (category.toLowerCase()) {
      case 'vegetables':
        icon = Icons.eco_outlined;
        break;
      case 'meat':
        icon = Icons.set_meal_outlined;
        break;
      case 'dairy':
        icon = Icons.icecream_outlined;
        break;
      case 'grains':
        icon = Icons.rice_bowl_outlined;
        break;
      case 'spices':
        icon = Icons.spa_outlined;
        break;
      case 'beverages':
        icon = Icons.local_cafe_outlined;
        break;
      default:
        icon = Icons.inventory_2_outlined;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isWarning
                              ? Colors.orange
                              : theme.colorScheme.primary)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: isWarning
                          ? Colors.orange.shade700
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                category,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '$itemCount items',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (lowStockCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$lowStockCount low stock',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StockStatusCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _StockStatusCard({
    Key? key,
    required this.title,
    required this.itemCount,
    required this.icon,
    required this.accent,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '$itemCount items',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (itemCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Needs attention',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  'All good',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _inventoryItems = [];
  List<InventoryItem> _lowStockItems = [];
  List<InventoryItem> _outOfStockItems = [];
  int _damagedItemCount = 0;
  double _damagedTotalCost = 0.0;
  bool _isLoading = false;
  bool _isAdmin = false;
  String? _lastRoleUid;
  String _searchQuery = '';
  VoidCallback? _globalSearchListener;
  String _selectedCategory = 'All';
  String? _selectedStockStatus;
  bool _showCategoryGrid = true;
  final List<String> _defaultCategories = [
    'All',
    'Vegetables',
    'Meat',
    'Dairy',
    'Grains',
    'Spices',
    'Beverages'
  ];
  late List<String> _categories;

  @override
  void initState() {
    super.initState();
    _categories = List<String>.from(_defaultCategories);
    _loadInventory();
    final notifier = widget.globalSearchQuery;
    if (notifier != null) {
      _searchQuery = notifier.value;
      _globalSearchListener = () {
        if (!mounted) return;
        setState(() {
          _searchQuery = notifier.value;
        });
      };
      notifier.addListener(_globalSearchListener!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRole();
    });
  }

  @override
  void dispose() {
    final notifier = widget.globalSearchQuery;
    final listener = _globalSearchListener;
    if (notifier != null && listener != null) {
      notifier.removeListener(listener);
    }
    super.dispose();
  }

  bool _isAdminFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final dynamic isAdminRaw = profile['isAdmin'];
    final bool isAdminFlag = isAdminRaw == true ||
        isAdminRaw == 1 ||
        (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
    return isAdminFlag || role == 'admin';
  }

  Future<void> _loadRole() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_lastRoleUid == uid) return;
    _lastRoleUid = uid;

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _isAdmin = _isAdminFromProfile(profile);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
      });
    }
  }

  void resetToGrid() {
    setState(() {
      _showCategoryGrid = true;
      _selectedCategory = 'All';
      _selectedStockStatus = null;
    });
  }

  void _goToPreviousCategory() {
    final categories = _categories.where((c) => c != 'All').toList();
    final currentIndex = categories.indexOf(_selectedCategory);
    if (currentIndex > 0) {
      setState(() {
        _selectedCategory = categories[currentIndex - 1];
      });
    }
  }

  void _goToNextCategory() {
    final categories = _categories.where((c) => c != 'All').toList();
    final currentIndex = categories.indexOf(_selectedCategory);
    if (currentIndex < categories.length - 1) {
      setState(() {
        _selectedCategory = categories[currentIndex + 1];
      });
    }
  }

  Future<void> _confirmDeleteInventoryItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Inventory Item'),
          content: Text('Delete "${item.name}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteInventoryItem(item.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      // Optimistic update - remove from local list without full refresh
      _removeInventoryItemFromLocal(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory item deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _loadInventory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await ApiService.getInventoryItems();
      final damagedResponse = await ApiService.getDamagedItems();

      final items = (response['data'] as List?)
              ?.map((item) => InventoryItem.fromJson(item))
              .toList() ??
          [];
      final damagedItems = (damagedResponse['data'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          [];

      if (!mounted) return;
      setState(() {
        _inventoryItems = items;
        _lowStockItems = items
            .where((item) => item.isLowStock && item.currentStock > 0)
            .toList();
        _outOfStockItems = items.where((item) => item.currentStock <= 0).toList();
        _damagedItemCount = damagedItems.length;
        _damagedTotalCost = damagedItems.fold(0.0, (sum, item) {
          final total = (item['totalCost'] ?? 0).toDouble();
          return sum + total;
        });
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorMessageHelper.showSnackBar(
        context,
        e,
        operationContext: 'inventory',
        onAction: _loadInventory,
        actionLabel: 'Retry',
      );
    }
  }

  // Optimistic update helpers
  void _removeInventoryItemFromLocal(String id) {
    setState(() {
      _inventoryItems = _inventoryItems.where((i) => i.id != id).toList();
      _lowStockItems = _lowStockItems.where((i) => i.id != id).toList();
      _outOfStockItems = _outOfStockItems.where((i) => i.id != id).toList();
    });
  }

  void _addInventoryItemToLocal(InventoryItem item) {
    setState(() {
      _inventoryItems = [item, ..._inventoryItems];
      if (item.isLowStock && item.currentStock > 0) {
        _lowStockItems = [item, ..._lowStockItems];
      } else if (item.currentStock <= 0) {
        _outOfStockItems = [item, ..._outOfStockItems];
      }
    });
  }

  void _updateInventoryItemInLocal(String id, InventoryItem updatedItem) {
    setState(() {
      _inventoryItems =
          _inventoryItems.map((i) => i.id == id ? updatedItem : i).toList();
      _lowStockItems = _inventoryItems
          .where((item) => item.isLowStock && item.currentStock > 0)
          .toList();
      _outOfStockItems =
          _inventoryItems.where((item) => item.currentStock <= 0).toList();
    });
  }

  List<InventoryItem> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();

    List<InventoryItem> base;
    if (_selectedStockStatus == 'low') {
      base = _inventoryItems
          .where((item) => item.isLowStock && item.currentStock > 0)
          .toList();
    } else if (_selectedStockStatus == 'out') {
      base = _inventoryItems.where((item) => item.currentStock <= 0).toList();
    } else if (_selectedStockStatus == 'all') {
      base = _inventoryItems;
    } else if (_selectedCategory == 'All') {
      base = _inventoryItems;
    } else {
      base = _inventoryItems
          .where((item) => item.category == _selectedCategory)
          .toList();
    }

    if (q.isEmpty) return base;
    return base.where((item) => item.name.toLowerCase().contains(q)).toList();
  }

  String? _categoryHelperText(String category) {
    switch (category.trim().toLowerCase()) {
      case 'vegetables':
        return 'Examples: lettuce, tomatoes, onions, carrots, potatoes, leafy greens.';
      case 'meat':
        return 'Examples: chicken, pork, beef, fish, processed meats.';
      case 'dairy':
        return 'Examples: milk, cheese, butter, cream, yogurt.';
      case 'grains':
        return 'Examples: rice, pasta, bread, flour, oats.';
      case 'spices':
        return 'Examples: salt, pepper, garlic powder, chili, herbs, seasoning mixes.';
      case 'beverages':
        return 'Examples: coffee, tea, juices, softdrinks, water, syrups.';
      default:
        return null;
    }
  }

  Widget _buildCategoryEmptyState(BuildContext context) {
    final helper = _categoryHelperText(_selectedCategory);
    final title = _searchQuery.trim().isNotEmpty
        ? 'No items match your search'
        : 'No inventory items found';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (helper != null && helper.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  helper,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showAddItemDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(
                _showCategoryGrid
                    ? 'Inventory'
                    : _selectedStockStatus == 'all'
                        ? 'All Inventory'
                        : _selectedStockStatus == 'low'
                            ? 'Low Stock'
                            : _selectedStockStatus == 'out'
                                ? 'Out of Stock'
                                : _selectedCategory,
              ),
              centerTitle: false,
              titleSpacing: 8,
              leading: _showCategoryGrid
                  ? (widget.onOpenDrawer != null
                      ? IconButton(
                          icon: const Icon(Icons.menu),
                          tooltip: 'Menu',
                          onPressed: widget.onOpenDrawer,
                        )
                      : null)
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () {
                        setState(() {
                          _showCategoryGrid = true;
                          _selectedCategory = 'All';
                          _selectedStockStatus = null;
                        });
                        widget.onOpenDrawer?.call();
                      },
                    ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddItemDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadInventory,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const SkeletonInventory()
          : _showCategoryGrid
              ? _buildCategoryGrid(context)
              : _buildCategoryItemsList(context),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
    );
  }

  Widget _buildLowStockAlert(BuildContext context) {
    if (_lowStockItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_lowStockItems.length} items are low on stock',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
          TextButton(
            onPressed: _showLowStockDialog,
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(BuildContext context) {
    final categories = _categories.where((c) => c != 'All').toList();

    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1100
                ? 4
                : width >= 800
                    ? 3
                    : width >= 520
                        ? 2
                        : 1;

            final allInventoryCard = _StockStatusCard(
              title: 'All Inventory',
              itemCount: _inventoryItems.length,
              icon: Icons.inventory_2_outlined,
              accent: Theme.of(context).colorScheme.primary,
              onTap: () {
                setState(() {
                  _selectedStockStatus = 'all';
                  _selectedCategory = 'All';
                  _showCategoryGrid = false;
                });
                widget.onBackNeeded?.call();
              },
            );

            final lowStockCard = _StockStatusCard(
              title: 'Low Stock',
              itemCount: _lowStockItems.length,
              icon: Icons.warning_amber_rounded,
              accent: Colors.orange.shade800,
              onTap: () {
                setState(() {
                  _selectedStockStatus = 'low';
                  _selectedCategory = 'All';
                  _showCategoryGrid = false;
                });
                widget.onBackNeeded?.call();
              },
            );

            final outCard = _StockStatusCard(
              title: 'Out of Stock',
              itemCount: _outOfStockItems.length,
              icon: Icons.error_outline,
              accent: Colors.red.shade700,
              onTap: () {
                setState(() {
                  _selectedStockStatus = 'out';
                  _selectedCategory = 'All';
                  _showCategoryGrid = false;
                });
                widget.onBackNeeded?.call();
              },
            );

            final damagedCard = _StockStatusCard(
              title: 'Damaged Items',
              itemCount: _damagedItemCount,
              icon: Icons.report_problem_outlined,
              accent: Colors.deepOrange.shade700,
              onTap: _openDamagedItemsScreen,
            );

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        crossAxisCount == 1
                            ? Column(
                                children: [
                                  allInventoryCard,
                                  const SizedBox(height: 12),
                                  lowStockCard,
                                  const SizedBox(height: 12),
                                  outCard,
                                  const SizedBox(height: 12),
                                  damagedCard,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: allInventoryCard),
                                  const SizedBox(width: 12),
                                  Expanded(child: lowStockCard),
                                  const SizedBox(width: 12),
                                  Expanded(child: outCard),
                                  const SizedBox(width: 12),
                                  Expanded(child: damagedCard),
                                ],
                              ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.grey.shade300),
                      ],
                    ),
                  ),
                ),
                if (crossAxisCount == 1)
                  SliverReorderableList(
                    itemCount: categories.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final moved = categories.removeAt(oldIndex);
                        categories.insert(newIndex, moved);

                        final newOrder = <String>['All', ...categories];
                        _categories = newOrder;
                      });
                    },
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final itemsInCategory = _inventoryItems
                          .where((i) => i.category == category)
                          .toList();
                      final lowStockCount =
                          itemsInCategory.where((i) => i.isLowStock).length;

                      return Padding(
                        key: ValueKey('category_$category'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CategoryCard(
                          category: category,
                          itemCount: itemsInCategory.length,
                          lowStockCount: lowStockCount,
                          onTap: () {
                            setState(() {
                              _selectedStockStatus = null;
                              _selectedCategory = category;
                              _showCategoryGrid = false;
                            });
                            widget.onBackNeeded?.call();
                          },
                        ),
                      );
                    },
                  )
                else
                  SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final category = categories[index];
                        final itemsInCategory = _inventoryItems
                            .where((i) => i.category == category)
                            .toList();
                        final lowStockCount =
                            itemsInCategory.where((i) => i.isLowStock).length;

                        return _CategoryCard(
                          key: ValueKey('category_$category'),
                          category: category,
                          itemCount: itemsInCategory.length,
                          lowStockCount: lowStockCount,
                          onTap: () {
                            setState(() {
                              _selectedStockStatus = null;
                              _selectedCategory = category;
                              _showCategoryGrid = false;
                            });
                            widget.onBackNeeded?.call();
                          },
                        );
                      },
                      childCount: categories.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: crossAxisCount == 1 ? 3.4 : 1.6,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryItemsList(BuildContext context) {
    final categories = _categories.where((c) => c != 'All').toList();
    final currentIndex = categories.indexOf(_selectedCategory);
    final hasPrevious = currentIndex > 0;
    final hasNext = currentIndex < categories.length - 1;

    return Column(
      children: [
        // Category navigation subheader
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: hasPrevious ? _goToPreviousCategory : null,
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: hasPrevious ? Colors.blue : Colors.grey.shade300,
                ),
                tooltip: hasPrevious ? 'Previous category' : null,
              ),
              Expanded(
                child: Text(
                  _selectedCategory,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: hasNext ? _goToNextCategory : null,
                icon: Icon(
                  Icons.arrow_forward_ios,
                  color: hasNext ? Colors.blue : Colors.grey.shade300,
                ),
                tooltip: hasNext ? 'Next category' : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${_filteredItems.length} ${_filteredItems.length == 1 ? 'item' : 'items'}',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ),
        Expanded(
          child: _filteredItems.isEmpty
              ? _buildCategoryEmptyState(context)
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _InventoryTable(
                    items: _filteredItems,
                    onRowTap: (item) => _showItemDetails(item),
                  ),
                ),
        ),
      ],
    );
  }

  void _showItemDetails(InventoryItem item) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 640;

    if (isCompact) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: _InventoryItemDetailsCard(
                item: item,
                onEdit: () {
                  Navigator.of(context).pop();
                  _showEditItemDialog(item);
                },
                onUpdateStock: () {
                  Navigator.of(context).pop();
                  _showUpdateStockDialog(item);
                },
                onDelete:
                    _isAdmin ? () => _confirmDeleteInventoryItem(item) : null,
              ),
            ),
          );
        },
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _InventoryItemDetailsCard(
                item: item,
                onEdit: () {
                  Navigator.of(context).pop();
                  _showEditItemDialog(item);
                },
                onUpdateStock: () {
                  Navigator.of(context).pop();
                  _showUpdateStockDialog(item);
                },
                onDelete:
                    _isAdmin ? () => _confirmDeleteInventoryItem(item) : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddItemDialog() async {
    final result = await showDialog<InventoryItem?>(
      context: context,
      builder: (context) => _AddItemDialog(
        initialCategory: _showCategoryGrid ? null : _selectedCategory,
      ),
    );

    // Optimistic update - add to local list without full refresh
    if (result != null) {
      _addInventoryItemToLocal(result);
    }
  }

  Future<void> _showEditItemDialog(InventoryItem item) async {
    final result = await showDialog<InventoryItem?>(
      context: context,
      builder: (context) => _EditItemDialog(
        item: item,
      ),
    );

    // Optimistic update - update local list without full refresh
    if (result != null) {
      _updateInventoryItemInLocal(result.id, result);
    }
  }

  Future<void> _showUpdateStockDialog(InventoryItem item) async {
    final result = await showDialog<InventoryItem?>(
      context: context,
      builder: (context) => _UpdateStockDialog(
        item: item,
      ),
    );

    // Optimistic update - update local list without full refresh
    if (result != null) {
      _updateInventoryItemInLocal(result.id, result);
    }
  }


  void _showLowStockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Low Stock Items'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _lowStockItems.length,
            itemBuilder: (context, index) {
              final item = _lowStockItems[index];
              return ListTile(
                title: Text(item.name),
                subtitle: Text(
                  'Current: ${item.currentStock}${item.unit} | Min: ${item.minStock}${item.unit}',
                ),
                trailing: Text(
                  '${item.currentStock - item.minStock}${item.unit}',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openDamagedItemsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DamagedItemsScreen(),
      ),
    );
  }
}

class _InventoryItemCard extends StatefulWidget {
  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onUpdateStock;

  const _InventoryItemCard({
    Key? key,
    required this.item,
    required this.onEdit,
    required this.onUpdateStock,
  }) : super(key: key);

  @override
  State<_InventoryItemCard> createState() => _InventoryItemCardState();
}

class _InventoryItemCardState extends State<_InventoryItemCard> {
  bool _isExpanded = false;

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isLowStock = item.isLowStock;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.expand_more,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.category,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit Item'),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'stock',
                        child: ListTile(
                          leading: Icon(Icons.inventory),
                          title: Text('Update Stock'),
                          dense: true,
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        widget.onEdit();
                      } else if (value == 'stock') {
                        widget.onUpdateStock();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StockInfoCard(
                      title: 'Current Stock',
                      value: '${item.currentStock}${item.unit}',
                      color: isLowStock ? Colors.red : Colors.green,
                      icon: isLowStock ? Icons.warning : Icons.check_circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StockInfoCard(
                      title: 'Unit Cost',
                      value: '₱${item.unitCost.toStringAsFixed(2)}',
                      color: Colors.blue,
                      icon: Icons.attach_money,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: Colors.grey.shade200),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StockInfoCard(
                              title: 'Min Stock',
                              value: '${item.minStock}${item.unit}',
                              color: Colors.orange,
                              icon: Icons.warning,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StockInfoCard(
                              title: 'Total Value',
                              value: '₱${item.totalValue.toStringAsFixed(2)}',
                              color: Colors.indigo,
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.event_available,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Last restock: ${_fmtDateTime(item.updatedAt.toLocal())}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                      if (item.supplier.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.business,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Supplier: ${item.supplier}',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StockInfoCard({
    Key? key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _HoverableStockInfoCard(
      title: title,
      value: value,
      color: color,
      icon: icon,
    );
  }
}

class _HoverableStockInfoCard extends StatefulWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _HoverableStockInfoCard({
    Key? key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  }) : super(key: key);

  @override
  State<_HoverableStockInfoCard> createState() =>
      _HoverableStockInfoCardState();
}

class _HoverableStockInfoCardState extends State<_HoverableStockInfoCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final bg = _isHovered ? color.withOpacity(0.16) : color.withOpacity(0.10);
    final border =
        _isHovered ? color.withOpacity(0.55) : color.withOpacity(0.30);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final String? initialCategory;

  const _AddItemDialog({
    Key? key,
    this.initialCategory,
  }) : super(key: key);

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _currentStockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _unitController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _supplierController = TextEditingController();
  bool _isLoading = false;

  String? _selectedCategory;
  String? _selectedUnit;

  // Currency symbol from business settings
  String get _currencySymbol => '₱';

  final List<String> _categories = const [
    'Vegetables',
    'Meat',
    'Dairy',
    'Grains',
    'Spices',
    'Beverages',
  ];

  final List<String> _units = const [
    'pcs',
    'kg',
    'g',
    'L',
    'mL',
    'pack',
    'bottle',
  ];

  @override
  void initState() {
    super.initState();
    final initialCategory = widget.initialCategory;
    if (initialCategory != null && _categories.contains(initialCategory)) {
      _selectedCategory = initialCategory;
      _categoryController.text = initialCategory;
    }
    _selectedUnit = _units.first;
    _unitController.text = _selectedUnit!;
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 8);
    return AlertDialog(
      title: const Text('Add Inventory Item'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  final fieldWidth = isWide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;

                  Widget cell(Widget child) {
                    return SizedBox(width: fieldWidth, child: child);
                  }

                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      cell(
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Item Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value?.isEmpty ?? true ? 'Required' : null,
                        ),
                      ),
                      cell(
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCategory = value;
                              _categoryController.text = value ?? '';
                            });
                          },
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _currentStockController,
                          decoration: const InputDecoration(
                            labelText: 'Current Stock',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*\.?[0-9]*$'),
                            ),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null) return 'Invalid number';
                            if (parsed < 0) return 'Must be \u2265 0';
                            return null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: _units
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedUnit = value;
                              _unitController.text = value ?? '';
                            });
                          },
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      cell(
                        TextFormField(
                          controller: _minStockController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum Stock',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*\.?[0-9]*$'),
                            ),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null) return 'Invalid number';
                            if (parsed < 0) return 'Must be \u2265 0';
                            return null;
                          },
                        ),
                      ),
                      cell(
                        TextFormField(
                          controller: _unitCostController,
                          decoration: InputDecoration(
                            labelText: 'Unit Cost',
                            border: const OutlineInputBorder(),
                            prefixText: '$_currencySymbol ',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*\.?[0-9]*$'),
                            ),
                          ],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null) return 'Invalid number';
                            if (parsed < 0) return 'Must be \u2265 0';
                            return null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: gap,
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: TextFormField(
                          controller: _supplierController,
                          decoration: const InputDecoration(
                            labelText: 'Supplier (Optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addItem,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Item'),
        ),
      ],
    );
  }

  Future<void> _addItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.createInventoryItem(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        currentStock: double.tryParse(_currentStockController.text.trim()) ?? 0,
        unit: _unitController.text.trim(),
        minStock: double.tryParse(_minStockController.text.trim()) ?? 0,
        unitCost: double.tryParse(_unitCostController.text.trim()) ?? 0,
        sellingPrice: null,
        supplier: _supplierController.text,
      );

      if (mounted) {
        final newItem =
            InventoryItem.fromJson(result['data'] as Map<String, dynamic>);
        Navigator.of(context).pop(newItem);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory item added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _currentStockController.dispose();
    _minStockController.dispose();
    _unitController.dispose();
    _unitCostController.dispose();
    _supplierController.dispose();
    super.dispose();
  }
}

class _EditItemDialog extends StatefulWidget {
  final InventoryItem item;

  const _EditItemDialog({
    Key? key,
    required this.item,
  }) : super(key: key);

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _minStockController;
  late final TextEditingController _unitCostController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _supplierController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _categoryController = TextEditingController(text: widget.item.category);
    _minStockController =
        TextEditingController(text: widget.item.minStock.toString());
    _unitCostController =
        TextEditingController(text: widget.item.unitCost.toString());
    _sellingPriceController = TextEditingController(
      text: widget.item.sellingPrice == 0
          ? ''
          : widget.item.sellingPrice.toString(),
    );
    _supplierController = TextEditingController(text: widget.item.supplier);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Inventory Item'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minStockController,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Stock',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCostController,
                  decoration: const InputDecoration(
                    labelText: 'Unit Cost',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sellingPriceController,
                  decoration: const InputDecoration(
                    labelText: 'Selling Price (Optional)',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^[0-9]*\.?[0-9]*$'),
                    ),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return null;
                    }
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null) return 'Invalid number';
                    if (parsed < 0) return 'Must be \u2265 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _supplierController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateItem,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Update Item'),
        ),
      ],
    );
  }

  Future<void> _updateItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.updateInventoryItem(
        widget.item.id,
        name: _nameController.text,
        category: _categoryController.text,
        minStock: double.parse(_minStockController.text),
        unitCost: double.parse(_unitCostController.text),
        sellingPrice: _sellingPriceController.text.trim().isEmpty
            ? 0
            : (double.tryParse(_sellingPriceController.text.trim()) ?? 0),
        supplier: _supplierController.text,
      );

      if (mounted) {
        // Optimistic update - return updated item
        final updatedItem = widget.item.copyWith(
          name: _nameController.text,
          category: _categoryController.text,
          minStock: double.parse(_minStockController.text),
          unitCost: double.parse(_unitCostController.text),
          sellingPrice: _sellingPriceController.text.trim().isEmpty
              ? 0
              : (double.tryParse(_sellingPriceController.text.trim()) ?? 0),
          supplier: _supplierController.text,
        );
        Navigator.of(context).pop(updatedItem);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory item updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _minStockController.dispose();
    _unitCostController.dispose();
    _sellingPriceController.dispose();
    _supplierController.dispose();
    super.dispose();
  }
}

class _UpdateStockDialog extends StatefulWidget {
  final InventoryItem item;

  const _UpdateStockDialog({
    Key? key,
    required this.item,
  }) : super(key: key);

  @override
  State<_UpdateStockDialog> createState() => _UpdateStockDialogState();
}

class _UpdateStockDialogState extends State<_UpdateStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  String _operation = 'set';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update Stock - ${widget.item.name}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current Stock: ${widget.item.currentStock}${widget.item.unit}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            RadioListTile<String>(
              title: const Text('Set Stock'),
              value: 'set',
              groupValue: _operation,
              onChanged: (value) => setState(() => _operation = value!),
            ),
            RadioListTile<String>(
              title: const Text('Add Stock'),
              value: 'add',
              groupValue: _operation,
              onChanged: (value) => setState(() => _operation = value!),
            ),
            RadioListTile<String>(
              title: const Text('Subtract Stock'),
              value: 'subtract',
              groupValue: _operation,
              onChanged: (value) => setState(() => _operation = value!),
            ),
            RadioListTile<String>(
              title: const Text('Mark Damaged'),
              value: 'damage',
              groupValue: _operation,
              onChanged: (value) => setState(() => _operation = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: _operation == 'set'
                    ? 'New Stock (${widget.item.unit})'
                    : _operation == 'damage'
                        ? 'Damaged Quantity (${widget.item.unit})'
                        : 'Quantity (${widget.item.unit})',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return 'Required';
                }
                final quantity = double.tryParse(text);
                if (quantity == null || quantity <= 0) {
                  return 'Enter a valid quantity';
                }
                if ((_operation == 'subtract' || _operation == 'damage') && quantity > widget.item.currentStock) {
                  return 'Cannot exceed current stock';
                }
                return null;
              },
            ),
            if (_operation == 'subtract' || _operation == 'damage') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Maximum: ${widget.item.currentStock}${widget.item.unit}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateStock,
          child: _isLoading
              ? const CircularProgressIndicator()
              : Text(_operation == 'damage' ? 'Mark Damaged' : 'Update Stock'),
        ),
      ],
    );
  }

  Future<void> _updateStock() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final quantity = double.parse(_quantityController.text);
      final currentStock = widget.item.currentStock;
      double newStock;

      if (_operation == 'damage') {
        await ApiService.markInventoryDamaged(
          widget.item.id,
          quantity: quantity,
          reason: 'Marked damaged from stock dialog',
        );
        newStock = currentStock - quantity;
      } else {
        switch (_operation) {
          case 'add':
            newStock = currentStock + quantity;
            break;
          case 'subtract':
            newStock = currentStock - quantity;
            break;
          case 'set':
          default:
            newStock = quantity;
        }

        await ApiService.updateInventoryStock(
          widget.item.id,
          quantity: quantity,
          operation: _operation,
        );
      }

      if (mounted) {
        // Optimistic update - return item with updated stock
        final updatedItem = widget.item.copyWith(
          currentStock: newStock,
          badStockQuantity: _operation == 'damage'
              ? widget.item.badStockQuantity + quantity
              : widget.item.badStockQuantity,
          isBadStock: _operation == 'damage' || widget.item.isBadStock,
        );
        Navigator.of(context).pop(updatedItem);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _operation == 'damage'
                  ? 'Marked $quantity${widget.item.unit} as damaged'
                  : 'Stock updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }
}
