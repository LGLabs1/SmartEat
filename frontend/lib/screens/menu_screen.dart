import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key, this.globalSearchQuery}) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

List<String> _extractCategories(Map<String, dynamic> item) {
  final raw = item['categories'];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  final single = (item['category'] ?? '').toString().trim();
  return single.isEmpty ? const [] : [single];
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> _menuItems = [];
  List<Map<String, dynamic>> _inventoryItems = const [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategoryFilter = 'All';
  bool _isAdmin = false;
  String? _lastRoleUid;
  VoidCallback? _globalSearchListener;

  Future<void> _setItemAvailability(
      Map<String, dynamic> item, bool value) async {
    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    final prev = item['isAvailable'];

    setState(() {
      _menuItems = _menuItems.map((m) {
        final mid = (m['id'] ?? '').toString().trim();
        if (mid != id) return m;
        return {
          ...m,
          'isAvailable': value,
        };
      }).toList();
    });

    try {
      await ApiService.updateMenuItem(id, isAvailable: value);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _menuItems = _menuItems.map((m) {
          final mid = (m['id'] ?? '').toString().trim();
          if (mid != id) return m;
          return {
            ...m,
            'isAvailable': prev,
          };
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMenuItems();
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
      final nextIsAdmin = _isAdminFromProfile(profile);
      final shouldReload = !_isAdmin && nextIsAdmin;
      setState(() {
        _isAdmin = nextIsAdmin;
      });
      if (shouldReload) {
        await _loadMenuItems();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
      });
    }
  }

  Future<void> _confirmDeleteMenuItem(Map<String, dynamic> item) async {
    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final name = (item['name'] ?? '').toString().trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Menu Item'),
          content: Text(
            'Delete "${name.isEmpty ? 'this item' : name}"? This cannot be undone.',
          ),
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
      await ApiService.deleteMenuItem(id);
      if (!mounted) return;
      await _loadMenuItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menu item deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _loadMenuItems() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        ApiService.getMenuItems(),
        ApiService.getInventoryItems(),
      ]);

      final menuRes = results[0];
      final invRes = results[1];

      final menuItems =
          List<Map<String, dynamic>>.from(menuRes['data'] ?? const []);
      final inventoryItems =
          List<Map<String, dynamic>>.from(invRes['data'] ?? const []);

      if (_isAdmin) {
        DateTime? _parseDocDate(dynamic raw) {
          if (raw == null) return null;
          if (raw is DateTime) return raw;
          if (raw is Timestamp) return raw.toDate();
          return DateTime.tryParse(raw.toString());
        }

        final byInventoryId = <String, List<Map<String, dynamic>>>{};
        for (final m in menuItems) {
          final invId = (m['inventoryItemId'] ?? '').toString().trim();
          if (invId.isEmpty) continue;
          byInventoryId.putIfAbsent(invId, () => []).add(m);
        }

        final List<Future<void>> dedupeOps = [];
        for (final entry in byInventoryId.entries) {
          final items = entry.value;
          if (items.length <= 1) continue;

          items.sort((a, b) {
            final aUpdated = _parseDocDate(a['updatedAt']) ??
                _parseDocDate(a['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bUpdated = _parseDocDate(b['updatedAt']) ??
                _parseDocDate(b['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bUpdated.compareTo(aUpdated);
          });

          for (final dupe in items.skip(1)) {
            final id = (dupe['id'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            dedupeOps.add(ApiService.deleteMenuItem(id).then((_) {}));
          }
        }

        if (dedupeOps.isNotEmpty) {
          await Future.wait(dedupeOps);
          final refreshed = await ApiService.getMenuItems();
          menuItems
            ..clear()
            ..addAll(
                List<Map<String, dynamic>>.from(refreshed['data'] ?? const []));
        }

        final menuByInventoryId = <String, Map<String, dynamic>>{};
        for (final m in menuItems) {
          final invId = (m['inventoryItemId'] ?? '').toString().trim();
          if (invId.isEmpty) continue;
          menuByInventoryId[invId] = m;
        }

        final sellingPriceByInventoryId = <String, double>{
          for (final inv in inventoryItems)
            (inv['id'] ?? '').toString().trim(): (inv['sellingPrice'] is num
                ? (inv['sellingPrice'] as num).toDouble()
                : double.tryParse((inv['sellingPrice'] ?? '').toString()) ?? 0),
        };

        final List<Future<void>> syncOps = [];
        for (final inv in inventoryItems) {
          final invId = (inv['id'] ?? '').toString().trim();
          if (invId.isEmpty) continue;
          final name = (inv['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final sellingRaw = inv['sellingPrice'];
          final selling = sellingRaw is num
              ? sellingRaw.toDouble()
              : double.tryParse((sellingRaw ?? '').toString()) ?? 0;
          if (selling <= 0) continue;

          final stockRaw = inv['currentStock'];
          final stock = stockRaw is num
              ? stockRaw.toInt()
              : int.tryParse((stockRaw ?? '').toString()) ?? 0;

          final existing = menuByInventoryId[invId];
          if (existing == null) {
            syncOps.add(() async {
              await ApiService.createMenuItem(
                name: name,
                category: 'Drinks',
                categories: const ['Drinks'],
                inventoryItemId: invId,
                price: selling.round(),
                availableServings: stock,
                description: '',
                imageUrl: '',
              );
            }());
          } else {
            final priceRaw = existing['price'];
            final existingPrice = priceRaw is num
                ? priceRaw.toDouble()
                : double.tryParse((priceRaw ?? '').toString()) ?? 0;

            final servingsRaw = existing['availableServings'];
            final existingServings = servingsRaw is num
                ? servingsRaw.toInt()
                : int.tryParse((servingsRaw ?? '').toString()) ?? 0;

            final needsPriceUpdate = existingPrice.round() != selling.round();
            final needsServingsUpdate = existingServings != stock;

            if (needsPriceUpdate || needsServingsUpdate) {
              final id = (existing['id'] ?? '').toString().trim();
              if (id.isNotEmpty) {
                syncOps.add(() async {
                  await ApiService.updateMenuItem(
                    id,
                    price: selling.round(),
                    availableServings: stock,
                  );
                }());
              }
            }
          }
        }

        for (final entry in menuByInventoryId.entries) {
          final invId = entry.key;
          final menu = entry.value;
          final selling = sellingPriceByInventoryId[invId] ?? 0;
          if (selling > 0) continue;
          final id = (menu['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          syncOps.add(() async {
            await ApiService.updateMenuItem(
              id,
              availableServings: 0,
            );
          }());
        }

        if (syncOps.isNotEmpty) {
          await Future.wait(syncOps);
          final refreshed = await ApiService.getMenuItems();
          menuItems
            ..clear()
            ..addAll(
                List<Map<String, dynamic>>.from(refreshed['data'] ?? const []));
        }
      }

      final inventoryById = <String, Map<String, dynamic>>{
        for (final inv in inventoryItems) (inv['id'] ?? '').toString(): inv,
      };

      for (final item in menuItems) {
        final invId = (item['inventoryItemId'] ?? '').toString().trim();
        if (invId.isEmpty) continue;
        final inv = inventoryById[invId];
        if (inv == null) continue;
        final stockRaw = inv['currentStock'];
        final stock = stockRaw is num
            ? stockRaw.toInt()
            : int.tryParse((stockRaw ?? '').toString()) ?? 0;
        item['availableServings'] = stock;
        final manual = item['isAvailable'];
        final manualOff = manual is bool && manual == false;
        item['isAvailable'] = stock > 0 && !manualOff;
      }

      setState(() {
        _menuItems = menuItems;
        _inventoryItems = inventoryItems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading menu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      for (final item in _menuItems) ...[
        ..._extractCategories(item),
      ]
    }.where((c) => c.isNotEmpty).toList()
      ..sort();

    final availableFilters = <String>['All', ...categories];
    final selectedCategoryFilter =
        availableFilters.contains(_selectedCategoryFilter)
            ? _selectedCategoryFilter
            : 'All';

    final filteredItems = _menuItems.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final categoryList = _extractCategories(item);

      final matchesQuery = _searchQuery.trim().isEmpty ||
          name.contains(_searchQuery.trim().toLowerCase());
      final matchesCategory = selectedCategoryFilter == 'All' ||
          categoryList.contains(selectedCategoryFilter);
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddItemDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMenuItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final label = availableFilters[index];
                      final isSelected = label == selectedCategoryFilter;
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => _selectedCategoryFilter = label),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: availableFilters.length,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredItems.isEmpty
                      ? const Center(child: Text('No menu items found'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final crossAxisCount = width >= 1100
                                ? 4
                                : width >= 800
                                    ? 3
                                    : width >= 520
                                        ? 2
                                        : 1;

                            Widget header(String title) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 8),
                                child: Row(
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Divider(
                                        color: Colors.grey.shade300,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (selectedCategoryFilter == 'All') {
                              final grouped =
                                  <String, List<Map<String, dynamic>>>{};
                              for (final item in filteredItems) {
                                final cats = _extractCategories(item);
                                final key = (cats.isNotEmpty
                                        ? cats.first
                                        : (item['category'] ?? '')
                                            .toString()
                                            .trim())
                                    .trim();
                                final normalized =
                                    key.isEmpty ? 'Uncategorized' : key;
                                grouped
                                    .putIfAbsent(normalized, () => [])
                                    .add(item);
                              }

                              final keys = grouped.keys.toList()
                                ..sort((a, b) =>
                                    a.toLowerCase().compareTo(b.toLowerCase()));

                              return ListView.builder(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: keys.length,
                                itemBuilder: (context, sectionIndex) {
                                  final key = keys[sectionIndex];
                                  final items = grouped[key] ?? const [];

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      header(key),
                                      GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 8),
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                          childAspectRatio:
                                              crossAxisCount == 1 ? 3.3 : 1.28,
                                        ),
                                        itemCount: items.length,
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          return _MenuGridCard(
                                            item: item,
                                            onEdit: () =>
                                                _showEditItemDialog(item),
                                            onDelete: _isAdmin
                                                ? () =>
                                                    _confirmDeleteMenuItem(item)
                                                : null,
                                            onToggleAvailability: _isAdmin
                                                ? (v) => _setItemAvailability(
                                                    item, v)
                                                : null,
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              );
                            }

                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio:
                                    crossAxisCount == 1 ? 3.3 : 1.28,
                              ),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                return _MenuGridCard(
                                  item: item,
                                  onEdit: () => _showEditItemDialog(item),
                                  onDelete: _isAdmin
                                      ? () => _confirmDeleteMenuItem(item)
                                      : null,
                                  onToggleAvailability: _isAdmin
                                      ? (v) => _setItemAvailability(item, v)
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        inventoryItems: _inventoryItems,
        onItemAdded: _loadMenuItems,
      ),
    );
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => _EditItemDialog(
        item: item,
        isAdmin: _isAdmin,
        inventoryItems: _inventoryItems,
        onItemUpdated: _loadMenuItems,
      ),
    );
  }

  List<String> _extractCategories(Map<String, dynamic> item) {
    final raw = item['categories'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final single = (item['category'] ?? '').toString().trim();
    return single.isEmpty ? const [] : [single];
  }
}

class _MenuGridCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleAvailability;

  const _MenuGridCard({
    Key? key,
    required this.item,
    required this.onEdit,
    this.onDelete,
    this.onToggleAvailability,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final servingsRaw = item['availableServings'];
    final servings = servingsRaw is num
        ? servingsRaw.toInt()
        : int.tryParse((servingsRaw ?? '').toString()) ?? 0;
    final manualAvailability = item['isAvailable'];
    final isAvailable =
        manualAvailability is bool ? manualAvailability : servings > 0;
    final imageUrl = (item['imageUrl'] ?? '').toString().trim();
    final availableServings = item['availableServings'];
    final category = (item['category'] ?? '').toString();
    final name = (item['name'] ?? '').toString();
    final price = (item['price'] ?? 0);

    final priceInt = price is num
        ? price.toInt()
        : int.tryParse(price.toString()) ??
            (double.tryParse(price.toString())?.round() ?? 0);
    final priceText = '₱$priceInt';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: imageUrl.isEmpty
                      ? Container(
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.restaurant_menu,
                            color: Colors.grey.shade500,
                            size: 40,
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey.shade500,
                                size: 34,
                              ),
                            );
                          },
                        ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onToggleAvailability == null
                          ? null
                          : () => onToggleAvailability?.call(!isAvailable),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? Colors.green.shade600
                                    : Colors.red.shade600,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isAvailable ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                color: Colors.grey.shade900,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.transparent,
                    child: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit();
                        } else if (value == 'delete') {
                          onDelete?.call();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Icon(Icons.more_horiz, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          priceText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.green.shade800,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Text(
                          availableServings == null
                              ? 'Servings: —'
                              : 'Servings: $availableServings',
                          style: TextStyle(
                            color: Colors.indigo.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final VoidCallback onItemAdded;
  final List<Map<String, dynamic>> inventoryItems;

  const _AddItemDialog({
    Key? key,
    required this.onItemAdded,
    required this.inventoryItems,
  }) : super(key: key);

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _price = 0;
  int _availableServings = 0;
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  bool _isLoading = false;
  final Set<String> _selectedCategories = <String>{};

  List<Map<String, dynamic>> _recipes = const [];
  String _selectedRecipeId = '';

  String _selectedInventoryItemId = '';

  static const List<String> _categoryOptions = <String>[
    'Chicken',
    'Pork',
    'Beef',
    'Seafood',
    'Veggies',
    'Egg',
    'Tofu',
    'Rice',
    'Noodles',
    'Dessert',
    'Drinks',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    try {
      final res = await ApiService.getRecipes();
      if (!mounted) return;
      final recipes = List<Map<String, dynamic>>.from(res['data'] ?? const []);
      recipes.sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
      setState(() => _recipes = recipes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _recipes = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedInventoryId = _selectedInventoryItemId.trim();
    final inventoryLinked = selectedInventoryId.isNotEmpty;

    return AlertDialog(
      title: const Text('Add Menu Item'),
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
                    labelText: 'Dish',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedRecipeId,
                  decoration: const InputDecoration(
                    labelText: 'Recipe (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('None'),
                    ),
                    ..._recipes.map((r) {
                      final id = (r['id'] ?? '').toString();
                      final name = (r['name'] ?? '').toString();
                      return DropdownMenuItem(
                        value: id,
                        child: Text(name.isEmpty ? 'Untitled recipe' : name),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedRecipeId = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedInventoryItemId,
                  decoration: const InputDecoration(
                    labelText: 'Inventory Link (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('None'),
                    ),
                    ...widget.inventoryItems.map((inv) {
                      final id = (inv['id'] ?? '').toString();
                      final name = (inv['name'] ?? '').toString();
                      final unit = (inv['unit'] ?? '').toString();
                      final stockRaw = inv['currentStock'];
                      final stock = stockRaw is num
                          ? stockRaw.toInt()
                          : int.tryParse((stockRaw ?? '').toString()) ?? 0;
                      final label = unit.isEmpty
                          ? '$name ($stock)'
                          : '$name ($stock$unit)';
                      return DropdownMenuItem(
                        value: id,
                        child:
                            Text(label.trim().isEmpty ? 'Unnamed item' : label),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedInventoryItemId = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                FormField<Set<String>>(
                  initialValue: _selectedCategories,
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Required' : null,
                  builder: (state) {
                    return InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: const OutlineInputBorder(),
                        errorText: state.errorText,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions.map((c) {
                          final selected = state.value?.contains(c) ?? false;
                          return ChoiceChip(
                            label: Text(c),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                if (_selectedCategories.contains(c)) {
                                  _selectedCategories.remove(c);
                                } else {
                                  _selectedCategories.add(c);
                                }
                              });
                              state.didChange(_selectedCategories);
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _IntStepperTextFormField(
                        labelText: 'Price (₱)',
                        value: _price,
                        min: 0,
                        onChanged: (v) => setState(() => _price = v),
                        validator: (v) => v <= 0 ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _IntStepperTextFormField(
                        labelText: 'Servings',
                        value: _availableServings,
                        min: 0,
                        enabled: !inventoryLinked,
                        onChanged: (v) =>
                            setState(() => _availableServings = v),
                        validator: (v) => v < 0 ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (Optional)',
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
          onPressed: _isLoading ? null : _addItem,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Add Item'),
        ),
      ],
    );
  }

  Future<void> _addItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      var servingsToSave = _availableServings;
      final invId = _selectedInventoryItemId.trim();
      if (invId.isNotEmpty) {
        final inv =
            widget.inventoryItems.cast<Map<String, dynamic>>().firstWhere(
                  (e) => (e['id'] ?? '').toString() == invId,
                  orElse: () => const {},
                );
        final stockRaw = inv['currentStock'];
        servingsToSave = stockRaw is num
            ? stockRaw.toInt()
            : int.tryParse((stockRaw ?? '').toString()) ?? 0;
      }

      final name = _nameController.text.trim();
      final cats = _selectedCategories.toList()..sort();
      final category = cats.isEmpty ? '' : cats.first;

      await ApiService.createMenuItem(
        name: name,
        category: category,
        categories: cats,
        recipeId: _selectedRecipeId.trim().isEmpty ? null : _selectedRecipeId,
        inventoryItemId: invId.isEmpty ? null : invId,
        price: _price,
        availableServings: servingsToSave,
        description: _descriptionController.text,
        imageUrl: _imageUrlController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onItemAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menu item added successfully')),
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
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }
}

class _EditItemDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onItemUpdated;
  final List<Map<String, dynamic>> inventoryItems;
  final bool isAdmin;

  const _EditItemDialog({
    Key? key,
    required this.item,
    required this.isAdmin,
    required this.onItemUpdated,
    required this.inventoryItems,
  }) : super(key: key);

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  int _price = 0;
  int _availableServings = 0;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;
  bool _isLoading = false;
  final Set<String> _selectedCategories = <String>{};

  List<Map<String, dynamic>> _recipes = const [];
  String _selectedRecipeId = '';
  String _selectedInventoryItemId = '';
  bool _manualIsAvailable = true;

  static const List<String> _categoryOptions = <String>[
    'Chicken',
    'Pork',
    'Beef',
    'Seafood',
    'Veggies',
    'Egg',
    'Tofu',
    'Rice',
    'Noodles',
    'Dessert',
    'Drinks',
  ];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: (widget.item['name'] ?? '').toString());
    _descriptionController = TextEditingController(
        text: (widget.item['description'] ?? '').toString());
    _imageUrlController =
        TextEditingController(text: (widget.item['imageUrl'] ?? '').toString());

    final priceRaw = widget.item['price'];
    _price = priceRaw is num
        ? priceRaw.toInt()
        : int.tryParse(priceRaw?.toString() ?? '') ??
            (double.tryParse(priceRaw?.toString() ?? '')?.round() ?? 0);

    final servingsRaw =
        widget.item['servings'] ?? widget.item['availableServings'] ?? 0;
    _availableServings = servingsRaw is num
        ? servingsRaw.toInt()
        : int.tryParse(servingsRaw?.toString() ?? '') ?? 0;

    final inv = (widget.item['inventoryItemId'] ?? '').toString();
    _selectedInventoryItemId = inv;

    final recipe = (widget.item['recipeId'] ?? '').toString();
    _selectedRecipeId = recipe;

    final rawCats = widget.item['categories'];
    if (rawCats is List) {
      _selectedCategories
        ..clear()
        ..addAll(
            rawCats.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
    } else {
      final single = (widget.item['category'] ?? '').toString().trim();
      if (single.isNotEmpty) _selectedCategories.add(single);
    }

    final manual = widget.item['isAvailable'];
    _manualIsAvailable = manual is bool ? manual : (_availableServings > 0);

    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    try {
      final res = await ApiService.getRecipes();
      if (!mounted) return;
      final recipes = List<Map<String, dynamic>>.from(res['data'] ?? const []);
      recipes.sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
      setState(() {
        _recipes = recipes;
        final ids = recipes.map((r) => (r['id'] ?? '').toString()).toSet();
        if (_selectedRecipeId.isNotEmpty && !ids.contains(_selectedRecipeId)) {
          _selectedRecipeId = '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _recipes = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedInventoryId = _selectedInventoryItemId.trim();
    final inventoryLinked = selectedInventoryId.isNotEmpty;

    return AlertDialog(
      title: const Text('Edit Menu Item'),
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
                    labelText: 'Dish',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedRecipeId,
                  decoration: const InputDecoration(
                    labelText: 'Recipe (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('None'),
                    ),
                    ..._recipes.map((r) {
                      final id = (r['id'] ?? '').toString();
                      final name = (r['name'] ?? '').toString();
                      return DropdownMenuItem(
                        value: id,
                        child: Text(name.isEmpty ? 'Untitled recipe' : name),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedRecipeId = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedInventoryItemId,
                  decoration: const InputDecoration(
                    labelText: 'Inventory Link (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('None'),
                    ),
                    ...widget.inventoryItems.map((inv) {
                      final id = (inv['id'] ?? '').toString();
                      final name = (inv['name'] ?? '').toString();
                      final unit = (inv['unit'] ?? '').toString();
                      final stockRaw = inv['currentStock'];
                      final stock = stockRaw is num
                          ? stockRaw.toInt()
                          : int.tryParse((stockRaw ?? '').toString()) ?? 0;
                      final label = unit.isEmpty
                          ? '$name ($stock)'
                          : '$name ($stock$unit)';
                      return DropdownMenuItem(
                        value: id,
                        child:
                            Text(label.trim().isEmpty ? 'Unnamed item' : label),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedInventoryItemId = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                FormField<Set<String>>(
                  initialValue: _selectedCategories,
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Required' : null,
                  builder: (state) {
                    return InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: const OutlineInputBorder(),
                        errorText: state.errorText,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions.map((c) {
                          final selected = state.value?.contains(c) ?? false;
                          return ChoiceChip(
                            label: Text(c),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                if (_selectedCategories.contains(c)) {
                                  _selectedCategories.remove(c);
                                } else {
                                  _selectedCategories.add(c);
                                }
                              });
                              state.didChange(_selectedCategories);
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _IntStepperTextFormField(
                        labelText: 'Price (₱)',
                        value: _price,
                        min: 0,
                        onChanged: (v) => setState(() => _price = v),
                        validator: (v) => v <= 0 ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _IntStepperTextFormField(
                        labelText: 'Servings',
                        value: _availableServings,
                        min: 0,
                        enabled: !inventoryLinked,
                        onChanged: (v) =>
                            setState(() => _availableServings = v),
                        validator: (v) => v < 0 ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available in POS'),
                    value: _manualIsAvailable,
                    onChanged: (v) => setState(() => _manualIsAvailable = v),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (Optional)',
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
      if (_price <= 0) {
        throw Exception('Invalid price');
      }
      if (_availableServings < 0) {
        throw Exception('Invalid available servings');
      }

      var servingsToSave = _availableServings;
      final invId = _selectedInventoryItemId.trim();
      if (invId.isNotEmpty) {
        final inv =
            widget.inventoryItems.cast<Map<String, dynamic>>().firstWhere(
                  (e) => (e['id'] ?? '').toString() == invId,
                  orElse: () => const {},
                );
        final stockRaw = inv['currentStock'];
        servingsToSave = stockRaw is num
            ? stockRaw.toInt()
            : int.tryParse((stockRaw ?? '').toString()) ?? 0;
      }

      await ApiService.updateMenuItem(
        widget.item['id'],
        name: _nameController.text,
        category: _selectedCategories.isEmpty ? '' : _selectedCategories.first,
        categories: _selectedCategories.toList()..sort(),
        recipeId: _selectedRecipeId,
        price: _price,
        inventoryItemId: invId,
        availableServings: servingsToSave,
        isAvailable: _manualIsAvailable,
        description: _descriptionController.text,
        imageUrl: _imageUrlController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onItemUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menu item updated successfully')),
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
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }
}

class _IntStepperTextFormField extends StatefulWidget {
  const _IntStepperTextFormField({
    required this.labelText,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.enabled = true,
    this.validator,
  });

  final String labelText;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? Function(int value)? validator;

  @override
  State<_IntStepperTextFormField> createState() =>
      _IntStepperTextFormFieldState();
}

class _IntStepperTextFormFieldState extends State<_IntStepperTextFormField> {
  late final TextEditingController _controller;
  bool _isEditingText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _IntStepperTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingText && oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  int _parseOrFallback(String s, int fallback) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return fallback;
    return int.tryParse(trimmed) ?? fallback;
  }

  void _setValue(int v) {
    final next = v < widget.min ? widget.min : v;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final canDecrement = widget.enabled && widget.value > widget.min;
    final canIncrement = widget.enabled;
    final colorScheme = Theme.of(context).colorScheme;

    return FormField<int>(
      initialValue: widget.value,
      validator: (_) => widget.validator?.call(widget.value),
      builder: (state) {
        return TextFormField(
          controller: _controller,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
            errorText: state.errorText,
            prefixIcon: IconButton(
              tooltip: 'Decrease',
              onPressed:
                  canDecrement ? () => _setValue(widget.value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: canDecrement ? colorScheme.primary : null,
            ),
            suffixIcon: IconButton(
              tooltip: 'Increase',
              onPressed:
                  canIncrement ? () => _setValue(widget.value + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
              color: canIncrement ? colorScheme.primary : null,
            ),
          ),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            if (!widget.enabled) return;
            _isEditingText = true;
            final parsed = _parseOrFallback(value, widget.value);
            _setValue(parsed);
          },
          onTap: () {
            if (!widget.enabled) return;
            _isEditingText = true;
          },
          onEditingComplete: () {
            if (!widget.enabled) return;
            _isEditingText = false;
            final parsed = _parseOrFallback(_controller.text, widget.value);
            _controller.text =
                (parsed < widget.min ? widget.min : parsed).toString();
          },
          onFieldSubmitted: (_) {
            if (!widget.enabled) return;
            _isEditingText = false;
            final parsed = _parseOrFallback(_controller.text, widget.value);
            _controller.text =
                (parsed < widget.min ? widget.min : parsed).toString();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
