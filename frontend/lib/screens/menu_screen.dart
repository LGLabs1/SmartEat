import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:provider/provider.dart';

import '../services/api_service.dart';

import '../services/auth_provider.dart';

import '../services/menu_form_options.dart';

import '../theme.dart';

import '../widgets/admin/admin_bottom_tabs.dart';
import '../widgets/dashboard/dashboard_back_handler.dart';
import '../widgets/feature_tab_header.dart';
import '../widgets/menu_image_picker.dart';

import '../features/inventory/domain/services/menu_availability.dart';

import '../features/inventory/presentation/widgets/add_item_dialog.dart';

import 'recipe_editor_page.dart';

import 'recipe_list_page.dart';

Widget menuCompactNavIcon(IconData icon, String label) {
  return Semantics(
    label: label,
    child: Tooltip(
      message: label,
      child: Icon(icon),
    ),
  );
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onBackHandlerChanged,
  }) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;

  final bool showAppBar;

  final VoidCallback? onOpenDrawer;

  final DashboardBackHandlerChanged? onBackHandlerChanged;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _menuItems = [];

  List<Map<String, dynamic>> _inventoryItems = const [];

  bool _isLoading = false;

  String _searchQuery = '';

  String _selectedCategoryFilter = 'All';

  bool _isAdmin = false;

  bool _isApprovedStaff = false;

  String? _lastRoleUid;

  VoidCallback? _globalSearchListener;

  // Track pinned item IDs

  List<String> _pinnedItemIds = [];

  TabController? _tabController;

  final List<int> _menuTabHistory = <int>[0];

  int _lastMenuTabIndex = 0;

  bool _restoringMenuTab = false;

  void _ensureTabController() {
    if (!_isAdmin) {
      _tabController?.removeListener(_onTabChanged);

      _tabController?.dispose();

      _tabController = null;

      return;
    }

    if (_tabController != null) return;

    _tabController = TabController(length: 2, vsync: this);

    _tabController!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_restoringMenuTab) return;

    final index = _tabController?.index ?? 0;

    if (index != _lastMenuTabIndex) {
      _menuTabHistory.add(index);

      _lastMenuTabIndex = index;
    }

    if (mounted) setState(() {});
  }

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

    widget.onBackHandlerChanged?.call(
      DashboardBackHandler(
        canUnwind: () =>
            widget.showAppBar == false &&
            _isAdmin &&
            _menuTabHistory.length > 1,
        unwind: () {
          if (_menuTabHistory.length <= 1 || _tabController == null) {
            return false;
          }
          _restoringMenuTab = true;
          _menuTabHistory.removeLast();
          final previous = _menuTabHistory.last;
          _lastMenuTabIndex = previous;
          _tabController!.index = previous;
          _restoringMenuTab = false;
          setState(() {});
          return true;
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);

    _tabController?.removeListener(_onTabChanged);

    _tabController?.dispose();

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

      final nextIsStaff = _isStaffFromProfile(profile);

      final shouldReload = !_isAdmin && nextIsAdmin;

      setState(() {
        _isAdmin = nextIsAdmin;

        _isApprovedStaff = nextIsStaff;
      });

      _ensureTabController();

      if (shouldReload) {
        await _loadMenuItems();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isAdmin = false;

        _isApprovedStaff = false;
      });
    }
  }

  bool _isStaffFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;

    final approved = profile['approved'];

    return approved != false; // Staff is approved unless explicitly false
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
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteMenuItem(id);

      // Optimistic update - remove from local list without full refresh

      _removeMenuItemFromLocal(id);

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
      // Load menu items first

      final results = await Future.wait([
        ApiService.getMenuItems(),
        ApiService.getInventoryItems(),
        ApiService.getRecipes()
            .catchError((dynamic _) => <String, dynamic>{'data': const []}),
      ]);

      final menuRes = results[0];

      final invRes = results[1];

      final recipeRes = results[2];

      final menuItems =
          List<Map<String, dynamic>>.from(menuRes['data'] ?? const []);

      final inventoryItems =
          List<Map<String, dynamic>>.from(invRes['data'] ?? const []);

      final recipes =
          List<Map<String, dynamic>>.from(recipeRes['data'] ?? const []);

      // Load pinned items separately (don't block on this)

      _loadPinnedItems();

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
                isAvailable: stock > 0,
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
        for (final inv in inventoryItems)
          (inv['id'] ?? '').toString().trim(): inv,
      };

      final inventoryByName = <String, Map<String, dynamic>>{
        for (final inv in inventoryItems)
          (inv['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' '): inv,
      };

      final recipeById = <String, Map<String, dynamic>>{
        for (final recipe in recipes)
          (recipe['id'] ?? '').toString().trim(): recipe,
      };

      for (final item in menuItems) {
        final result = MenuAvailability.resolve(
          menuItem: item,
          inventoryById: inventoryById,
          inventoryByName: inventoryByName,
          recipeById: recipeById,
        );
        MenuAvailability.applyTo(item, result);
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

  // Optimistic update helpers

  void _removeMenuItemFromLocal(String id) {
    setState(() {
      _menuItems = _menuItems.where((m) => m['id'] != id).toList();
    });
  }

  void _addMenuItemToLocal(Map<String, dynamic> item) {
    setState(() {
      _menuItems = [item, ..._menuItems];
    });
  }

  void _updateMenuItemInLocal(String id, Map<String, dynamic> updates) {
    setState(() {
      _menuItems = _menuItems.map((m) {
        if (m['id'] == id) {
          return {...m, ...updates};
        }

        return m;
      }).toList();
    });
  }

  Future<void> _loadPinnedItems() async {
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();

      final eateryId = (profile?['eateryId'] ?? '').toString();

      if (eateryId.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('settings')
          .doc('pinned_menu_items')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final pinned = data['pinnedIds'] as List<dynamic>? ?? [];

        _pinnedItemIds = pinned.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Silently fail - pinned items are not critical
    }
  }

  Future<void> _togglePinItem(String itemId) async {
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();

      final eateryId = (profile?['eateryId'] ?? '').toString();

      if (eateryId.isEmpty) return;

      setState(() {
        if (_pinnedItemIds.contains(itemId)) {
          _pinnedItemIds.remove(itemId);
        } else {
          _pinnedItemIds.add(itemId);
        }
      });

      await FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('settings')
          .doc('pinned_menu_items')
          .set({
        'eateryId': eateryId,
        'pinnedIds': _pinnedItemIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_pinnedItemIds.contains(itemId)
              ? 'Item pinned to top'
              : 'Item unpinned'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update pin: $e')),
      );
    }
  }

  bool _isPinned(String itemId) {
    return _pinnedItemIds.contains(itemId);
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

    final theme = Theme.of(context);

    final showRecipeTabs = _isAdmin && !widget.showAppBar;

    if (showRecipeTabs) _ensureTabController();

    final tc = showRecipeTabs ? _tabController : null;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              leading: widget.onOpenDrawer != null
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                      onPressed: widget.onOpenDrawer,
                    )
                  : (Navigator.of(context).canPop()
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                      : null),
              title: Text(tc != null ? 'Menu & Recipes' : 'Menu Management'),
              actions: [
                if (_isAdmin)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add menu item',
                    onPressed: _showAddItemDialog,
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadMenuItems,
                ),
              ],
            )
          : null,
      floatingActionButton: !_isAdmin
          ? null
          : tc != null
              ? (tc.index == 0
                  ? FloatingActionButton.extended(
                      onPressed: _showAddItemDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Menu Item'),
                    )
                  : FloatingActionButton.extended(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const RecipeEditorPage()),
                        );
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Recipe'),
                    ))
              : (!widget.showAppBar
                  ? FloatingActionButton.extended(
                      onPressed: _showAddItemDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Menu Item'),
                    )
                  : null),
      bottomNavigationBar: tc == null
          ? null
          : AdminBottomTabs(
              tabs: const [
                AdminTabItem(
                    label: 'Menu', icon: Icons.restaurant_menu_outlined),
                AdminTabItem(label: 'Recipes', icon: Icons.menu_book_outlined),
              ],
              selectedIndex: tc.index,
              onTap: tc.animateTo,
            ),
      body: Column(
        children: [
          FeatureTabHeader(
            title: 'Menu',
            tabs: tc == null
                ? const [
                    FeatureTabItem(
                        label: 'Menu', icon: Icons.restaurant_menu_outlined)
                  ]
                : const [
                    FeatureTabItem(
                        label: 'Menu', icon: Icons.restaurant_menu_outlined),
                    FeatureTabItem(
                        label: 'Recipes', icon: Icons.menu_book_outlined),
                  ],
            selectedIndex: tc?.index ?? 0,
          ),
          Expanded(
            child: tc == null
                ? _buildMenuTab(theme, availableFilters, selectedCategoryFilter,
                    filteredItems)
                : TabBarView(
                    controller: tc,
                    children: [
                      _buildMenuTab(theme, availableFilters,
                          selectedCategoryFilter, filteredItems),
                      const RecipeListPage(embedded: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTab(
    ThemeData theme,
    List<String> availableFilters,
    String selectedCategoryFilter,
    List<Map<String, dynamic>> filteredItems,
  ) {
    return _isLoading
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
                      label: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: theme.colorScheme.primaryContainer,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      side: BorderSide(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
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

                          final crossAxisCount = width >= 1200
                              ? 5
                              : width >= 900
                                  ? 4
                                  : width >= 600
                                      ? 3
                                      : 2;
                          final cardWidth =
                              (width - 32 - (8 * (crossAxisCount - 1))) /
                                  crossAxisCount;
                          final cardHeight = cardWidth;

                          Widget header(String title) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Row(
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Divider(
                                      color:
                                          Theme.of(context).colorScheme.outline,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        mainAxisExtent: cardHeight,
                                      ),
                                      itemCount: items.length,
                                      itemBuilder: (context, index) {
                                        final item = items[index];

                                        return _MenuGridCard(
                                          item: item,
                                          isPinned: _isPinned(
                                              (item['id'] ?? '').toString()),
                                          onPinToggle: () => _togglePinItem(
                                              (item['id'] ?? '').toString()),
                                          onEdit: () =>
                                              _showEditItemDialog(item),
                                          onDelete: _isAdmin
                                              ? () =>
                                                  _confirmDeleteMenuItem(item)
                                              : null,
                                          onToggleAvailability: (_isAdmin ||
                                                  _isApprovedStaff)
                                              ? (v) =>
                                                  _setItemAvailability(item, v)
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
                              mainAxisExtent: cardHeight,
                            ),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];

                              return _MenuGridCard(
                                item: item,
                                isPinned:
                                    _isPinned((item['id'] ?? '').toString()),
                                onPinToggle: () => _togglePinItem(
                                    (item['id'] ?? '').toString()),
                                onEdit: () => _showEditItemDialog(item),
                                onDelete: _isAdmin
                                    ? () => _confirmDeleteMenuItem(item)
                                    : null,
                                onToggleAvailability:
                                    (_isAdmin || _isApprovedStaff)
                                        ? (v) => _setItemAvailability(item, v)
                                        : null,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
  }

  Future<void> _showAddItemDialog() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _AddItemDialog(
        inventoryItems: _inventoryItems,
        onOpenInventoryCreation: _openInventoryCreationFromMenu,
        onOpenRecipeCreation: _openRecipeCreationFromMenu,
      ),
    );

    // Optimistic update - add to local list without full refresh

    if (result != null && result['id'] != null) {
      _addMenuItemToLocal(result);
    }
  }

  Future<void> _showEditItemDialog(Map<String, dynamic> item) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _EditItemDialog(
        item: item,
        isAdmin: _isAdmin,
        inventoryItems: _inventoryItems,
        onOpenInventoryCreation: _openInventoryCreationFromMenu,
        onOpenRecipeCreation: _openRecipeCreationFromMenu,
      ),
    );

    // Optimistic update - update local list without full refresh

    if (result != null && result['id'] != null) {
      _updateMenuItemInLocal(result['id'] as String, result);
    }
  }

  Future<void> _openInventoryCreationFromMenu() async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => const AddItemDialog(),
    );

    if (!mounted) return;

    await _loadMenuItems();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? 'No inventory item added. Add your menu item when ready.'
              : 'Inventory item added. You can now add your menu item.',
        ),
      ),
    );
  }

  Future<void> _openRecipeCreationFromMenu() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeEditorPage()),
    );

    if (!mounted) return;

    await _loadMenuItems();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You can now add your menu item.')),
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

  final bool isPinned;

  final VoidCallback? onPinToggle;

  const _MenuGridCard({
    Key? key,
    required this.item,
    required this.onEdit,
    this.onDelete,
    this.onToggleAvailability,
    this.isPinned = false,
    this.onPinToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final manualAvailability = item['isAvailable'];

    final isAvailable = manualAvailability is bool ? manualAvailability : true;

    final unavailabilityReason = menuUnavailabilityReason(item);

    final imageUrl = (item['imageUrl'] ?? '').toString().trim();

    final rawImageAlignmentX = item['imageAlignmentX'] is num
        ? (item['imageAlignmentX'] as num).toDouble()
        : double.tryParse((item['imageAlignmentX'] ?? '').toString()) ?? 0.0;
    final imageAlignmentX = rawImageAlignmentX < -1.0
        ? -1.0
        : rawImageAlignmentX > 1.0
            ? 1.0
            : rawImageAlignmentX;
    final rawImageAlignmentY = item['imageAlignmentY'] is num
        ? (item['imageAlignmentY'] as num).toDouble()
        : double.tryParse((item['imageAlignmentY'] ?? '').toString()) ?? 0.0;
    final imageAlignmentY = rawImageAlignmentY < -1.0
        ? -1.0
        : rawImageAlignmentY > 1.0
            ? 1.0
            : rawImageAlignmentY;

    final shouldShowImage = imageUrl.isNotEmpty &&
        !imageUrl.toLowerCase().startsWith('https://share.google/') &&
        !imageUrl.toLowerCase().startsWith('http://share.google/') &&
        !imageUrl.toLowerCase().contains('drive.google.com');

    final category = (item['category'] ?? '').toString();

    final name = (item['name'] ?? '').toString();

    final price = (item['price'] ?? 0);

    final priceInt = price is num
        ? price.toInt()
        : int.tryParse(price.toString()) ??
            (double.tryParse(price.toString())?.round() ?? 0);

    final priceText = '₱$priceInt';
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: !shouldShowImage
                      ? Container(
                          color: theme.colorScheme.surfaceVariant,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.restaurant_menu,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 40,
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          alignment:
                              Alignment(imageAlignmentX, imageAlignmentY),
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: theme.colorScheme.surfaceVariant,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 34,
                              ),
                            );
                          },
                        ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Tooltip(
                    message: unavailabilityReason.isEmpty
                        ? 'Tap to toggle availability'
                        : unavailabilityReason,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onToggleAvailability == null
                            ? null
                            : () => onToggleAvailability!.call(!isAvailable),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isAvailable
                                ? theme.colorScheme.secondaryContainer
                                    .withValues(alpha: 0.96)
                                : theme.colorScheme.errorContainer
                                    .withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isAvailable
                                  ? theme.colorScheme.secondary
                                      .withValues(alpha: 0.45)
                                  : theme.colorScheme.error
                                      .withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAvailable ? Icons.check_circle : Icons.cancel,
                                size: 14,
                                color: isAvailable
                                    ? theme.colorScheme.onSecondaryContainer
                                    : theme.colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isAvailable ? 'Available' : 'Unavailable',
                                style: TextStyle(
                                  color: isAvailable
                                      ? theme.colorScheme.onSecondaryContainer
                                      : theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0),
                    child: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(isPinned ? 'Unpin from top' : 'Pin to top'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        if (onDelete != null)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onSelected: (value) {
                        if (value == 'pin') {
                          onPinToggle?.call();
                        } else if (value == 'edit') {
                          onEdit();
                        } else if (value == 'delete') {
                          onDelete?.call();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isPinned
                              ? theme.colorScheme.error.withValues(alpha: 0.92)
                              : theme.colorScheme.surface
                                  .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: isPinned
                              ? Border.all(
                                  color: theme.colorScheme.error
                                      .withValues(alpha: 0.92),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Icon(
                          isPinned ? Icons.push_pin : Icons.more_horiz,
                          size: 14,
                          color: isPinned ? theme.colorScheme.onError : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.sageNavy.withValues(alpha: 0.08),
                      AppTheme.sageNavy.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.45, 0.78, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isPinned) ...[
                      const Icon(Icons.push_pin, size: 11, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      priceText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
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

enum _StockSource { inventory, recipe }

double? _parseStockCost(dynamic raw) {
  if (raw is num) return raw.toDouble();

  final text = (raw ?? '').toString().trim();

  if (text.isEmpty) return null;

  return double.tryParse(text);
}

Future<bool> _confirmSourceRedirect(
  BuildContext context,
  String sourceLabel,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Create a $sourceLabel first?'),
      content: Text(
        'Your menu item form will close. Create the $sourceLabel first, then return to add the menu item.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

class _StockSourceField extends StatelessWidget {
  const _StockSourceField({
    required this.initialValue,
    required this.onChanged,
  });

  final _StockSource? initialValue;

  final ValueChanged<_StockSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return FormField<_StockSource>(
      initialValue: initialValue,
      validator: (value) => value == null ? 'Choose inventory or recipe' : null,
      builder: (field) {
        final selected = field.value;

        void select(_StockSource source) {
          if (selected == source) return;

          field.didChange(source);

          onChanged(source);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _StockSourceCard(
                    label: 'Inventory',
                    subtitle: 'Track one stock item',
                    icon: Icons.inventory_2_outlined,
                    selected: selected == _StockSource.inventory,
                    onTap: () => select(_StockSource.inventory),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StockSourceCard(
                    label: 'Recipe',
                    subtitle: 'Track ingredients',
                    icon: Icons.menu_book_outlined,
                    selected: selected == _StockSource.recipe,
                    onTap: () => select(_StockSource.recipe),
                  ),
                ),
              ],
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StockSourceCard extends StatelessWidget {
  const _StockSourceCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;

  final String subtitle;

  final IconData icon;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                            : scheme.onSurfaceVariant,
                      ),
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

class _StockSourceSection extends StatelessWidget {
  const _StockSourceSection({
    required this.source,
    required this.onSourceChanged,
    required this.inventoryItems,
    required this.recipes,
    required this.loadingRecipes,
    required this.selectedInventoryId,
    required this.selectedRecipeId,
    required this.onInventorySelected,
    required this.onRecipeSelected,
    required this.itemError,
    required this.onAddInventory,
    required this.onAddRecipe,
  });

  final _StockSource? source;

  final ValueChanged<_StockSource> onSourceChanged;

  final List<Map<String, dynamic>> inventoryItems;

  final List<Map<String, dynamic>> recipes;

  final bool loadingRecipes;

  final String selectedInventoryId;

  final String selectedRecipeId;

  final ValueChanged<String> onInventorySelected;

  final ValueChanged<String> onRecipeSelected;

  final String? itemError;

  final VoidCallback onAddInventory;

  final VoidCallback onAddRecipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeSource = source;
    final selectedId = activeSource == _StockSource.inventory
        ? selectedInventoryId.trim()
        : selectedRecipeId.trim();
    final items =
        activeSource == _StockSource.inventory ? inventoryItems : recipes;
    final isLoading = activeSource == _StockSource.recipe && loadingRecipes;
    final selectedExists = items.any(
      (item) => (item['id'] ?? '').toString().trim() == selectedId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StockSourceField(
          initialValue: activeSource,
          onChanged: onSourceChanged,
        ),
        if (activeSource != null) ...[
          const SizedBox(height: 12),
          if (isLoading)
            const LinearProgressIndicator()
          else if (items.isEmpty)
            _StockSourceEmptyState(
              icon: activeSource == _StockSource.inventory
                  ? Icons.inventory_2_outlined
                  : Icons.menu_book_outlined,
              title: activeSource == _StockSource.inventory
                  ? 'No inventory items yet'
                  : 'No recipes yet',
              message: activeSource == _StockSource.inventory
                  ? 'Add an inventory item first, then come back to create this menu item.'
                  : 'Create a recipe first, then come back to link it to this menu item.',
              actionLabel: activeSource == _StockSource.inventory
                  ? 'Add Inventory Item'
                  : 'Create Recipe',
              onAction: activeSource == _StockSource.inventory
                  ? onAddInventory
                  : onAddRecipe,
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey(
                '${activeSource.name}:$selectedId:${items.length}',
              ),
              initialValue: selectedId.isEmpty ? null : selectedId,
              decoration: InputDecoration(
                labelText: activeSource == _StockSource.inventory
                    ? 'Inventory item *'
                    : 'Recipe *',
                prefixIcon: Icon(
                  activeSource == _StockSource.inventory
                      ? Icons.inventory_2_outlined
                      : Icons.menu_book_outlined,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                isDense: true,
              ),
              isExpanded: true,
              items: [
                if (selectedId.isNotEmpty && !selectedExists)
                  DropdownMenuItem(
                    value: selectedId,
                    child: Text(
                      'Linked ${activeSource == _StockSource.inventory ? 'inventory item' : 'recipe'} unavailable',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ...items.map(
                  (item) => _stockItemMenuItem(item, activeSource),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;

                if (activeSource == _StockSource.inventory) {
                  onInventorySelected(value);
                } else {
                  onRecipeSelected(value);
                }
              },
            ),
          if (items.isNotEmpty && selectedId.isNotEmpty && !selectedExists)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text(
                'The linked ${activeSource == _StockSource.inventory ? 'inventory item' : 'recipe'} no longer exists. Select another one or create a new one.',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (itemError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text(
                itemError!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ],
    );
  }

  DropdownMenuItem<String> _stockItemMenuItem(
    Map<String, dynamic> item,
    _StockSource source,
  ) {
    final id = (item['id'] ?? '').toString().trim();
    final name = (item['name'] ?? '').toString().trim();

    if (source == _StockSource.inventory) {
      final unit = (item['unit'] ?? '').toString().trim();
      final stockRaw = item['currentStock'];
      final stock = stockRaw is num
          ? stockRaw.toInt()
          : int.tryParse((stockRaw ?? '').toString()) ?? 0;
      final suffix = unit.isEmpty ? '($stock)' : '($stock $unit)';

      return DropdownMenuItem(
        value: id,
        child: Text(
          '${name.isEmpty ? 'Unnamed item' : name} $suffix',
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final cost = _parseStockCost(item['costPerServing']);
    final suffix = cost == null ? '' : ' • ₱${cost.toStringAsFixed(2)}/serving';

    return DropdownMenuItem(
      value: id,
      child: Text(
        '${name.isEmpty ? 'Unnamed recipe' : name}$suffix',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StockSourceEmptyState extends StatelessWidget {
  const _StockSourceEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;

  final String title;

  final String message;

  final String actionLabel;

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyCostField extends StatelessWidget {
  const _ReadOnlyCostField({
    required this.label,
    required this.cost,
    required this.helper,
  });

  final String label;

  final double? cost;

  final String helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = cost;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.calculate_outlined),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        isDense: true,
      ),
      child: Text(
        value == null ? '—' : '₱${value.toStringAsFixed(2)}',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: value == null ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final List<Map<String, dynamic>> inventoryItems;

  final Future<void> Function()? onOpenInventoryCreation;

  final Future<void> Function()? onOpenRecipeCreation;

  const _AddItemDialog({
    Key? key,
    required this.inventoryItems,
    this.onOpenInventoryCreation,
    this.onOpenRecipeCreation,
  }) : super(key: key);

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();

  int _price = 0;

  final _descriptionController = TextEditingController();

  bool _isLoading = false;

  final Set<String> _selectedCategories = <String>{};

  String _selectedInventoryItemId = '';

  String _selectedRecipeId = '';

  _StockSource? _stockSource;

  String? _itemError;

  bool _manualIsAvailable = true;

  final _imageUrlController = TextEditingController();

  double _imageAlignmentX = 0.0;

  double _imageAlignmentY = 0.0;

  List<Map<String, dynamic>> _recipes = [];

  bool _loadingRecipes = true;

  @override
  void initState() {
    super.initState();

    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    try {
      final res = await ApiService.getRecipes();

      final list = List<Map<String, dynamic>>.from(res['data'] ?? const []);

      if (!mounted) return;

      setState(() {
        _recipes = list;

        _loadingRecipes = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _loadingRecipes = false);
    }
  }

  Map<String, dynamic>? get _selectedRecipe {
    final id = _selectedRecipeId.trim();

    if (id.isEmpty) return null;

    for (final r in _recipes) {
      if ((r['id'] ?? '').toString() == id) return r;
    }

    return null;
  }

  Map<String, dynamic>? get _selectedInventory {
    final id = _selectedInventoryItemId.trim();

    if (id.isEmpty) return null;

    for (final inv in widget.inventoryItems) {
      if ((inv['id'] ?? '').toString().trim() == id) return inv;
    }

    return null;
  }

  double? get _selectedCost {
    switch (_stockSource) {
      case _StockSource.inventory:
        return _parseStockCost(_selectedInventory?['unitCost']);
      case _StockSource.recipe:
        return _parseStockCost(_selectedRecipe?['costPerServing']);
      case null:
        return null;
    }
  }

  String get _costLabel {
    switch (_stockSource) {
      case _StockSource.inventory:
        return 'Unit cost (₱)';
      case _StockSource.recipe:
        return 'Serving cost (₱)';
      case null:
        return 'Unit/Serving cost (₱)';
    }
  }

  String get _costHelper {
    switch (_stockSource) {
      case _StockSource.inventory:
        return 'Auto-filled from inventory unit cost';
      case _StockSource.recipe:
        final ingredients = _selectedRecipe?['ingredients'];
        final count = ingredients is List ? ingredients.length : null;
        return count == null
            ? 'Auto-filled from recipe'
            : 'Auto-filled from recipe • $count ingredients';
      case null:
        return 'Select a stock source to compute cost';
    }
  }

  void _onSourceChanged(_StockSource source) {
    setState(() {
      _stockSource = source;
      _selectedInventoryItemId = '';
      _selectedRecipeId = '';
      _itemError = null;
    });
  }

  void _onInventorySelected(String id) {
    setState(() {
      _selectedInventoryItemId = id;
      _selectedRecipeId = '';
      _itemError = null;
    });
  }

  void _onRecipeSelected(String id) {
    setState(() {
      _selectedRecipeId = id;
      _selectedInventoryItemId = '';
      _itemError = null;
    });
  }

  Future<void> _redirectToInventory() async {
    if (!await _confirmSourceRedirect(context, 'inventory item')) return;

    if (!mounted) return;

    Navigator.of(context).pop();

    widget.onOpenInventoryCreation?.call();
  }

  Future<void> _redirectToRecipe() async {
    if (!await _confirmSourceRedirect(context, 'recipe')) return;

    if (!mounted) return;

    Navigator.of(context).pop();

    widget.onOpenRecipeCreation?.call();
  }

  bool _validateSourceSelection() {
    final source = _stockSource;

    if (source == null) return false;

    final id = source == _StockSource.inventory
        ? _selectedInventoryItemId.trim()
        : _selectedRecipeId.trim();
    final items =
        source == _StockSource.inventory ? widget.inventoryItems : _recipes;

    if (source == _StockSource.recipe && _loadingRecipes) {
      setState(() => _itemError = 'Recipes are still loading. Please wait.');
      return false;
    }

    if (items.isEmpty) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Add an inventory item first.'
            : 'Create a recipe first.';
      });
      return false;
    }

    if (id.isEmpty) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Choose an inventory item.'
            : 'Choose a recipe.';
      });
      return false;
    }

    final exists =
        items.any((item) => (item['id'] ?? '').toString().trim() == id);

    if (!exists) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Select an available inventory item.'
            : 'Select an available recipe.';
      });
      return false;
    }

    setState(() => _itemError = null);

    return true;
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, {Widget? prefixIcon, String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: prefixIcon,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final selectedCost = _selectedCost;

    final margin =
        (selectedCost != null && _price > 0) ? (_price - selectedCost) : null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: theme.colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(Icons.restaurant_menu_rounded,
                      color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add Menu Item',
                            style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer)),
                        Text(
                            'Fields marked * are required. Choose an inventory item or recipe to track stock.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer)),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: Icon(Icons.close,
                          color: theme.colorScheme.onPrimaryContainer),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 560;

                    final half = twoCol
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;

                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                              context, Icons.info_outline, 'Basic Information'),
                          TextFormField(
                              controller: _nameController,
                              decoration: _dec('Dish Name *',
                                  prefixIcon: const Icon(
                                      Icons.restaurant_menu_rounded)),
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null),
                          const SizedBox(height: 16),
                          _sectionTitle(context, Icons.inventory_2_outlined,
                              'Stock Source *'),
                          _StockSourceSection(
                            source: _stockSource,
                            onSourceChanged: _onSourceChanged,
                            inventoryItems: widget.inventoryItems,
                            recipes: _recipes,
                            loadingRecipes: _loadingRecipes,
                            selectedInventoryId: _selectedInventoryItemId,
                            selectedRecipeId: _selectedRecipeId,
                            onInventorySelected: _onInventorySelected,
                            onRecipeSelected: _onRecipeSelected,
                            itemError: _itemError,
                            onAddInventory: _redirectToInventory,
                            onAddRecipe: _redirectToRecipe,
                          ),
                          if (margin != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Estimated margin per item: ₱${margin.toStringAsFixed(2)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: margin >= 0
                                      ? AppTheme.sageSuccess
                                      : theme.colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          _sectionTitle(
                              context, Icons.category_outlined, 'Category *'),
                          FormField<Set<String>>(
                              initialValue: _selectedCategories,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                              builder: (state) {
                                return InputDecorator(
                                    decoration: InputDecoration(
                                        labelText: 'Select categories',
                                        border: const OutlineInputBorder(
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(12))),
                                        errorText: state.errorText,
                                        isDense: true),
                                    child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: menuCategoryOptions.map((c) {
                                          final selected =
                                              state.value?.contains(c) ?? false;

                                          return FilterChip(
                                              label: Text(c,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500)),
                                              selected: selected,
                                              onSelected: (_) {
                                                setState(() {
                                                  if (_selectedCategories
                                                      .contains(c)) {
                                                    _selectedCategories
                                                        .remove(c);
                                                  } else {
                                                    _selectedCategories.add(c);
                                                  }
                                                });

                                                state.didChange(
                                                    _selectedCategories);
                                              });
                                        }).toList()));
                              }),
                          const SizedBox(height: 16),
                          Wrap(spacing: 16, runSpacing: 16, children: [
                            SizedBox(
                                width: half,
                                child: _IntStepperTextFormField(
                                    labelText: 'Price (₱) *',
                                    value: _price,
                                    min: 0,
                                    onChanged: (v) =>
                                        setState(() => _price = v),
                                    validator: (v) =>
                                        v <= 0 ? 'Required' : null,
                                    prefixIcon: Icons.payments_rounded)),
                            SizedBox(
                              width: half,
                              child: _ReadOnlyCostField(
                                label: _costLabel,
                                cost: selectedCost,
                                helper: _costHelper,
                              ),
                            ),
                          ]),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Available on menu'),
                            subtitle: const Text(
                                'Turn off to hide this item without deleting it.'),
                            value: _manualIsAvailable,
                            onChanged: (v) =>
                                setState(() => _manualIsAvailable = v),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: _descriptionController,
                              decoration: _dec('Description (optional)',
                                  prefixIcon:
                                      const Icon(Icons.description_rounded)),
                              maxLines: 3),
                          const SizedBox(height: 20),
                          _sectionTitle(context, Icons.image_outlined,
                              'Image (optional)'),
                          MenuImagePickerField(
                            imageUrlController: _imageUrlController,
                            onImageUploaded: (_) => setState(() {
                              _imageAlignmentX = 0;
                              _imageAlignmentY = 0;
                            }),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: _imageUrlController,
                              decoration: _dec('Dish Image URL',
                                      prefixIcon:
                                          const Icon(Icons.link_rounded),
                                      helper:
                                          'Direct image URL (.jpg/.png/.webp)')
                                  .copyWith(
                                      suffixIcon: _imageUrlController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () => setState(() {
                                                    _imageUrlController.clear();
                                                    _imageAlignmentX = 0;
                                                    _imageAlignmentY = 0;
                                                  }))),
                              keyboardType: TextInputType.url,
                              onChanged: (_) => setState(() {})),
                          const SizedBox(height: 12),
                          _MenuItemPreviewCard(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Sample Dish'
                                  : _nameController.text.trim(),
                              price: _price.toDouble(),
                              imageUrl: _imageUrlController.text.trim(),
                              imageAlignmentX: _imageAlignmentX,
                              imageAlignmentY: _imageAlignmentY),
                          if (_imageUrlController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Horizontal focus',
                                style: theme.textTheme.bodySmall),
                            Slider(
                                value: _imageAlignmentX,
                                min: -1,
                                max: 1,
                                divisions: 20,
                                label: _imageAlignmentX == 0
                                    ? 'Center'
                                    : _imageAlignmentX < 0
                                        ? 'Left'
                                        : 'Right',
                                onChanged: (v) =>
                                    setState(() => _imageAlignmentX = v)),
                            Text('Vertical focus',
                                style: theme.textTheme.bodySmall),
                            Slider(
                                value: _imageAlignmentY,
                                min: -1,
                                max: 1,
                                divisions: 20,
                                label: _imageAlignmentY == 0
                                    ? 'Center'
                                    : _imageAlignmentY < 0
                                        ? 'Top'
                                        : 'Bottom',
                                onChanged: (v) =>
                                    setState(() => _imageAlignmentY = v)),
                          ],
                        ]);
                  }),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: _isLoading ? null : _addItem,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Add Item')),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final invId = _selectedInventoryItemId.trim();
      final recipeId = _selectedRecipeId.trim();

      if (!_validateSourceSelection()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final inventoryById = <String, Map<String, dynamic>>{
        for (final inv in widget.inventoryItems)
          (inv['id'] ?? '').toString().trim(): inv,
      };
      final recipeById = <String, Map<String, dynamic>>{
        for (final recipe in _recipes)
          (recipe['id'] ?? '').toString().trim(): recipe,
      };
      final availability = MenuAvailability.resolve(
        menuItem: {
          'inventoryItemId': invId,
          'recipeId': recipeId,
        },
        inventoryById: inventoryById,
        recipeById: recipeById,
      );

      final name = _nameController.text.trim();

      final cats = _selectedCategories.toList()..sort();

      final category = cats.isEmpty ? '' : cats.first;

      final imageUrl = _imageUrlController.text.trim();

      final result = await ApiService.createMenuItem(
        name: name,
        category: category,
        categories: cats,
        inventoryItemId: invId.isEmpty ? null : invId,
        recipeId: recipeId.isEmpty ? null : recipeId,
        price: _price,
        availableServings: availability.availableServings ?? 0,
        isAvailable: _manualIsAvailable,
        description: _descriptionController.text,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        imageAlignmentX: imageUrl.isEmpty ? null : _imageAlignmentX,
        imageAlignmentY: imageUrl.isEmpty ? null : _imageAlignmentY,
      );

      if (mounted) {
        final newItem = result['data'] as Map<String, dynamic>?;

        Navigator.of(context).pop(newItem);

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Menu item added successfully')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  final List<Map<String, dynamic>> inventoryItems;

  final bool isAdmin;

  final Future<void> Function()? onOpenInventoryCreation;

  final Future<void> Function()? onOpenRecipeCreation;

  const _EditItemDialog({
    Key? key,
    required this.item,
    required this.isAdmin,
    required this.inventoryItems,
    this.onOpenInventoryCreation,
    this.onOpenRecipeCreation,
  }) : super(key: key);

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  int _price = 0;

  late final TextEditingController _descriptionController;

  late final TextEditingController _imageUrlController;

  bool _isLoading = false;

  final Set<String> _selectedCategories = <String>{};

  double _imageAlignmentX = 0.0;

  double _imageAlignmentY = 0.0;

  String _selectedInventoryItemId = '';

  String _selectedRecipeId = '';

  _StockSource? _stockSource;

  String? _itemError;

  bool _manualIsAvailable = true;

  List<Map<String, dynamic>> _recipes = [];

  bool _loadingRecipes = true;

  @override
  void initState() {
    super.initState();

    _nameController =
        TextEditingController(text: (widget.item['name'] ?? '').toString());

    _descriptionController = TextEditingController(
        text: (widget.item['description'] ?? '').toString());

    _imageUrlController = TextEditingController(
        text: (widget.item['imageUrl'] ?? '').toString().trim());

    _imageUrlController.addListener(() => setState(() {}));

    final rawImageAlignmentX = widget.item['imageAlignmentX'] is num
        ? (widget.item['imageAlignmentX'] as num).toDouble()
        : double.tryParse((widget.item['imageAlignmentX'] ?? '').toString()) ??
            0.0;

    _imageAlignmentX = rawImageAlignmentX.clamp(-1.0, 1.0);

    final rawImageAlignmentY = widget.item['imageAlignmentY'] is num
        ? (widget.item['imageAlignmentY'] as num).toDouble()
        : double.tryParse((widget.item['imageAlignmentY'] ?? '').toString()) ??
            0.0;

    _imageAlignmentY = rawImageAlignmentY.clamp(-1.0, 1.0);

    final priceRaw = widget.item['price'];

    _price = priceRaw is num
        ? priceRaw.toInt()
        : int.tryParse(priceRaw?.toString() ?? '') ??
            (double.tryParse(priceRaw?.toString() ?? '')?.round() ?? 0);

    _selectedInventoryItemId =
        (widget.item['inventoryItemId'] ?? '').toString();

    _selectedRecipeId = (widget.item['recipeId'] ?? '').toString();

    if (_selectedRecipeId.trim().isNotEmpty) {
      _stockSource = _StockSource.recipe;
      _selectedInventoryItemId = '';
    } else if (_selectedInventoryItemId.trim().isNotEmpty) {
      _stockSource = _StockSource.inventory;
    }

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

    _manualIsAvailable = manual is bool ? manual : true;

    _loadRecipes();
  }

  Future<void> _loadRecipes() async {
    try {
      final res = await ApiService.getRecipes();

      final list = List<Map<String, dynamic>>.from(res['data'] ?? const []);

      if (!mounted) return;

      setState(() {
        _recipes = list;

        _loadingRecipes = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _loadingRecipes = false);
    }
  }

  Map<String, dynamic>? get _selectedRecipe {
    final id = _selectedRecipeId.trim();

    if (id.isEmpty) return null;

    for (final r in _recipes) {
      if ((r['id'] ?? '').toString() == id) return r;
    }

    return null;
  }

  Map<String, dynamic>? get _selectedInventory {
    final id = _selectedInventoryItemId.trim();

    if (id.isEmpty) return null;

    for (final inv in widget.inventoryItems) {
      if ((inv['id'] ?? '').toString().trim() == id) return inv;
    }

    return null;
  }

  double? get _selectedCost {
    switch (_stockSource) {
      case _StockSource.inventory:
        return _parseStockCost(_selectedInventory?['unitCost']);
      case _StockSource.recipe:
        return _parseStockCost(_selectedRecipe?['costPerServing']);
      case null:
        return null;
    }
  }

  String get _costLabel {
    switch (_stockSource) {
      case _StockSource.inventory:
        return 'Unit cost (₱)';
      case _StockSource.recipe:
        return 'Serving cost (₱)';
      case null:
        return 'Unit/Serving cost (₱)';
    }
  }

  String get _costHelper {
    switch (_stockSource) {
      case _StockSource.inventory:
        return 'Auto-filled from inventory unit cost';
      case _StockSource.recipe:
        final ingredients = _selectedRecipe?['ingredients'];
        final count = ingredients is List ? ingredients.length : null;
        return count == null
            ? 'Auto-filled from recipe'
            : 'Auto-filled from recipe • $count ingredients';
      case null:
        return 'Select a stock source to compute cost';
    }
  }

  void _onSourceChanged(_StockSource source) {
    setState(() {
      _stockSource = source;
      _selectedInventoryItemId = '';
      _selectedRecipeId = '';
      _itemError = null;
    });
  }

  void _onInventorySelected(String id) {
    setState(() {
      _selectedInventoryItemId = id;
      _selectedRecipeId = '';
      _itemError = null;
    });
  }

  void _onRecipeSelected(String id) {
    setState(() {
      _selectedRecipeId = id;
      _selectedInventoryItemId = '';
      _itemError = null;
    });
  }

  Future<void> _redirectToInventory() async {
    if (!await _confirmSourceRedirect(context, 'inventory item')) return;

    if (!mounted) return;

    Navigator.of(context).pop();

    widget.onOpenInventoryCreation?.call();
  }

  Future<void> _redirectToRecipe() async {
    if (!await _confirmSourceRedirect(context, 'recipe')) return;

    if (!mounted) return;

    Navigator.of(context).pop();

    widget.onOpenRecipeCreation?.call();
  }

  bool _validateSourceSelection() {
    final source = _stockSource;

    if (source == null) return false;

    final id = source == _StockSource.inventory
        ? _selectedInventoryItemId.trim()
        : _selectedRecipeId.trim();
    final items =
        source == _StockSource.inventory ? widget.inventoryItems : _recipes;

    if (source == _StockSource.recipe && _loadingRecipes) {
      setState(() => _itemError = 'Recipes are still loading. Please wait.');
      return false;
    }

    if (items.isEmpty) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Add an inventory item first.'
            : 'Create a recipe first.';
      });
      return false;
    }

    if (id.isEmpty) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Choose an inventory item.'
            : 'Choose a recipe.';
      });
      return false;
    }

    final exists =
        items.any((item) => (item['id'] ?? '').toString().trim() == id);

    if (!exists) {
      setState(() {
        _itemError = source == _StockSource.inventory
            ? 'Select an available inventory item.'
            : 'Select an available recipe.';
      });
      return false;
    }

    setState(() => _itemError = null);

    return true;
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      ]),
    );
  }

  InputDecoration _dec(String label, {Widget? prefixIcon, String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: prefixIcon,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final selectedCost = _selectedCost;

    final margin =
        (selectedCost != null && _price > 0) ? (_price - selectedCost) : null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: theme.colorScheme.primaryContainer,
              child: Row(children: [
                Icon(Icons.edit_note_rounded,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Edit Menu Item',
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer)),
                      Text('Choose an inventory item or recipe to track stock.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer)),
                    ])),
                IconButton(
                    icon: Icon(Icons.close,
                        color: theme.colorScheme.onPrimaryContainer),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 560;

                    final half = twoCol
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;

                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                              context, Icons.info_outline, 'Basic Information'),
                          TextFormField(
                              controller: _nameController,
                              decoration: _dec('Dish Name *',
                                  prefixIcon: const Icon(
                                      Icons.restaurant_menu_rounded)),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null),
                          const SizedBox(height: 16),
                          _sectionTitle(context, Icons.inventory_2_outlined,
                              'Stock Source *'),
                          _StockSourceSection(
                            source: _stockSource,
                            onSourceChanged: _onSourceChanged,
                            inventoryItems: widget.inventoryItems,
                            recipes: _recipes,
                            loadingRecipes: _loadingRecipes,
                            selectedInventoryId: _selectedInventoryItemId,
                            selectedRecipeId: _selectedRecipeId,
                            onInventorySelected: _onInventorySelected,
                            onRecipeSelected: _onRecipeSelected,
                            itemError: _itemError,
                            onAddInventory: _redirectToInventory,
                            onAddRecipe: _redirectToRecipe,
                          ),
                          if (margin != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Estimated margin per item: ₱${margin.toStringAsFixed(2)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: margin >= 0
                                      ? AppTheme.sageSuccess
                                      : theme.colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          _sectionTitle(
                              context, Icons.category_outlined, 'Category *'),
                          FormField<Set<String>>(
                              initialValue: _selectedCategories,
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                              builder: (state) => InputDecorator(
                                  decoration: InputDecoration(
                                      labelText: 'Select categories',
                                      border: const OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(12))),
                                      errorText: state.errorText,
                                      isDense: true),
                                  child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: menuCategoryOptions.map((c) {
                                        final selected =
                                            state.value?.contains(c) ?? false;

                                        return FilterChip(
                                            label: Text(c,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: selected
                                                        ? FontWeight.w700
                                                        : FontWeight.w500)),
                                            selected: selected,
                                            onSelected: (_) {
                                              setState(() {
                                                if (_selectedCategories
                                                    .contains(c)) {
                                                  _selectedCategories.remove(c);
                                                } else {
                                                  _selectedCategories.add(c);
                                                }
                                              });

                                              state.didChange(
                                                  _selectedCategories);
                                            });
                                      }).toList()))),
                          const SizedBox(height: 16),
                          Wrap(spacing: 16, runSpacing: 16, children: [
                            SizedBox(
                                width: half,
                                child: _IntStepperTextFormField(
                                    labelText: 'Price (₱) *',
                                    value: _price,
                                    min: 0,
                                    onChanged: (v) =>
                                        setState(() => _price = v),
                                    validator: (v) =>
                                        v <= 0 ? 'Required' : null,
                                    prefixIcon: Icons.payments_rounded)),
                            SizedBox(
                              width: half,
                              child: _ReadOnlyCostField(
                                label: _costLabel,
                                cost: selectedCost,
                                helper: _costHelper,
                              ),
                            ),
                          ]),
                          SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Available on menu'),
                              subtitle: const Text(
                                  'Turn off to hide this item without deleting it.'),
                              value: _manualIsAvailable,
                              onChanged: (v) =>
                                  setState(() => _manualIsAvailable = v)),
                          const SizedBox(height: 8),
                          TextFormField(
                              controller: _descriptionController,
                              decoration: _dec('Description (optional)',
                                  prefixIcon:
                                      const Icon(Icons.description_rounded)),
                              maxLines: 3),
                          const SizedBox(height: 20),
                          _sectionTitle(context, Icons.image_outlined,
                              'Image (optional)'),
                          MenuImagePickerField(
                            imageUrlController: _imageUrlController,
                            menuItemId:
                                (widget.item['id'] ?? '').toString().trim(),
                            onImageUploaded: (_) => setState(() {
                              _imageAlignmentX = 0;
                              _imageAlignmentY = 0;
                            }),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: _imageUrlController,
                              decoration: _dec('Dish Image URL',
                                      prefixIcon:
                                          const Icon(Icons.link_rounded))
                                  .copyWith(
                                      suffixIcon: _imageUrlController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () => setState(() {
                                                    _imageUrlController.clear();
                                                    _imageAlignmentX = 0;
                                                    _imageAlignmentY = 0;
                                                  }))),
                              keyboardType: TextInputType.url,
                              onChanged: (_) => setState(() {})),
                          const SizedBox(height: 12),
                          _MenuItemPreviewCard(
                              name: _nameController.text.trim().isEmpty
                                  ? 'Sample Dish'
                                  : _nameController.text.trim(),
                              price: _price.toDouble(),
                              imageUrl: _imageUrlController.text.trim(),
                              imageAlignmentX: _imageAlignmentX,
                              imageAlignmentY: _imageAlignmentY),
                          if (_imageUrlController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Horizontal focus',
                                style: theme.textTheme.bodySmall),
                            Slider(
                                value: _imageAlignmentX,
                                min: -1,
                                max: 1,
                                divisions: 20,
                                onChanged: (v) =>
                                    setState(() => _imageAlignmentX = v)),
                            Text('Vertical focus',
                                style: theme.textTheme.bodySmall),
                            Slider(
                                value: _imageAlignmentY,
                                min: -1,
                                max: 1,
                                divisions: 20,
                                onChanged: (v) =>
                                    setState(() => _imageAlignmentY = v)),
                          ],
                        ]);
                  }),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
                padding: const EdgeInsets.all(20),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                      onPressed: _isLoading ? null : _updateItem,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Changes')),
                ])),
          ],
        ),
      ),
    );
  }

  Future<void> _updateItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_price <= 0) throw Exception('Invalid price');

      final invId = _selectedInventoryItemId.trim();
      final recipeId = _selectedRecipeId.trim();

      if (!_validateSourceSelection()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final inventoryById = <String, Map<String, dynamic>>{
        for (final inv in widget.inventoryItems)
          (inv['id'] ?? '').toString().trim(): inv,
      };
      final recipeById = <String, Map<String, dynamic>>{
        for (final recipe in _recipes)
          (recipe['id'] ?? '').toString().trim(): recipe,
      };
      final availability = MenuAvailability.resolve(
        menuItem: {
          'inventoryItemId': invId,
          'recipeId': recipeId,
        },
        inventoryById: inventoryById,
        recipeById: recipeById,
      );

      final result = await ApiService.updateMenuItem(
        widget.item['id'],
        name: _nameController.text.trim(),
        category: _selectedCategories.isEmpty ? '' : _selectedCategories.first,
        categories: _selectedCategories.toList()..sort(),
        price: _price,
        inventoryItemId: invId,
        recipeId: recipeId,
        availableServings: availability.availableServings ?? 0,
        isAvailable: _manualIsAvailable,
        description: _descriptionController.text,
        imageUrl: _imageUrlController.text.trim(),
        imageAlignmentX: _imageAlignmentX,
        imageAlignmentY: _imageAlignmentY,
      );

      if (mounted) {
        final updated =
            result['data'] as Map<String, dynamic>? ?? <String, dynamic>{};

        Navigator.of(context).pop(updated);

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Menu item updated successfully')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

class _MenuItemPreviewCard extends StatelessWidget {
  const _MenuItemPreviewCard({
    Key? key,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.imageAlignmentX,
    required this.imageAlignmentY,
  }) : super(key: key);

  final String name;

  final double price;

  final String imageUrl;

  final double imageAlignmentX;

  final double imageAlignmentY;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final displayName = name.trim().isEmpty ? 'Menu preview' : name;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment(imageAlignmentX, imageAlignmentY),
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Unable to load image preview',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 52,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.onSurface.withValues(alpha: 0.0),
                      theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Γé▒${price.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w900,
                      ),
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

class _IntStepperTextFormField extends StatefulWidget {
  const _IntStepperTextFormField({
    required this.labelText,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.validator,
    this.prefixIcon,
  });

  final String labelText;

  final int value;

  final int min;

  final ValueChanged<int> onChanged;

  final String? Function(int value)? validator;

  final IconData? prefixIcon;

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
    final canDecrement = widget.value > widget.min;

    final colorScheme = Theme.of(context).colorScheme;

    return FormField<int>(
      initialValue: widget.value,
      validator: (_) => widget.validator?.call(widget.value),
      builder: (state) {
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            errorText: state.errorText,
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.prefixIcon != null) ...[
                  const SizedBox(width: 12),
                  Icon(widget.prefixIcon,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ],
                IconButton(
                  tooltip: 'Decrease',
                  onPressed:
                      canDecrement ? () => _setValue(widget.value - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: canDecrement ? colorScheme.primary : null,
                ),
              ],
            ),
            suffixIcon: IconButton(
              tooltip: 'Increase',
              onPressed: () => _setValue(widget.value + 1),
              icon: const Icon(Icons.add_circle_outline),
              color: colorScheme.primary,
            ),
          ),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            _isEditingText = true;

            final parsed = _parseOrFallback(value, widget.value);

            _setValue(parsed);
          },
          onTap: () {
            _isEditingText = true;
          },
          onEditingComplete: () {
            _isEditingText = false;

            final parsed = _parseOrFallback(_controller.text, widget.value);

            _controller.text =
                (parsed < widget.min ? widget.min : parsed).toString();
          },
          onFieldSubmitted: (_) {
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
