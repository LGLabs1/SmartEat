import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:provider/provider.dart';

import '../services/api_service.dart';

import '../services/auth_provider.dart';

import 'recipe_editor_page.dart';

import 'recipe_list_page.dart';



class MenuScreen extends StatefulWidget {

  const MenuScreen({

    Key? key,

    this.globalSearchQuery,

    this.showAppBar = true,

    this.onOpenDrawer,

  }) : super(key: key);



  final ValueNotifier<String>? globalSearchQuery;

  final bool showAppBar;

  final VoidCallback? onOpenDrawer;



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

  }



  @override

  void dispose() {

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

      ]);



      final menuRes = results[0];

      final invRes = results[1];



      final menuItems =

          List<Map<String, dynamic>>.from(menuRes['data'] ?? const []);

      final inventoryItems =

          List<Map<String, dynamic>>.from(invRes['data'] ?? const []);



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

              bottom: tc == null

                  ? null

                  : TabBar(

                      controller: tc,

                      tabs: const [

                        Tab(text: 'Menu', icon: Icon(Icons.restaurant_menu_outlined)),

                        Tab(text: 'Recipes', icon: Icon(Icons.menu_book_outlined)),

                      ],

                    ),

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

          : BottomNavigationBar(

              currentIndex: tc.index,

              onTap: tc.animateTo,

              type: BottomNavigationBarType.fixed,

              items: const [

                BottomNavigationBarItem(

                  icon: Icon(Icons.restaurant_menu_outlined),

                  label: 'Menu',

                ),

                BottomNavigationBarItem(

                  icon: Icon(Icons.menu_book_outlined),

                  label: 'Recipes',

                ),

              ],

            ),

      body: tc == null

          ? _buildMenuTab(theme, availableFilters, selectedCategoryFilter, filteredItems)

          : TabBarView(

              controller: tc,

              children: [

                _buildMenuTab(theme, availableFilters, selectedCategoryFilter, filteredItems),

                const RecipeListPage(embedded: true),

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

                      backgroundColor: theme.colorScheme.surfaceContainerHighest,

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

                                      : width >= 400

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

                                      color: Theme.of(context).colorScheme.outline,

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

                                            crossAxisCount == 1 ? 3.0 : 1.25,

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

                                  crossAxisCount == 1 ? 3.0 : 1.25,

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

      ),

    );



    // Optimistic update - update local list without full refresh

    if (result != null && result['id'] != null) {

      _updateMenuItemInLocal(result['id'] as String, result);

    }

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

    final servingsRaw = item['availableServings'];

    final servings = servingsRaw is num

        ? servingsRaw.toInt()

        : int.tryParse((servingsRaw ?? '').toString()) ?? 0;

    final manualAvailability = item['isAvailable'];

    final isAvailable = manualAvailability is bool

        ? manualAvailability

        : (servings == -1 || servings > 0);

    final imageUrl = (item['imageUrl'] ?? '').toString().trim();

    final shouldShowImage = imageUrl.isNotEmpty &&

        !imageUrl.toLowerCase().startsWith('https://share.google/') &&

        !imageUrl.toLowerCase().startsWith('http://share.google/') &&

        !imageUrl.toLowerCase().contains('drive.google.com');

    final availableServings = item['availableServings'];

    final inventoryItemId = (item['inventoryItemId'] ?? '').toString().trim();

    final isInventoryLinked = inventoryItemId.isNotEmpty;

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

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Expanded(

            child: Stack(

              children: [

                Positioned.fill(

                  child: !shouldShowImage

                      ? Container(

                          color: Theme.of(context).colorScheme.surfaceVariant,

                          child: Icon(

                            Icons.restaurant_menu,

                            color: Theme.of(context).colorScheme.onSurfaceVariant,

                            size: 40,

                          ),

                        )

                      : Image.network(

                          imageUrl,

                          fit: BoxFit.cover,

                          errorBuilder: (context, error, stackTrace) {

                            return Container(

                              color: Theme.of(context).colorScheme.surfaceVariant,

                              child: Icon(

                                Icons.image_not_supported_outlined,

                                color: Theme.of(context).colorScheme.onSurfaceVariant,

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

                          color: isAvailable

                              ? theme.colorScheme.secondaryContainer.withOpacity(0.96)

                              : theme.colorScheme.errorContainer.withOpacity(0.96),

                          borderRadius: BorderRadius.circular(999),

                          border: Border.all(

                            color: isAvailable

                                ? theme.colorScheme.secondary.withOpacity(0.45)

                                : theme.colorScheme.error.withOpacity(0.45),

                          ),

                        ),

                        child: Row(

                          mainAxisSize: MainAxisSize.min,

                          children: [

                            Icon(

                              isAvailable ? Icons.check_circle : Icons.cancel,

                              size: 12,

                              color: isAvailable

                                  ? theme.colorScheme.onSecondaryContainer

                                  : theme.colorScheme.onErrorContainer,

                            ),

                            const SizedBox(width: 4),

                            Text(

                              isAvailable ? 'Available' : 'Unavailable',

                              style: TextStyle(

                                color: isAvailable

                                    ? theme.colorScheme.onSecondaryContainer

                                    : theme.colorScheme.onErrorContainer,

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

                    color: theme.colorScheme.surface.withOpacity(0),

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

                              ? Theme.of(context).colorScheme.error.withOpacity(0.92)

                              : Theme.of(context).colorScheme.surface.withOpacity(0.9),

                          borderRadius: BorderRadius.circular(999),

                          border: isPinned

                              ? Border.all(

                                  color: theme.colorScheme.error.withOpacity(0.92),

                                  width: 1,

                                )

                              : null,

                        ),

                        child: Icon(

                          isPinned ? Icons.push_pin : Icons.more_horiz,

                          size: 14,

                          color: isPinned ? Theme.of(context).colorScheme.onError : null,

                        ),

                      ),

                    ),

                  ),

                ),

              ],

            ),

          ),

          Padding(

            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Row(

                  children: [

                    if (isPinned)

                      Padding(

                        padding: const EdgeInsets.only(right: 4),

                        child: Icon(

                          Icons.push_pin,

                          size: 10,

                          color: Theme.of(context).colorScheme.error,

                        ),

                      ),

                    Expanded(

                      child: Text(

                        name,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,

                        style: const TextStyle(

                          fontSize: 13,

                          fontWeight: FontWeight.w700,

                        ),

                      ),

                    ),

                  ],

                ),

                const SizedBox(height: 1),

                Text(

                  category,

                  style: TextStyle(

                    color: Theme.of(context).colorScheme.onSurfaceVariant,

                    fontSize: 10,

                  ),

                  overflow: TextOverflow.ellipsis,

                ),

                const SizedBox(height: 3),

                Row(

                  children: [

                    Expanded(

                      child: Container(

                        padding: const EdgeInsets.symmetric(

                          horizontal: 6,

                          vertical: 3,

                        ),

                        decoration: BoxDecoration(

                          color: Theme.of(context).colorScheme.secondaryContainer,

                          borderRadius: BorderRadius.circular(999),

                          border: Border.all(

                            color: Theme.of(context).colorScheme.secondaryContainer,

                          ),

                        ),

                        child: Text(

                          priceText,

                          style: TextStyle(

                            fontSize: 10,

                            fontWeight: FontWeight.w800,

                            color: Theme.of(context).colorScheme.secondary,

                          ),

                          overflow: TextOverflow.ellipsis,

                          textAlign: TextAlign.center,

                        ),

                      ),

                    ),

                    if (isInventoryLinked) ...[

                      const SizedBox(width: 6),

                      Expanded(

                        child: Container(

                          padding: const EdgeInsets.symmetric(

                            horizontal: 6,

                            vertical: 3,

                          ),

                          decoration: BoxDecoration(

                            color: theme.colorScheme.primaryContainer,

                            borderRadius: BorderRadius.circular(999),

                            border: Border.all(

                                color: theme.colorScheme.primaryContainer),

                          ),

                          child: Center(

                            child: Text(

                              availableServings == null ||

                                      availableServings == -1

                                  ? 'ΓÇö'

                                  : 'x$availableServings',

                              style: TextStyle(

                                color: Theme.of(context).colorScheme.primary,

                                fontSize: 10,

                                fontWeight: FontWeight.w700,

                              ),

                            ),

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



class _AddItemDialog extends StatefulWidget {

  final List<Map<String, dynamic>> inventoryItems;



  const _AddItemDialog({

    Key? key,

    required this.inventoryItems,

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

  final _imageUrlController = TextEditingController();

  double _imageAlignmentX = 0.0;

  double _imageAlignmentY = 0.0;

  List<Map<String, dynamic>> _recipes = [];

  bool _loadingRecipes = true;



  static const List<String> _categoryOptions = <String>[

    'Chicken', 'Pork', 'Beef', 'Seafood', 'Veggies', 'Egg', 'Tofu', 'Rice', 'Noodles', 'Dessert', 'Drinks',

  ];



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



  Widget _sectionTitle(BuildContext context, IconData icon, String title) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 12, top: 4),

      child: Row(

        children: [

          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),

          const SizedBox(width: 8),

          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),

        ],

      ),

    );

  }



  InputDecoration _dec(String label, {Widget? prefixIcon, String? helper}) => InputDecoration(

        labelText: label,

        helperText: helper,

        prefixIcon: prefixIcon,

        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),

        isDense: true,

      );



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final recipe = _selectedRecipe;

    final batchYield = recipe == null ? null : ((recipe['batchYield'] ?? recipe['baseServings']) as num?)?.toDouble();

    final batchCost = (recipe?['batchCost'] as num?)?.toDouble();

    final costPerServing = (recipe?['costPerServing'] as num?)?.toDouble();

    final recipeLinked = _selectedRecipeId.trim().isNotEmpty;

    final margin = (costPerServing != null && _price > 0) ? (_price - costPerServing) : null;



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

                  Icon(Icons.restaurant_menu_rounded, color: theme.colorScheme.onPrimaryContainer),

                  const SizedBox(width: 12),

                  Expanded(

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text('Add Menu Item', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),

                        Text('Fields marked * are required. Link a recipe to use ingredient-based costing.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),

                      ],

                    ),

                  ),

                  IconButton(icon: Icon(Icons.close, color: theme.colorScheme.onPrimaryContainer), onPressed: () => Navigator.of(context).pop()),

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

                    final half = twoCol ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      _sectionTitle(context, Icons.info_outline, 'Basic Information'),

                      TextFormField(controller: _nameController, decoration: _dec('Dish Name *', prefixIcon: const Icon(Icons.restaurant_menu_rounded)), textInputAction: TextInputAction.next, validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),

                      const SizedBox(height: 16),

                      Wrap(spacing: 16, runSpacing: 16, children: [

                        SizedBox(width: half, child: DropdownButtonFormField<String>(value: _selectedInventoryItemId, decoration: _dec('Inventory Link (optional)', prefixIcon: const Icon(Icons.inventory_2_outlined)), isExpanded: true, items: [

                          const DropdownMenuItem(value: '', child: Text('None')),

                          ...widget.inventoryItems.map((inv) {

                            final id = (inv['id'] ?? '').toString();

                            final name = (inv['name'] ?? '').toString();

                            final unit = (inv['unit'] ?? '').toString();

                            final stockRaw = inv['currentStock'];

                            final stock = stockRaw is num ? stockRaw.toInt() : int.tryParse((stockRaw ?? '').toString()) ?? 0;

                            final label = unit.isEmpty ? '$name ($stock)' : '$name ($stock $unit)';

                            return DropdownMenuItem(value: id, child: Text(label.trim().isEmpty ? 'Unnamed item' : label, overflow: TextOverflow.ellipsis));

                          }),

                        ], onChanged: (v) => setState(() => _selectedInventoryItemId = v ?? ''))),

                        SizedBox(width: half, child: DropdownButtonFormField<String>(value: _selectedRecipeId, decoration: _dec('Recipe / Costing (optional)', prefixIcon: const Icon(Icons.menu_book_outlined), helper: recipeLinked ? 'Cost per serving synced from recipe' : 'Select to calculate ingredient-based cost'), isExpanded: true, items: [

                          const DropdownMenuItem(value: '', child: Text('None')),

                          ..._recipes.map((r) {

                            final id = (r['id'] ?? '').toString();

                            final name = (r['name'] ?? 'Unnamed recipe').toString();

                            return DropdownMenuItem(value: id, child: Text(name, overflow: TextOverflow.ellipsis));

                          }),

                        ], onChanged: _loadingRecipes ? null : (v) => setState(() => _selectedRecipeId = v ?? ''))),

                      ]),

                      if (_loadingRecipes) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),

                      if (recipeLinked) ...[

                        const SizedBox(height: 12),

                        Container(

                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),

                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                            Text('Costing Preview', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),

                            const SizedBox(height: 6),

                            Text('Batch yield: ${batchYield?.toStringAsFixed(batchYield % 1 == 0 ? 0 : 2) ?? '—'}  •  Batch cost: ${batchCost != null ? '₱${batchCost.toStringAsFixed(2)}' : '—'}  •  Cost/serving: ${costPerServing != null ? '₱${costPerServing.toStringAsFixed(2)}' : '—'}', style: theme.textTheme.bodySmall),

                            if (margin != null) Text('Estimated margin per serving (at current price): ₱${margin.toStringAsFixed(2)}', style: theme.textTheme.bodySmall?.copyWith(color: margin >= 0 ? Colors.green.shade700 : theme.colorScheme.error, fontWeight: FontWeight.w600)),

                          ]),

                        ),

                      ],

                      const SizedBox(height: 16),

                      _sectionTitle(context, Icons.category_outlined, 'Category *'),

                      FormField<Set<String>>(initialValue: _selectedCategories, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null, builder: (state) {

                        return InputDecorator(decoration: InputDecoration(labelText: 'Select categories', border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))), errorText: state.errorText, isDense: true), child: Wrap(spacing: 8, runSpacing: 8, children: _categoryOptions.map((c) {

                          final selected = state.value?.contains(c) ?? false;

                          return FilterChip(label: Text(c, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)), selected: selected, onSelected: (_) {

                            setState(() { if (_selectedCategories.contains(c)) { _selectedCategories.remove(c); } else { _selectedCategories.add(c); } });

                            state.didChange(_selectedCategories);

                          });

                        }).toList()));

                      }),

                      const SizedBox(height: 16),

                      Wrap(spacing: 16, runSpacing: 16, children: [

                        SizedBox(width: half, child: _IntStepperTextFormField(labelText: 'Price (₱) *', value: _price, min: 0, onChanged: (v) => setState(() => _price = v), validator: (v) => v <= 0 ? 'Required' : null, prefixIcon: Icons.payments_rounded)),

                      ]),

                      const SizedBox(height: 16),

                      TextFormField(controller: _descriptionController, decoration: _dec('Description (optional)', prefixIcon: const Icon(Icons.description_rounded)), maxLines: 3),

                      const SizedBox(height: 20),

                      _sectionTitle(context, Icons.image_outlined, 'Image (optional)'),

                      TextFormField(controller: _imageUrlController, decoration: _dec('Dish Image URL', prefixIcon: const Icon(Icons.link_rounded), helper: 'Direct image URL (.jpg/.png/.webp)').copyWith(suffixIcon: _imageUrlController.text.trim().isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _imageUrlController.clear(); _imageAlignmentX = 0; _imageAlignmentY = 0; }))), keyboardType: TextInputType.url, onChanged: (_) => setState(() {})),

                      const SizedBox(height: 12),

                      _MenuItemPreviewCard(name: _nameController.text.trim().isEmpty ? 'Sample Dish' : _nameController.text.trim(), price: _price.toDouble(), imageUrl: _imageUrlController.text.trim(), imageAlignmentX: _imageAlignmentX, imageAlignmentY: _imageAlignmentY),

                      if (_imageUrlController.text.trim().isNotEmpty) ...[

                        const SizedBox(height: 12),

                        Text('Horizontal focus', style: theme.textTheme.bodySmall),

                        Slider(value: _imageAlignmentX, min: -1, max: 1, divisions: 20, label: _imageAlignmentX == 0 ? 'Center' : _imageAlignmentX < 0 ? 'Left' : 'Right', onChanged: (v) => setState(() => _imageAlignmentX = v)),

                        Text('Vertical focus', style: theme.textTheme.bodySmall),

                        Slider(value: _imageAlignmentY, min: -1, max: 1, divisions: 20, label: _imageAlignmentY == 0 ? 'Center' : _imageAlignmentY < 0 ? 'Top' : 'Bottom', onChanged: (v) => setState(() => _imageAlignmentY = v)),

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

                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),

                const SizedBox(width: 12),

                ElevatedButton(onPressed: _isLoading ? null : _addItem, child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add Item')),

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

      int servingsToSave;

      if (invId.isNotEmpty) {

        final inv = widget.inventoryItems.cast<Map<String, dynamic>>().firstWhere((e) => (e['id'] ?? '').toString() == invId, orElse: () => const {});

        final stockRaw = inv['currentStock'];

        servingsToSave = stockRaw is num ? stockRaw.toInt() : int.tryParse((stockRaw ?? '').toString()) ?? 0;

      } else {

        servingsToSave = -1;

      }

      final name = _nameController.text.trim();

      final cats = _selectedCategories.toList()..sort();

      final category = cats.isEmpty ? '' : cats.first;

      final imageUrl = _imageUrlController.text.trim();

      final recipeId = _selectedRecipeId.trim();

      final result = await ApiService.createMenuItem(

        name: name,

        category: category,

        categories: cats,

        inventoryItemId: invId.isEmpty ? null : invId,

        recipeId: recipeId.isEmpty ? null : recipeId,

        price: _price,

        availableServings: servingsToSave,

        description: _descriptionController.text,

        imageUrl: imageUrl.isEmpty ? null : imageUrl,

        imageAlignmentX: imageUrl.isEmpty ? null : _imageAlignmentX,

        imageAlignmentY: imageUrl.isEmpty ? null : _imageAlignmentY,

      );

      if (mounted) {

        final newItem = result['data'] as Map<String, dynamic>?;

        Navigator.of(context).pop(newItem);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menu item added successfully')));

      }

    } catch (e) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));

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



  const _EditItemDialog({

    Key? key,

    required this.item,

    required this.isAdmin,

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

  bool _isUnlimitedServings = false;

  late final TextEditingController _descriptionController;

  late final TextEditingController _imageUrlController;

  bool _isLoading = false;

  final Set<String> _selectedCategories = <String>{};

  double _imageAlignmentX = 0.0;

  double _imageAlignmentY = 0.0;

  String _selectedInventoryItemId = '';

  String _selectedRecipeId = '';

  bool _manualIsAvailable = true;

  List<Map<String, dynamic>> _recipes = [];

  bool _loadingRecipes = true;



  static const List<String> _categoryOptions = <String>[

    'Chicken', 'Pork', 'Beef', 'Seafood', 'Veggies', 'Egg', 'Tofu', 'Rice', 'Noodles', 'Dessert', 'Drinks',

  ];



  @override

  void initState() {

    super.initState();

    _nameController = TextEditingController(text: (widget.item['name'] ?? '').toString());

    _descriptionController = TextEditingController(text: (widget.item['description'] ?? '').toString());

    _imageUrlController = TextEditingController(text: (widget.item['imageUrl'] ?? '').toString().trim());

    _imageUrlController.addListener(() => setState(() {}));

    final rawImageAlignmentX = widget.item['imageAlignmentX'] is num ? (widget.item['imageAlignmentX'] as num).toDouble() : double.tryParse((widget.item['imageAlignmentX'] ?? '').toString()) ?? 0.0;

    _imageAlignmentX = rawImageAlignmentX.clamp(-1.0, 1.0);

    final rawImageAlignmentY = widget.item['imageAlignmentY'] is num ? (widget.item['imageAlignmentY'] as num).toDouble() : double.tryParse((widget.item['imageAlignmentY'] ?? '').toString()) ?? 0.0;

    _imageAlignmentY = rawImageAlignmentY.clamp(-1.0, 1.0);

    final priceRaw = widget.item['price'];

    _price = priceRaw is num ? priceRaw.toInt() : int.tryParse(priceRaw?.toString() ?? '') ?? (double.tryParse(priceRaw?.toString() ?? '')?.round() ?? 0);

    final servingsRaw = widget.item['servings'] ?? widget.item['availableServings'] ?? 0;

    _availableServings = servingsRaw is num ? servingsRaw.toInt() : int.tryParse(servingsRaw?.toString() ?? '') ?? 0;

    _isUnlimitedServings = _availableServings == -1;

    _selectedInventoryItemId = (widget.item['inventoryItemId'] ?? '').toString();

    _selectedRecipeId = (widget.item['recipeId'] ?? '').toString();

    final rawCats = widget.item['categories'];

    if (rawCats is List) {

      _selectedCategories..clear()..addAll(rawCats.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));

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



  Widget _sectionTitle(BuildContext context, IconData icon, String title) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 12, top: 4),

      child: Row(children: [

        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),

        const SizedBox(width: 8),

        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),

      ]),

    );

  }



  InputDecoration _dec(String label, {Widget? prefixIcon, String? helper}) => InputDecoration(

        labelText: label, helperText: helper, prefixIcon: prefixIcon,

        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))), isDense: true,

      );



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final recipe = _selectedRecipe;

    final batchYield = recipe == null ? null : ((recipe['batchYield'] ?? recipe['baseServings']) as num?)?.toDouble();

    final batchCost = (recipe?['batchCost'] as num?)?.toDouble();

    final costPerServing = (recipe?['costPerServing'] as num?)?.toDouble();

    final recipeLinked = _selectedRecipeId.trim().isNotEmpty;

    final margin = (costPerServing != null && _price > 0) ? (_price - costPerServing) : null;



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

                Icon(Icons.edit_note_rounded, color: theme.colorScheme.onPrimaryContainer),

                const SizedBox(width: 12),

                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  Text('Edit Menu Item', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),

                  Text('Link a recipe to use ingredient-based costing.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),

                ])),

                IconButton(icon: Icon(Icons.close, color: theme.colorScheme.onPrimaryContainer), onPressed: () => Navigator.of(context).pop()),

              ]),

            ),

            Flexible(

              child: Form(

                key: _formKey,

                child: SingleChildScrollView(

                  padding: const EdgeInsets.all(20),

                  child: LayoutBuilder(builder: (context, constraints) {

                    final twoCol = constraints.maxWidth >= 560;

                    final half = twoCol ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;

                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      _sectionTitle(context, Icons.info_outline, 'Basic Information'),

                      TextFormField(controller: _nameController, decoration: _dec('Dish Name *', prefixIcon: const Icon(Icons.restaurant_menu_rounded)), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),

                      const SizedBox(height: 16),

                      Wrap(spacing: 16, runSpacing: 16, children: [

                        SizedBox(width: half, child: DropdownButtonFormField<String>(value: _selectedInventoryItemId, decoration: _dec('Inventory Link (optional)', prefixIcon: const Icon(Icons.inventory_2_outlined)), isExpanded: true, items: [

                          const DropdownMenuItem(value: '', child: Text('None')),

                          ...widget.inventoryItems.map((inv) {

                            final id = (inv['id'] ?? '').toString();

                            final name = (inv['name'] ?? '').toString();

                            final unit = (inv['unit'] ?? '').toString();

                            final stockRaw = inv['currentStock'];

                            final stock = stockRaw is num ? stockRaw.toInt() : int.tryParse((stockRaw ?? '').toString()) ?? 0;

                            final label = unit.isEmpty ? '$name ($stock)' : '$name ($stock $unit)';

                            return DropdownMenuItem(value: id, child: Text(label.trim().isEmpty ? 'Unnamed item' : label, overflow: TextOverflow.ellipsis));

                          }),

                        ], onChanged: (v) => setState(() => _selectedInventoryItemId = v ?? ''))),

                        SizedBox(width: half, child: DropdownButtonFormField<String>(value: _selectedRecipeId, decoration: _dec('Recipe / Costing (optional)', prefixIcon: const Icon(Icons.menu_book_outlined), helper: recipeLinked ? 'Cost per serving synced from recipe' : 'Select to calculate ingredient-based cost'), isExpanded: true, items: [

                          const DropdownMenuItem(value: '', child: Text('None')),

                          ..._recipes.map((r) => DropdownMenuItem(value: (r['id'] ?? '').toString(), child: Text((r['name'] ?? 'Unnamed recipe').toString(), overflow: TextOverflow.ellipsis))),

                        ], onChanged: _loadingRecipes ? null : (v) => setState(() => _selectedRecipeId = v ?? ''))),

                      ]),

                      if (_loadingRecipes) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),

                      if (recipeLinked) ...[

                        const SizedBox(height: 12),

                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                          Text('Costing Preview', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),

                          const SizedBox(height: 6),

                          Text('Batch yield: ${batchYield?.toStringAsFixed(batchYield % 1 == 0 ? 0 : 2) ?? '—'}  •  Batch cost: ${batchCost != null ? '₱${batchCost.toStringAsFixed(2)}' : '—'}  •  Cost/serving: ${costPerServing != null ? '₱${costPerServing.toStringAsFixed(2)}' : '—'}', style: theme.textTheme.bodySmall),

                          if (margin != null) Text('Estimated margin per serving (at current price): ₱${margin.toStringAsFixed(2)}', style: theme.textTheme.bodySmall?.copyWith(color: margin >= 0 ? Colors.green.shade700 : theme.colorScheme.error, fontWeight: FontWeight.w600)),

                        ])),

                      ],

                      const SizedBox(height: 16),

                      _sectionTitle(context, Icons.category_outlined, 'Category *'),

                      FormField<Set<String>>(initialValue: _selectedCategories, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null, builder: (state) => InputDecorator(decoration: InputDecoration(labelText: 'Select categories', border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))), errorText: state.errorText, isDense: true), child: Wrap(spacing: 8, runSpacing: 8, children: _categoryOptions.map((c) {

                        final selected = state.value?.contains(c) ?? false;

                        return FilterChip(label: Text(c, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)), selected: selected, onSelected: (_) {

                          setState(() { if (_selectedCategories.contains(c)) { _selectedCategories.remove(c); } else { _selectedCategories.add(c); } });

                          state.didChange(_selectedCategories);

                        });

                      }).toList()))),

                      const SizedBox(height: 16),

                      Wrap(spacing: 16, runSpacing: 16, children: [

                        SizedBox(width: half, child: _IntStepperTextFormField(labelText: 'Price (₱) *', value: _price, min: 0, onChanged: (v) => setState(() => _price = v), validator: (v) => v <= 0 ? 'Required' : null, prefixIcon: Icons.payments_rounded)),

                        SizedBox(width: half, child: _IntStepperTextFormField(labelText: _isUnlimitedServings ? 'Servings (unlimited)' : 'Available Servings', value: _isUnlimitedServings ? 0 : _availableServings, min: 0, enabled: !_isUnlimitedServings && _selectedInventoryItemId.trim().isEmpty, onChanged: (v) => setState(() => _availableServings = v), prefixIcon: Icons.inventory_rounded)),

                      ]),

                      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Unlimited servings'), value: _isUnlimitedServings, onChanged: _selectedInventoryItemId.trim().isNotEmpty ? null : (v) => setState(() => _isUnlimitedServings = v)),

                      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Available on menu'), value: _manualIsAvailable, onChanged: (v) => setState(() => _manualIsAvailable = v)),

                      const SizedBox(height: 8),

                      TextFormField(controller: _descriptionController, decoration: _dec('Description (optional)', prefixIcon: const Icon(Icons.description_rounded)), maxLines: 3),

                      const SizedBox(height: 20),

                      _sectionTitle(context, Icons.image_outlined, 'Image (optional)'),

                      TextFormField(controller: _imageUrlController, decoration: _dec('Dish Image URL', prefixIcon: const Icon(Icons.link_rounded)).copyWith(suffixIcon: _imageUrlController.text.trim().isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _imageUrlController.clear(); _imageAlignmentX = 0; _imageAlignmentY = 0; }))), keyboardType: TextInputType.url, onChanged: (_) => setState(() {})),

                      const SizedBox(height: 12),

                      _MenuItemPreviewCard(name: _nameController.text.trim().isEmpty ? 'Sample Dish' : _nameController.text.trim(), price: _price.toDouble(), imageUrl: _imageUrlController.text.trim(), imageAlignmentX: _imageAlignmentX, imageAlignmentY: _imageAlignmentY),

                      if (_imageUrlController.text.trim().isNotEmpty) ...[

                        const SizedBox(height: 12),

                        Text('Horizontal focus', style: theme.textTheme.bodySmall),

                        Slider(value: _imageAlignmentX, min: -1, max: 1, divisions: 20, onChanged: (v) => setState(() => _imageAlignmentX = v)),

                        Text('Vertical focus', style: theme.textTheme.bodySmall),

                        Slider(value: _imageAlignmentY, min: -1, max: 1, divisions: 20, onChanged: (v) => setState(() => _imageAlignmentY = v)),

                      ],

                    ]);

                  }),

                ),

              ),

            ),

            const Divider(height: 1),

            Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [

              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),

              const SizedBox(width: 12),

              ElevatedButton(onPressed: _isLoading ? null : _updateItem, child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes')),

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

      var servingsToSave = _availableServings;

      final invId = _selectedInventoryItemId.trim();

      if (invId.isNotEmpty) {

        final inv = widget.inventoryItems.cast<Map<String, dynamic>>().firstWhere((e) => (e['id'] ?? '').toString() == invId, orElse: () => const {});

        final stockRaw = inv['currentStock'];

        servingsToSave = stockRaw is num ? stockRaw.toInt() : int.tryParse((stockRaw ?? '').toString()) ?? 0;

      }

      final recipeId = _selectedRecipeId.trim();

      final result = await ApiService.updateMenuItem(

        widget.item['id'],

        name: _nameController.text.trim(),

        category: _selectedCategories.isEmpty ? '' : _selectedCategories.first,

        categories: _selectedCategories.toList()..sort(),

        price: _price,

        inventoryItemId: invId,

        recipeId: recipeId,

        availableServings: _isUnlimitedServings ? -1 : servingsToSave,

        isAvailable: _manualIsAvailable,

        description: _descriptionController.text,

        imageUrl: _imageUrlController.text.trim(),

        imageAlignmentX: _imageAlignmentX,

        imageAlignmentY: _imageAlignmentY,

      );

      if (mounted) {

        final updated = result['data'] as Map<String, dynamic>? ?? <String, dynamic>{};

        Navigator.of(context).pop(updated);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menu item updated successfully')));

      }

    } catch (e) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));

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

                      theme.colorScheme.onSurface.withOpacity(0.0),

                      theme.colorScheme.onSurface.withOpacity(0.65),

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

    this.enabled = true,

    this.validator,

    this.prefixIcon,

  });



  final String labelText;

  final int value;

  final int min;

  final ValueChanged<int> onChanged;

  final bool enabled;

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

            border: const OutlineInputBorder(

              borderRadius: BorderRadius.all(Radius.circular(12)),

            ),

            errorText: state.errorText,

            prefixIcon: Row(

              mainAxisSize: MainAxisSize.min,

              children: [

                if (widget.prefixIcon != null) ...[

                  const SizedBox(width: 12),

                  Icon(widget.prefixIcon, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),

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

