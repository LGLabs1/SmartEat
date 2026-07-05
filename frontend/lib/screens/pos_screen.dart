import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/ai_assistant_provider.dart';
import '../widgets/skeleton_loaders.dart';
import '../utils/haptic_feedback.dart';
import '../utils/error_messages.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({
    Key? key,
    this.initialAddToExistingOrder = false,
    this.initialOrderId = '',
    this.showAppBar = true,
  }) : super(key: key);

  final bool initialAddToExistingOrder;
  final String initialOrderId;
  final bool showAppBar;

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  List<Map<String, dynamic>> _cartItems = [];
  List<Map<String, dynamic>> _menuItems = [];
  bool _isLoading = false;
  double _totalAmount = 0.0;
  bool _isAdmin = false;
  String? _lastRoleUid;
  bool _addToExistingOrder = false;
  String _targetPendingOrderId = '';
  String _newOrderTempId = '';
  List<Map<String, dynamic>> _pendingOrders = const [];
  final Map<String, int> _baselineQtyByMenuId = {};
  bool _isPrefilling = false;
  String _selectedCategory = 'All';
  List<String> _pinnedItemIds = [];

  void _openCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: _CartPanel(
              cartItems: _cartItems,
              totalAmount: _totalAmount,
              isLoading: _isLoading,
              isAddToExistingOrder: _addToExistingOrder,
              orderId:
                  _addToExistingOrder ? _targetPendingOrderId : _newOrderTempId,
              isNewOrder: !_addToExistingOrder,
              baselineQtyByMenuId: _baselineQtyByMenuId,
              onQuantityChanged: (index, qty) => _updateQuantity(index, qty),
              onRemove: (index) => _removeFromCart(index),
              onCreateOrder: _createOrder,
              actionLabel: _addToExistingOrder ? 'Add Items' : 'Create Order',
            ),
          ),
        );
      },
    );
  }

  late Stream<List<Map<String, dynamic>>> _menuStream;

  @override
  void initState() {
    super.initState();
    _menuStream = ApiService.getMenuItemsStream();
    _addToExistingOrder = widget.initialAddToExistingOrder;
    _targetPendingOrderId = widget.initialOrderId.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRole();
      context.read<AIAssistantProvider>().setActivePage('orders');
      if (_addToExistingOrder && _targetPendingOrderId.isNotEmpty) {
        _prefillPendingOrderIntoCart(_targetPendingOrderId);
      }
    });
  }

  String _shortOrderId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 6 ? trimmed : trimmed.substring(0, 6);
  }

  String _generateOrderId() {
    // Generate a Firestore-compatible document ID (20 characters)
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _prefillPendingOrderIntoCart(String orderId) async {
    if (_isPrefilling) return;
    final trimmed = orderId.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isPrefilling = true;
    });

    try {
      final res = await ApiService.getOrderById(trimmed);
      final order = Map<String, dynamic>.from(res['data'] ?? const {});
      final itemsRaw = order['items'];
      final items = itemsRaw is List ? itemsRaw : const [];

      final nextCart = <Map<String, dynamic>>[];
      final nextBaseline = <String, int>{};

      int asInt(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse((v ?? '').toString()) ?? 0;
      }

      double asDouble(dynamic v) {
        if (v is num) return v.toDouble();
        return double.tryParse((v ?? '').toString()) ?? 0.0;
      }

      for (final raw in items) {
        if (raw is! Map) continue;
        final it = Map<String, dynamic>.from(raw);
        final menuItemId = (it['menuItemId'] ?? '').toString().trim();
        if (menuItemId.isEmpty) continue;
        final qty = asInt(it['quantity']);
        if (qty <= 0) continue;
        final price = asDouble(it['price']);

        final menu = _menuItems.firstWhere(
          (m) => (m['id'] ?? '').toString().trim() == menuItemId,
          orElse: () => const {},
        );

        final name = (menu is Map && menu.isNotEmpty)
            ? (menu['name'] ?? '').toString()
            : (it['name'] ?? '').toString();

        nextCart.add({
          ...(menu is Map && menu.isNotEmpty
              ? Map<String, dynamic>.from(menu)
              : {
                  'id': menuItemId,
                  'name': name,
                  'price': price,
                }),
          'id': menuItemId,
          'name': name,
          'price': price,
          'quantity': qty,
          'subtotal': price * qty,
        });

        nextBaseline[menuItemId] = qty;
      }

      if (!mounted) return;
      setState(() {
        _cartItems = nextCart;
        _baselineQtyByMenuId
          ..clear()
          ..addAll(nextBaseline);
        _calculateTotal();
        _isPrefilling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPrefilling = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load order items: $e')),
      );
    }
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

  Future<void> _loadMenuItems() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        ApiService.getMenuItems(),
        ApiService.getInventoryItems(),
      ]);

      final menuRes = results[0];
      final invRes = results[1];

      final inventoryItems =
          List<Map<String, dynamic>>.from(invRes['data'] ?? const []);
      final inventoryById = <String, Map<String, dynamic>>{
        for (final inv in inventoryItems) (inv['id'] ?? '').toString(): inv,
      };

      final rawMenuItems =
          List<Map<String, dynamic>>.from(menuRes['data'] ?? const []);

      // Load pinned items
      _loadPinnedItems();

      if (_isAdmin) {
        final menuByInventoryId = <String, Map<String, dynamic>>{};
        for (final m in rawMenuItems) {
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

          final selling = sellingPriceByInventoryId[invId] ?? 0;
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
          rawMenuItems
            ..clear()
            ..addAll(
                List<Map<String, dynamic>>.from(refreshed['data'] ?? const []));
        }
      }

      final normalizedMenuItems = rawMenuItems.map((item) {
        if (item['price'] is String) {
          item['price'] = double.tryParse(item['price']) ?? 0.0;
        }

        final invId = (item['inventoryItemId'] ?? '').toString().trim();
        if (invId.isNotEmpty) {
          final inv = inventoryById[invId];
          if (inv != null) {
            final stockRaw = inv['currentStock'];
            final stock = stockRaw is num
                ? stockRaw.toInt()
                : int.tryParse((stockRaw ?? '').toString()) ?? 0;
            item['availableServings'] = stock;
            final manual = item['isAvailable'];
            final manualOff = manual is bool && manual == false;
            item['isAvailable'] = stock > 0 && !manualOff;
          }
        }
        return item;
      }).toList();

      setState(() {
        _menuItems = normalizedMenuItems;
        final cats = _availableCategories();
        if (!cats.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ErrorMessageHelper.showSnackBar(
          context,
          e,
          operationContext: 'menu',
          onAction: _loadMenuItems,
          actionLabel: 'Retry',
        );
      }
    }
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
        setState(() {
          _pinnedItemIds = pinned.map((e) => e.toString()).toList();
        });
      }
    } catch (_) {
      // Silently fail - pinned items are not critical
    }
  }

  bool _isPinned(String itemId) {
    return _pinnedItemIds.contains(itemId);
  }

  Future<void> _loadPendingOrders() async {
    try {
      final res = await ApiService.getPendingOrders(limit: 25);
      final orders = List<Map<String, dynamic>>.from(res['data'] ?? const []);
      if (!mounted) return;
      setState(() {
        _pendingOrders = orders;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load pending orders: $e')),
      );
    }
  }

  Future<void> _pickPendingOrder() async {
    await _loadPendingOrders();
    if (!mounted) return;

    final selected = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Pending Order'),
          content: SizedBox(
            width: 520,
            child: _pendingOrders.isEmpty
                ? const Text('No pending orders found.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _pendingOrders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final o = _pendingOrders[index];
                      final id = (o['id'] ?? '').toString();
                      final total =
                          (o['totalAmount'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        title: Text(
                          id.isEmpty
                              ? 'Order'
                              : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                        ),
                        subtitle: Text('₱${total.toStringAsFixed(2)}'),
                        onTap: () => Navigator.of(context).pop(o),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selected == null) return;
    final id = (selected['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    setState(() {
      _targetPendingOrderId = id;
    });

    if (_addToExistingOrder && _targetPendingOrderId.isNotEmpty) {
      await _prefillPendingOrderIntoCart(_targetPendingOrderId);
    }
  }

  int _qtyInCart(String menuId) {
    final idx = _cartItems.indexWhere(
      (e) => (e['id'] ?? '').toString().trim() == menuId,
    );
    if (idx < 0) return 0;
    final q = _cartItems[idx]['quantity'];
    if (q is int) return q;
    if (q is num) return q.toInt();
    return int.tryParse((q ?? '').toString()) ?? 0;
  }

  void _setQtyForItem(Map<String, dynamic> item, int nextQty) {
    final menuId = (item['id'] ?? '').toString().trim();
    if (menuId.isEmpty) return;

    final inventoryItemId = (item['inventoryItemId'] ?? '').toString().trim();
    final isInventoryLinked = inventoryItemId.isNotEmpty;
    final servingsRaw = item['servings'] ?? item['availableServings'] ?? 0;
    final servings = servingsRaw is num
        ? servingsRaw.toInt()
        : int.tryParse((servingsRaw ?? '').toString()) ?? 0;
    final isUnlimited = servings == -1 || !isInventoryLinked;
    final manualAvailability = item['isAvailable'];
    final isAvailable = manualAvailability is bool
        ? manualAvailability
        : (isUnlimited || servings > 0);

    if (!isAvailable && nextQty > 0) {
      HapticHelper.error();
      return;
    }

    // For unlimited items, don't cap quantity; for limited items, cap at servings
    final cappedQty =
        isUnlimited ? nextQty : (servings > 0 ? nextQty.clamp(0, servings) : 0);
    final exceeded = !isUnlimited && nextQty > cappedQty;

    setState(() {
      final idx = _cartItems.indexWhere(
        (e) => (e['id'] ?? '').toString().trim() == menuId,
      );

      if (cappedQty <= 0) {
        if (idx >= 0) {
          _cartItems.removeAt(idx);
          HapticHelper.removeFromCart();
        }
        _calculateTotal();
        if (_cartItems.isEmpty) {
          _newOrderTempId = '';
        }
        return;
      }

      // Generate real order ID for new orders when first item is added
      if (!_addToExistingOrder && _newOrderTempId.isEmpty) {
        _newOrderTempId = _generateOrderId();
      }

      final priceRaw = item['price'];
      final price = priceRaw is num
          ? priceRaw.toDouble()
          : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;

      final wasEmpty = idx < 0;
      if (idx >= 0) {
        _cartItems[idx]['quantity'] = cappedQty;
        _cartItems[idx]['subtotal'] = price * cappedQty;
      } else {
        _cartItems.add({
          ...item,
          'id': menuId,
          'quantity': cappedQty,
          'subtotal': price * cappedQty,
        });
      }
      _calculateTotal();

      // Haptic feedback for adding to cart
      if (wasEmpty || nextQty > 0) {
        HapticHelper.addToCart();
      }
    });

    if (exceeded && mounted) {
      HapticHelper.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only $servings left in stock.')),
      );
    }
  }

  List<String> _availableCategories() {
    final set = <String>{};
    // Add 'Pinned' if there are pinned items
    if (_pinnedItemIds.isNotEmpty) {
      set.add('📌 Pinned');
    }
    for (final it in _menuItems) {
      final c = (it['category'] ?? '').toString().trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()
      ..sort((a, b) {
        // Always show Pinned first, then alphabetically
        if (a == '📌 Pinned') return -1;
        if (b == '📌 Pinned') return 1;
        return a.compareTo(b);
      });
    return ['All', ...list];
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

  Widget _buildMenuByCategory({
    required List<Map<String, dynamic>> items,
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    Widget header(String title) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Divider(
                color: theme.colorScheme.outline,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};

    // First, add pinned items as a separate group if showing All
    final pinnedItems = items
        .where((item) => _isPinned((item['id'] ?? '').toString()))
        .toList();
    if (pinnedItems.isNotEmpty) {
      grouped['📌 Pinned'] = pinnedItems;
    }

    // Then group by category (including pinned items in their original category too)
    for (final item in items) {
      final cats = _extractCategories(item);
      final key = (cats.isNotEmpty
              ? cats.first
              : (item['category'] ?? '').toString().trim())
          .trim();
      final normalized = key.isEmpty ? 'Uncategorized' : key;
      // Add to category group (pinned items appear in both)
      grouped.putIfAbsent(normalized, () => []).add(item);
    }

    final keys = grouped.keys.toList()
      ..sort((a, b) {
        // Always show Pinned first
        if (a == '📌 Pinned') return -1;
        if (b == '📌 Pinned') return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: keys.length,
      itemBuilder: (context, sectionIndex) {
        final key = keys[sectionIndex];
        final sectionItems = grouped[key] ?? const [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(key),
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: sectionItems.length,
              itemBuilder: (context, index) {
                final item = sectionItems[index];
                final id = (item['id'] ?? '').toString().trim();
                final qty = id.isEmpty ? 0 : _qtyInCart(id);
                return _MenuItemCard(
                  item: item,
                  quantityInCart: qty,
                  onIncrement: () => _setQtyForItem(item, qty + 1),
                  onDecrement: () => _setQtyForItem(item, qty - 1),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryChips() {
    final cats = _availableCategories();
    if (cats.length <= 1) return const SizedBox(height: 0);

    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = cats[index];
          final selected = _selectedCategory == cat;
          return ChoiceChip(
            label: Text(
              cat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedCategory = cat;
              });
            },
            selectedColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(color: theme.colorScheme.outline),
          );
        },
      ),
    );
  }

  void _updateQuantity(int index, int quantity) {
    if (quantity <= 0) {
      _removeFromCart(index);
      return;
    }

    setState(() {
      _cartItems[index]['quantity'] = quantity;
      _cartItems[index]['subtotal'] = quantity * _cartItems[index]['price'];
      _calculateTotal();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cartItems.removeAt(index);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    _totalAmount = _cartItems.fold(
      0.0,
      (sum, item) => sum + (item['subtotal'] as double),
    );
  }

  Future<void> _createOrder() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cart is empty', style: Theme.of(context).textTheme.bodyMedium),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Hard guard: do not allow cart qty to exceed available servings, or allow
    // ordering items manually marked unavailable.
    final invalid = <String>[];
    for (final cart in _cartItems) {
      final menuId = (cart['id'] ?? '').toString().trim();
      if (menuId.isEmpty) continue;
      final menu = _menuItems.firstWhere(
        (m) => (m['id'] ?? '').toString().trim() == menuId,
        orElse: () => const <String, dynamic>{},
      );
      if (menu.isEmpty) continue;

      final inventoryItemId = (menu['inventoryItemId'] ?? '').toString().trim();
      final isInventoryLinked = inventoryItemId.isNotEmpty;
      final servingsRaw = menu['servings'] ?? menu['availableServings'];
      // Treat missing/invalid servings as unlimited (-1), or if not linked to inventory
      final servings = servingsRaw is num
          ? servingsRaw.toInt()
          : (servingsRaw == null
              ? -1
              : (int.tryParse(servingsRaw.toString()) ?? -1));
      final isUnlimited = servings == -1 || !isInventoryLinked;
      final manualAvailability = menu['isAvailable'];
      final isAvailable =
          manualAvailability is bool ? manualAvailability : servings > 0;

      final qtyRaw = cart['quantity'];
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse((qtyRaw ?? '').toString()) ?? 0;

      if (!isAvailable ||
          (!isUnlimited && servings <= 0) ||
          (!isUnlimited && qty > servings)) {
        invalid.add((menu['name'] ?? cart['name'] ?? 'Item').toString());
      }
    }

    if (invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Some items are unavailable or exceed stock: ${invalid.take(3).join(', ')}',
          ),
        ),
      );
      return;
    }

    if (_addToExistingOrder && _targetPendingOrderId.trim().isEmpty) {
      await _pickPendingOrder();
      if (!mounted) return;
      if (_targetPendingOrderId.trim().isEmpty) {
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> orderItems;
      if (_addToExistingOrder) {
        final deltas = <Map<String, dynamic>>[];
        for (final item in _cartItems) {
          final menuId = (item['id'] ?? '').toString().trim();
          if (menuId.isEmpty) continue;
          final qtyRaw = item['quantity'];
          final qty = qtyRaw is num
              ? qtyRaw.toInt()
              : int.tryParse((qtyRaw ?? '').toString()) ?? 0;
          final baseline = _baselineQtyByMenuId[menuId] ?? 0;
          final deltaQty = qty - baseline;
          if (deltaQty <= 0) continue;
          final price = item['price'];
          final priceNum = price is num
              ? price.toDouble()
              : double.tryParse((price ?? '').toString()) ?? 0.0;
          deltas.add({
            'menuItemId': menuId,
            'name': item['name'],
            'quantity': deltaQty,
            'price': priceNum,
            'subtotal': priceNum * deltaQty,
          });
        }
        if (deltas.isEmpty) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No new items to add.')),
          );
          return;
        }
        orderItems = deltas;
      } else {
        orderItems = _cartItems
            .map((item) => {
                  'menuItemId': item['id'],
                  'name': item['name'],
                  'quantity': item['quantity'],
                  'price': item['price'],
                  'subtotal': item['subtotal'],
                })
            .toList();
      }

      if (_addToExistingOrder) {
        await ApiService.addItemsToPendingOrder(
          orderId: _targetPendingOrderId,
          items: orderItems,
        );
      } else {
        await ApiService.createOrder(
          items: orderItems,
          paymentMethod: 'cash',
          orderId: _newOrderTempId.isNotEmpty ? _newOrderTempId : null,
        );
      }

      if (mounted) {
        final theme = Theme.of(context);
        setState(() {
          _cartItems.clear();
          _baselineQtyByMenuId.clear();
          _totalAmount = 0.0;
          _isLoading = false;
          _newOrderTempId = '';
          if (!_addToExistingOrder) {
            _targetPendingOrderId = '';
          }
        });

        _loadMenuItems();
        _loadPendingOrders();

        // Success haptic feedback
        HapticHelper.orderComplete();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.onSecondary),
                const SizedBox(width: 8),
                Text(
                  _addToExistingOrder
                      ? 'Items added to order!'
                      : 'Order created successfully!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondary,
                  ),
                ),
              ],
            ),
            backgroundColor: theme.colorScheme.secondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ErrorMessageHelper.showSnackBar(
          context,
          e,
          operationContext: 'order',
          onAction: _createOrder,
          actionLabel: 'Retry',
        );
      }
    }
  }

  List<Map<String, dynamic>> _processMenuItems(
    List<Map<String, dynamic>> menuItems,
    List<Map<String, dynamic>> inventoryItems,
  ) {
    final inventoryById = <String, Map<String, dynamic>>{
      for (final inv in inventoryItems) (inv['id'] ?? '').toString(): inv,
    };

    return menuItems.map((item) {
      if (item['price'] is String) {
        item['price'] = double.tryParse(item['price']) ?? 0.0;
      }

      final invId = (item['inventoryItemId'] ?? '').toString().trim();
      if (invId.isNotEmpty) {
        final inv = inventoryById[invId];
        if (inv != null) {
          final stockRaw = inv['currentStock'];
          final stock = stockRaw is num
              ? stockRaw.toInt()
              : int.tryParse((stockRaw ?? '').toString()) ?? 0;
          item['availableServings'] = stock;
          final manual = item['isAvailable'];
          final manualOff = manual is bool && manual == false;
          item['isAvailable'] = stock > 0 && !manualOff;
        }
      }
      return item;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _menuStream,
      builder: (context, menuSnapshot) {
        return FutureBuilder<Map<String, dynamic>>(
          future: ApiService.getInventoryItems(),
          builder: (context, inventorySnapshot) {
            final isLoading =
                !menuSnapshot.hasData || !inventorySnapshot.hasData;
            final menuItems = menuSnapshot.data ?? [];
            final inventoryItems = inventorySnapshot.hasData
                ? List<Map<String, dynamic>>.from(
                    inventorySnapshot.data!['data'] ?? const [])
                : <Map<String, dynamic>>[];

            _menuItems = _processMenuItems(menuItems, inventoryItems);

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isCompact = width < 780;
                final isShortHeight = constraints.maxHeight < 420;
                final crossAxisCount = width < 520
                    ? 2
                    : width >= 1100
                        ? 4
                        : width >= 820
                            ? 3
                            : 2;
                final childAspectRatio = width < 520
                    ? (isShortHeight ? 0.68 : 0.72)
                    : crossAxisCount == 2
                        ? (isShortHeight ? 0.72 : 0.76)
                        : crossAxisCount == 3
                            ? (isShortHeight ? 0.78 : 0.82)
                            : (isShortHeight ? 0.86 : 0.90);

                final filteredMenuItems = _selectedCategory == 'All'
                    ? _menuItems
                    : _selectedCategory == '📌 Pinned'
                        ? _menuItems
                            .where((m) => _isPinned((m['id'] ?? '').toString()))
                            .toList()
                        : _menuItems
                            .where((m) =>
                                (m['category'] ?? '').toString().trim() ==
                                _selectedCategory)
                            .toList();

                return Scaffold(
                  appBar: widget.showAppBar
                      ? AppBar(
                          title: Text(
                            _addToExistingOrder &&
                                    _targetPendingOrderId.trim().isNotEmpty
                                ? 'Add Items — Order #${_shortOrderId(_targetPendingOrderId)}'
                                : 'Point of Sale',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          actions: [
                            if (isCompact)
                              IconButton(
                                tooltip: _addToExistingOrder
                                    ? 'Add to Order'
                                    : 'New Order',
                                onPressed: () async {
                                  if (_isLoading) return;
                                  final next = !_addToExistingOrder;
                                  setState(() {
                                    _addToExistingOrder = next;
                                    if (!next) {
                                      _targetPendingOrderId = '';
                                      _baselineQtyByMenuId.clear();
                                    }
                                  });
                                  if (next) {
                                    await _pickPendingOrder();
                                    if (!mounted) return;
                                    if (_targetPendingOrderId.trim().isEmpty) {
                                      setState(() {
                                        _addToExistingOrder = false;
                                      });
                                    }
                                  }
                                },
                                icon: Icon(
                                  _addToExistingOrder
                                      ? Icons.playlist_add_check
                                      : Icons.playlist_add,
                                ),
                              )
                            else
                              TextButton.icon(
                                onPressed: () async {
                                  if (_isLoading) return;
                                  final next = !_addToExistingOrder;
                                  setState(() {
                                    _addToExistingOrder = next;
                                    if (!next) {
                                      _targetPendingOrderId = '';
                                      _baselineQtyByMenuId.clear();
                                    }
                                  });
                                  if (next) {
                                    await _pickPendingOrder();
                                    if (!mounted) return;
                                    if (_targetPendingOrderId.trim().isEmpty) {
                                      setState(() {
                                        _addToExistingOrder = false;
                                      });
                                    }
                                  }
                                },
                                icon: Icon(
                                  _addToExistingOrder
                                      ? Icons.playlist_add_check
                                      : Icons.playlist_add,
                                ),
                                label: Text(
                                  _addToExistingOrder
                                      ? 'Add to Order'
                                      : 'New Order',
                                ),
                              ),
                            if (isCompact)
                              IconButton(
                                tooltip: _cartItems.isEmpty
                                    ? 'Cart'
                                    : 'Cart (${_cartItems.length})',
                                onPressed: _openCartSheet,
                                icon: const Icon(Icons.shopping_cart_outlined),
                              ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loadMenuItems,
                            ),
                          ],
                        )
                      : null,
                  bottomNavigationBar: isCompact
                      ? SafeArea(
                          top: false,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 56),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border(
                                top: BorderSide(color: Theme.of(context).colorScheme.outline),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₱${_totalAmount.toStringAsFixed(2)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _cartItems.isEmpty
                                            ? 'No items'
                                            : '${_cartItems.length} item(s) in cart',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 36,
                                  child: FilledButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : (_cartItems.isEmpty
                                            ? _openCartSheet
                                            : (_addToExistingOrder
                                                ? _createOrder
                                                : _openCartSheet)),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor:
                                          Theme.of(context).colorScheme.onPrimary,
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(
                                      Icons.shopping_cart_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _cartItems.isEmpty
                                          ? 'View Cart'
                                          : _addToExistingOrder
                                              ? 'Add Items'
                                              : 'Checkout',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                  body: isCompact
                      ? Column(
                          children: [
                            _buildCategoryChips(),
                            Expanded(
                              child: isLoading
                                  ? const SkeletonPOS()
                                  : (_selectedCategory == 'All'
                                      ? _buildMenuByCategory(
                                          items: filteredMenuItems,
                                          crossAxisCount: crossAxisCount,
                                          childAspectRatio: childAspectRatio,
                                        )
                                      : GridView.builder(
                                          padding: const EdgeInsets.all(12),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: crossAxisCount,
                                            childAspectRatio: childAspectRatio,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                          ),
                                          itemCount: filteredMenuItems.length,
                                          itemBuilder: (context, index) {
                                            final item =
                                                filteredMenuItems[index];
                                            final id = (item['id'] ?? '')
                                                .toString()
                                                .trim();
                                            final qty =
                                                id.isEmpty ? 0 : _qtyInCart(id);
                                            return _MenuItemCard(
                                              item: item,
                                              quantityInCart: qty,
                                              onIncrement: () =>
                                                  _setQtyForItem(item, qty + 1),
                                              onDecrement: () =>
                                                  _setQtyForItem(item, qty - 1),
                                            );
                                          },
                                        )),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildCategoryChips(),
                                  Expanded(
                                    child: isLoading
                                        ? const SkeletonPOS()
                                        : (_selectedCategory == 'All'
                                            ? _buildMenuByCategory(
                                                items: filteredMenuItems,
                                                crossAxisCount: crossAxisCount,
                                                childAspectRatio:
                                                    childAspectRatio,
                                              )
                                            : GridView.builder(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                gridDelegate:
                                                    SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      crossAxisCount,
                                                  childAspectRatio:
                                                      childAspectRatio,
                                                  crossAxisSpacing: 12,
                                                  mainAxisSpacing: 12,
                                                ),
                                                itemCount:
                                                    filteredMenuItems.length,
                                                itemBuilder: (context, index) {
                                                  final item =
                                                      filteredMenuItems[index];
                                                  final id = (item['id'] ?? '')
                                                      .toString()
                                                      .trim();
                                                  final qty = id.isEmpty
                                                      ? 0
                                                      : _qtyInCart(id);
                                                  return _MenuItemCard(
                                                    item: item,
                                                    quantityInCart: qty,
                                                    onIncrement: () =>
                                                        _setQtyForItem(
                                                            item, qty + 1),
                                                    onDecrement: () =>
                                                        _setQtyForItem(
                                                            item, qty - 1),
                                                  );
                                                },
                                              )),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: width >= 1200 ? 420 : 360,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 16, 16, 16),
                                child: _CartPanel(
                                  cartItems: _cartItems,
                                  totalAmount: _totalAmount,
                                  isLoading: isLoading,
                                  isAddToExistingOrder: _addToExistingOrder,
                                  orderId: _addToExistingOrder
                                      ? _targetPendingOrderId
                                      : _newOrderTempId,
                                  isNewOrder: !_addToExistingOrder,
                                  baselineQtyByMenuId: _baselineQtyByMenuId,
                                  onQuantityChanged: (index, qty) =>
                                      _updateQuantity(index, qty),
                                  onRemove: (index) => _removeFromCart(index),
                                  onCreateOrder: _createOrder,
                                  actionLabel: _addToExistingOrder
                                      ? 'Add Items'
                                      : 'Create Order',
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    Key? key,
    required this.cartItems,
    required this.totalAmount,
    required this.isLoading,
    required this.isAddToExistingOrder,
    required this.orderId,
    required this.isNewOrder,
    required this.baselineQtyByMenuId,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onCreateOrder,
    this.actionLabel = 'Create Order',
  }) : super(key: key);

  final List<Map<String, dynamic>> cartItems;
  final double totalAmount;
  final bool isLoading;
  final bool isAddToExistingOrder;
  final String orderId;
  final bool isNewOrder;
  final Map<String, int> baselineQtyByMenuId;
  final void Function(int index, int quantity) onQuantityChanged;
  final void Function(int index) onRemove;
  final Future<void> Function() onCreateOrder;
  final String actionLabel;

  String _shortOrderId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 6 ? trimmed : trimmed.substring(0, 6);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$month/$day/$year $hour:$minute $period';
  }

  Widget _buildAddToOrderSections(BuildContext context) {
    final theme = Theme.of(context);
    final existingIndexes = <int>[];
    final newIndexes = <int>[];

    for (var i = 0; i < cartItems.length; i++) {
      final item = cartItems[i];
      final id = (item['id'] ?? '').toString().trim();
      final qty = _asInt(item['quantity']);
      final baseline = id.isEmpty ? 0 : (baselineQtyByMenuId[id] ?? 0);
      if (baseline > 0) {
        existingIndexes.add(i);
      }
      if (qty > baseline) {
        newIndexes.add(i);
      }
    }

    final rows = <_CartSectionRow>[];
    rows.add(const _CartSectionRow.header('Existing items'));
    if (existingIndexes.isEmpty) {
      rows.add(const _CartSectionRow.note('No existing items'));
    } else {
      for (final idx in existingIndexes) {
        rows.add(_CartSectionRow.existing(idx));
      }
    }

    rows.add(const _CartSectionRow.header('New items'));
    if (newIndexes.isEmpty) {
      rows.add(const _CartSectionRow.note('No new items added yet'));
    } else {
      for (final idx in newIndexes) {
        rows.add(_CartSectionRow.delta(idx));
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          Divider(color: Theme.of(context).dividerColor, height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        switch (row.type) {
          case _CartSectionRowType.header:
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Text(
                row.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            );
          case _CartSectionRowType.note:
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Text(
                row.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          case _CartSectionRowType.existing:
            final index = row.index;
            final cartItem = cartItems[index];
            final id = (cartItem['id'] ?? '').toString().trim();
            final baseline = id.isEmpty ? 0 : (baselineQtyByMenuId[id] ?? 0);
            final priceRaw = cartItem['price'];
            final price = priceRaw is num
                ? priceRaw.toDouble()
                : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;
            final baselineSubtotal = baseline * price;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                (cartItem['name'] ?? '').toString(),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                'Existing x$baseline',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Text(
                '₱${baselineSubtotal.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          case _CartSectionRowType.delta:
            final index = row.index;
            final cartItem = cartItems[index];
            final id = (cartItem['id'] ?? '').toString().trim();
            final qty = _asInt(cartItem['quantity']);
            final baseline = id.isEmpty ? 0 : (baselineQtyByMenuId[id] ?? 0);
            final delta = (qty - baseline).clamp(0, 1000000);

            final priceRaw = cartItem['price'];
            final price = priceRaw is num
                ? priceRaw.toDouble()
                : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;
            final deltaSubtotal = delta * price;

            void setDelta(int nextDelta) {
              final safe = nextDelta.clamp(0, 1000000);
              onQuantityChanged(index, baseline + safe);
            }

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                (cartItem['name'] ?? '').toString(),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                'New x$delta',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: delta <= 0 ? null : () => setDelta(delta - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                      color: theme.colorScheme.primary,
                    ),
                    Text(
                      delta.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setDelta(delta + 1),
                      icon: const Icon(Icons.add_circle_outline),
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${deltaSubtotal.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: delta <= 0 ? null : () => setDelta(0),
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceVariant,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cart',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatDateTime(DateTime.now()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if ((isAddToExistingOrder || isNewOrder) &&
                          orderId.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            isNewOrder
                                ? 'New Order #${_shortOrderId(orderId)}'
                                : 'Order #${_shortOrderId(orderId)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isNewOrder
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '₱${totalAmount.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: theme.dividerColor, height: 1),
          Expanded(
            child: cartItems.isEmpty
                ? Center(
                    child: Text(
                      'No items in cart',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : (isAddToExistingOrder
                    ? _buildAddToOrderSections(context)
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: cartItems.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: theme.dividerColor, height: 1),
                        itemBuilder: (context, index) {
                          final cartItem = cartItems[index];
                          return _CartItemTile(
                            cartItem: cartItem,
                            onQuantityChanged: (quantity) =>
                                onQuantityChanged(index, quantity),
                            onRemove: () => onRemove(index),
                          );
                        },
                      )),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: cartItems.isEmpty
                    ? null
                    : (isLoading ? null : onCreateOrder),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        actionLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CartSectionRowType { header, note, existing, delta }

class _CartSectionRow {
  const _CartSectionRow._(this.type, this.label, this.index);

  const _CartSectionRow.header(String label)
      : this._(_CartSectionRowType.header, label, -1);

  const _CartSectionRow.note(String label)
      : this._(_CartSectionRowType.note, label, -1);

  const _CartSectionRow.existing(int index)
      : this._(_CartSectionRowType.existing, '', index);

  const _CartSectionRow.delta(int index)
      : this._(_CartSectionRowType.delta, '', index);

  final _CartSectionRowType type;
  final String label;
  final int index;
}

class _MenuItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int quantityInCart;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _MenuItemCard({
    Key? key,
    required this.item,
    required this.quantityInCart,
    required this.onIncrement,
    required this.onDecrement,
  }) : super(key: key);

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    // Remove parentheses and their contents
    var cleaned = name.replaceAll(RegExp(r'\([^)]*\)'), '');
    // Remove special characters, keep only letters and spaces
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
    cleaned = cleaned.trim();
    final words =
        cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return words
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join('');
  }

  @override
  Widget build(BuildContext context) {
    final isShortHeight = MediaQuery.of(context).size.height < 420;
    final inventoryItemId = (item['inventoryItemId'] ?? '').toString().trim();
    final isInventoryLinked = inventoryItemId.isNotEmpty;
    final servingsRaw = item['servings'] ?? item['availableServings'] ?? 0;
    final servings = servingsRaw is num
        ? servingsRaw.toInt()
        : int.tryParse((servingsRaw ?? '').toString()) ?? 0;
    final isUnlimited = servings == -1 || !isInventoryLinked;
    final manualAvailability = item['isAvailable'];
    final isAvailable = manualAvailability is bool
        ? manualAvailability
        : (isUnlimited || servings > 0);
    final canAdd = isAvailable && (isUnlimited || servings > 0);

    final priceRaw = item['price'] ?? 0;
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse(priceRaw.toString()) ?? 0.0;

    final category = (item['category'] ?? '').toString();
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
    final name = (item['name'] ?? '').toString();
    final theme = Theme.of(context);
    final initials = _getInitials(name);

    return Card(
      elevation: 0,
      color: isAvailable
          ? theme.colorScheme.surfaceVariant
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(isShortHeight ? 8 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 0.92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    color: theme.colorScheme.surface,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl.isNotEmpty)
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment(imageAlignmentX, imageAlignmentY),
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: theme.colorScheme.surfaceVariant,
                              alignment: Alignment.center,
                              child: Text(
                                'Image not available',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: theme.colorScheme.surfaceVariant,
                            alignment: Alignment.center,
                            child: Text(
                              initials,
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.onSurface.withOpacity(0.0),
                                Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: isShortHeight ? 44 : 52,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.onSurface.withOpacity(0.08),
                                  theme.colorScheme.onSurface.withOpacity(0.75),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: double.infinity,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: _MarqueeText(
                                        text: name,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ) ?? TextStyle(
                                          color: theme.colorScheme.onPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₱${price.toStringAsFixed(2)}',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.w900,
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
              ),
            ),
            SizedBox(height: isShortHeight ? 8 : 10),
            SizedBox(
              width: double.infinity,
              child: quantityInCart > 0
                  ? Container(
                      height: isShortHeight ? 28 : 30,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onPressed: onDecrement,
                            icon: const Icon(Icons.remove),
                          ),
                          Text(
                            quantityInCart.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onPressed: canAdd ? onIncrement : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    )
                  : isAvailable
                      ? SizedBox(
                          height: isShortHeight ? 28 : 30,
                          child: FilledButton(
                            onPressed: canAdd ? onIncrement : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Add to cart',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          height: isShortHeight ? 28 : 30,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withOpacity(0.16),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Unavailable',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double velocity;
  final double gap;

  const _MarqueeText({
    Key? key,
    required this.text,
    required this.style,
    this.velocity = 40,
    this.gap = 24,
  }) : super(key: key);

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _scrollWidth = 0;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateScroll(double textWidth, double maxWidth) {
    final needsScroll = textWidth > maxWidth;
    if (!needsScroll) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      if (_needsScroll) {
        setState(() {
          _needsScroll = false;
        });
      }
      return;
    }

    final targetWidth = textWidth + widget.gap;
    if (_scrollWidth == targetWidth && _needsScroll) return;

    _scrollWidth = targetWidth;
    _needsScroll = true;
    _controller.duration = Duration(
      milliseconds:
          (_scrollWidth / widget.velocity * 1000).clamp(2500, 15000).toInt(),
    );
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final needsScroll = textPainter.width > constraints.maxWidth;
        final textWidth = textPainter.width;
        final targetWidth = textWidth + widget.gap;

        if (needsScroll) {
          if (_scrollWidth != targetWidth || !_needsScroll) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _scrollWidth = targetWidth;
                _needsScroll = true;
                _controller.duration = Duration(
                  milliseconds:
                      (_scrollWidth / widget.velocity * 1000).clamp(2500, 15000).toInt(),
                );
                _controller.repeat();
              });
            });
          }
        } else if (_needsScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _needsScroll = false;
              _controller.stop();
            });
          });
        }

        if (!needsScroll) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final offset = _controller.value * targetWidth;
                  return Transform.translate(
                    offset: Offset(-offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: textWidth,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    SizedBox(width: widget.gap),
                    SizedBox(
                      width: textWidth,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final Map<String, dynamic> cartItem;
  final Function(int) onQuantityChanged;
  final VoidCallback onRemove;

  const _CartItemTile({
    Key? key,
    required this.cartItem,
    required this.onQuantityChanged,
    required this.onRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qty = (cartItem['quantity'] as int?) ??
        int.tryParse((cartItem['quantity'] ?? '').toString()) ??
        1;
    final price = (cartItem['price'] is num)
        ? (cartItem['price'] as num).toDouble()
        : double.tryParse((cartItem['price'] ?? '').toString()) ?? 0.0;
    final subtotal = (cartItem['subtotal'] is num)
        ? (cartItem['subtotal'] as num).toDouble()
        : double.tryParse((cartItem['subtotal'] ?? '').toString()) ??
            (qty * price);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(
        cartItem['name'] ?? '',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        '₱${subtotal.toStringAsFixed(2)}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: qty <= 1 ? null : () => onQuantityChanged(qty - 1),
              color: theme.colorScheme.primary,
            ),
            SizedBox(
              width: 28,
              child: Text(
                qty.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onQuantityChanged(qty + 1),
              color: theme.colorScheme.primary,
            ),
            IconButton(
              icon: Icon(Icons.delete, color: theme.colorScheme.error),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
