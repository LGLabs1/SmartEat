import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class ApiService {
  static const String _baseUrl = 'http://localhost:3000/api';

  static Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  // Menu endpoints - using Firebase
  static Future<Map<String, dynamic>> getMenuItems() async {
    final items = await FirebaseService.getMenuItems();
    return {'data': items};
  }

  static Stream<List<Map<String, dynamic>>> getMenuItemsStream() {
    return FirebaseService.getMenuItemsStream();
  }

  static Future<Map<String, dynamic>> getRecipes() async {
    final items = await FirebaseService.getRecipes();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createRecipe({
    required String name,
    required int baseServings,
    required List<Map<String, dynamic>> ingredients,
  }) async {
    final item = await FirebaseService.createRecipe({
      'name': name,
      'baseServings': baseServings,
      'ingredients': ingredients,
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> createMenuItem({
    required String name,
    required String category,
    List<String>? categories,
    String? recipeId,
    String? inventoryItemId,
    required int price,
    required int availableServings,
    String? description,
    String? imageUrl,
    double? imageAlignmentX,
    double? imageAlignmentY,
  }) async {
    final invLinked =
        inventoryItemId != null && inventoryItemId.trim().isNotEmpty;
    final bool initialAvailability = invLinked ? (availableServings > 0) : true;
    final item = await FirebaseService.createMenuItem({
      'name': name,
      'category': category,
      if (categories != null) 'categories': categories,
      if (recipeId != null && recipeId.trim().isNotEmpty)
        'recipeId': recipeId.trim(),
      if (inventoryItemId != null && inventoryItemId.trim().isNotEmpty)
        'inventoryItemId': inventoryItemId.trim(),
      'price': price,
      'availableServings': availableServings,
      'description': description ?? '',
      'imageUrl': imageUrl ?? '',
      if (imageAlignmentX != null) 'imageAlignmentX': imageAlignmentX,
      if (imageAlignmentY != null) 'imageAlignmentY': imageAlignmentY,
      'isAvailable': initialAvailability,
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> updateMenuItem(
    String id, {
    String? name,
    String? category,
    List<String>? categories,
    String? recipeId,
    String? inventoryItemId,
    int? price,
    int? availableServings,
    String? description,
    bool? isAvailable,
    String? imageUrl,
    double? imageAlignmentX,
    double? imageAlignmentY,
  }) async {
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (category != null) updates['category'] = category;
    if (categories != null) updates['categories'] = categories;
    if (recipeId != null) {
      final trimmed = recipeId.trim();
      if (trimmed.isEmpty) {
        updates['recipeId'] = '';
      } else {
        updates['recipeId'] = trimmed;
      }
    }
    if (inventoryItemId != null) {
      final trimmed = inventoryItemId.trim();
      if (trimmed.isEmpty) {
        updates['inventoryItemId'] = '';
      } else {
        updates['inventoryItemId'] = trimmed;
      }
    }
    if (price != null) updates['price'] = price;
    if (availableServings != null) {
      updates['availableServings'] = availableServings;
      if (isAvailable == null) {
        // For unlimited items (availableServings == -1), keep available unless explicitly toggled off.
        updates['isAvailable'] =
            availableServings == -1 ? true : availableServings > 0;
      }
    }
    if (description != null) updates['description'] = description;
    if (isAvailable != null) updates['isAvailable'] = isAvailable;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (imageAlignmentX != null) updates['imageAlignmentX'] = imageAlignmentX;
    if (imageAlignmentY != null) updates['imageAlignmentY'] = imageAlignmentY;

    final item = await FirebaseService.updateMenuItem(id, updates);
    return {'data': item};
  }

  static Future<Map<String, dynamic>> deleteMenuItem(String id) async {
    await FirebaseService.deleteMenuItem(id);
    return {'success': true};
  }

  // Order endpoints
  static Future<Map<String, dynamic>> createOrder({
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'cash',
    String? notes,
    String? orderId,
  }) async {
    // Calculate total amount
    double totalAmount = 0;
    for (final item in items) {
      final priceRaw = item['price'];
      final price = priceRaw is num
          ? priceRaw.toDouble()
          : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;
      final qty = (item['quantity'] as int?) ??
          int.tryParse((item['quantity'] ?? '').toString()) ??
          0;
      totalAmount += price * qty;
    }

    final order = await FirebaseService.createOrder({
      'items': items,
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'notes': notes ?? '',
      'status': 'pending',
    }, orderId: orderId);
    return {'data': order};
  }

  static Future<Map<String, dynamic>> getTodayOrders() async {
    final orders = await FirebaseService.getTodayOrders();
    return {'data': orders};
  }

  static Future<Map<String, dynamic>> getOrdersByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final orders =
        await FirebaseService.getOrders(startDate: startDate, endDate: endDate);
    return {'data': orders};
  }

  static Future<Map<String, dynamic>> getPendingOrders({int limit = 20}) async {
    final orders = await FirebaseService.getPendingOrders(limit: limit);
    return {'data': orders};
  }

  static Future<Map<String, dynamic>> addItemsToPendingOrder({
    required String orderId,
    required List<Map<String, dynamic>> items,
  }) async {
    final updated =
        await FirebaseService.addItemsToPendingOrder(orderId, items);
    return {'data': updated};
  }

  static Future<Map<String, dynamic>> getOrderById(String orderId) async {
    final order = await FirebaseService.getOrderById(orderId);
    return {'data': order};
  }

  static Future<Map<String, dynamic>> completeOrder(String orderId) async {
    final res = await FirebaseService.completeOrder(orderId);
    return {'data': res};
  }

  static Future<Map<String, dynamic>> voidOrder(
    String orderId, {
    String reason = '',
  }) async {
    await FirebaseService.voidOrder(orderId, reason: reason);
    return {'ok': true};
  }

  static Future<Map<String, dynamic>> voidOrderItems(
    String orderId,
    List<Map<String, dynamic>> itemsToVoid, {
    String reason = '',
  }) async {
    await FirebaseService.voidOrderItems(orderId, itemsToVoid, reason: reason);
    return {'ok': true};
  }

  static Future<Map<String, dynamic>> restoreOrderToPending(
      String orderId) async {
    await FirebaseService.restoreOrderToPending(orderId);
    return {'ok': true};
  }

  // Inventory endpoints
  static Future<Map<String, dynamic>> getInventoryItems(
      {String? category}) async {
    final items = await FirebaseService.getInventoryItems(category: category);
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createInventoryItem({
    required String name,
    required String category,
    required double currentStock,
    required String unit,
    required double minStock,
    required double unitCost,
    double? sellingPrice,
    String? supplier,
  }) async {
    final item = await FirebaseService.createInventoryItem({
      'name': name,
      'category': category,
      'currentStock': currentStock,
      'unit': unit,
      'minStock': minStock,
      'unitCost': unitCost,
      if (sellingPrice != null) 'sellingPrice': sellingPrice,
      'supplier': supplier ?? '',
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> updateInventoryItem(
    String id, {
    String? name,
    String? category,
    double? minStock,
    double? unitCost,
    double? sellingPrice,
    String? supplier,
  }) async {
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (category != null) updates['category'] = category;
    if (minStock != null) updates['minStock'] = minStock;
    if (unitCost != null) updates['unitCost'] = unitCost;
    if (sellingPrice != null) updates['sellingPrice'] = sellingPrice;
    if (supplier != null) updates['supplier'] = supplier;

    final item = await FirebaseService.updateInventoryItem(id, updates);
    return {'data': item};
  }

  static Future<Map<String, dynamic>> updateInventoryStock(
    String id, {
    required double quantity,
    String operation = 'set',
  }) async {
    final item =
        await FirebaseService.updateInventoryStock(id, quantity, operation);
    return {'data': item};
  }

  static Future<Map<String, dynamic>> markInventoryDamaged(
    String id, {
    required double quantity,
    String reason = 'Damaged',
  }) async {
    final item = await FirebaseService.createDamagedItem(id, quantity, reason);
    return {'data': item};
  }

  static Future<Map<String, dynamic>> getDamagedItems() async {
    final items = await FirebaseService.getDamagedItems();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> getLowStockItems() async {
    final items = await FirebaseService.getLowStockItems();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> deleteInventoryItem(String id) async {
    await FirebaseService.deleteInventoryItem(id);
    return {'success': true};
  }

  // Analytics endpoints
  static Future<Map<String, dynamic>> getDailySalesAnalytics(
      {int days = 30}) async {
    final data = await FirebaseService.getDailySalesAnalytics(days: days);
    return {'data': data};
  }

  static Future<Map<String, dynamic>> getItemPerformance() async {
    final data = await FirebaseService.getItemPerformance();
    return {'data': data};
  }

  static Future<Map<String, dynamic>> getSummaryStats() async {
    final data = await FirebaseService.getSummaryStats();
    return {'data': data};
  }

  // Get order count forecast based on historical day-of-week averages
  static Future<Map<String, dynamic>> getOrdersForecast({int days = 7}) async {
    try {
      // Get last 60 days of orders for historical analysis
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 60));
      final ordersResult =
          await getOrdersByDateRange(startDate: startDate, endDate: endDate);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      // Group orders by day of week (1=Monday, 7=Sunday)
      final dayOfWeekOrderCounts = <int, List<int>>{};
      for (int i = 1; i <= 7; i++) {
        dayOfWeekOrderCounts[i] = [];
      }

      // Count orders per day
      final ordersPerDay = <String, int>{};
      for (final order in orders) {
        if (order is Map) {
          final createdAt = order['createdAt'];
          final status = (order['status'] ?? '').toString().toLowerCase();

          if (createdAt != null && status == 'completed') {
            // Handle both Timestamp and String formats
            DateTime? orderDate;
            if (createdAt is Timestamp) {
              orderDate = createdAt.toDate();
            } else if (createdAt is String) {
              orderDate = DateTime.tryParse(createdAt);
            }
            if (orderDate != null) {
              final dateStr = orderDate.toIso8601String().split('T')[0];
              ordersPerDay[dateStr] = (ordersPerDay[dateStr] ?? 0) + 1;
            }
          }
        }
      }

      // Group by day of week
      for (var i = 0; i < 60; i++) {
        final date = endDate.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        final dayOfWeek = date.weekday;
        final count = ordersPerDay[dateStr] ?? 0;
        dayOfWeekOrderCounts[dayOfWeek]!.add(count);
      }

      // Calculate average orders per day of week
      final dayOfWeekAverages = <int, double>{};
      for (int i = 1; i <= 7; i++) {
        final counts = dayOfWeekOrderCounts[i]!;
        if (counts.isNotEmpty) {
          final sum = counts.reduce((a, b) => a + b);
          dayOfWeekAverages[i] = sum / counts.length;
        } else {
          dayOfWeekAverages[i] = 0.0;
        }
      }

      // Generate forecast
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;
        final predictedOrders = dayOfWeekAverages[dayOfWeek]!.round();

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedOrders': predictedOrders,
          'confidence': 0.8,
          'dayName': _getDayName(date.weekday),
          'isWeekend': date.weekday == 6 || date.weekday == 7,
        });
      }

      return {
        'data': forecast,
        'model': 'historical_day_of_week',
        'note': 'Based on average orders per day of week from last 60 days',
      };
    } catch (e) {
      // Fallback: return zeros if no data available
      return _generateEmptyForecast(days);
    }
  }

  static Map<String, dynamic> _generateEmptyForecast(int days) {
    final forecast = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (var i = 1; i <= days; i++) {
      final date = now.add(Duration(days: i));
      forecast.add({
        'day': i,
        'date': date.toIso8601String().split('T')[0],
        'predictedOrders': 0,
        'confidence': 0.0,
        'dayName': _getDayName(date.weekday),
        'isWeekend': date.weekday == 6 || date.weekday == 7,
      });
    }
    return {
      'data': forecast,
      'model': 'empty',
      'note': 'No historical data available'
    };
  }

  static Future<Map<String, dynamic>> getSalesForecast({int days = 7}) async {
    try {
      // Get last 60 days of orders for historical revenue analysis
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 60));
      final ordersResult =
          await getOrdersByDateRange(startDate: startDate, endDate: endDate);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      // Group revenue by day of week (1=Monday, 7=Sunday)
      final dayOfWeekRevenues = <int, List<double>>{};
      for (int i = 1; i <= 7; i++) {
        dayOfWeekRevenues[i] = [];
      }

      // Calculate daily revenue
      final dailyRevenue = <String, double>{};
      for (final order in orders) {
        if (order is Map) {
          final createdAt = order['createdAt'];
          final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final status = (order['status'] ?? '').toString().toLowerCase();

          if (createdAt != null && status == 'completed') {
            // Handle both Timestamp and String formats
            DateTime? orderDate;
            if (createdAt is Timestamp) {
              orderDate = createdAt.toDate();
            } else if (createdAt is String) {
              orderDate = DateTime.tryParse(createdAt);
            }
            if (orderDate != null) {
              final dateStr = orderDate.toIso8601String().split('T')[0];
              dailyRevenue[dateStr] = (dailyRevenue[dateStr] ?? 0.0) + total;
            }
          }
        }
      }

      // Group revenue by day of week
      for (var i = 0; i < 60; i++) {
        final date = endDate.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        final dayOfWeek = date.weekday;
        final revenue = dailyRevenue[dateStr] ?? 0.0;
        dayOfWeekRevenues[dayOfWeek]!.add(revenue);
      }

      // Calculate average revenue per day of week
      final dayOfWeekAverages = <int, double>{};
      for (int i = 1; i <= 7; i++) {
        final revenues = dayOfWeekRevenues[i]!;
        if (revenues.isNotEmpty) {
          final sum = revenues.reduce((a, b) => a + b);
          dayOfWeekAverages[i] = sum / revenues.length;
        } else {
          dayOfWeekAverages[i] = 0.0;
        }
      }

      // Generate forecast
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;
        final predictedRevenue = dayOfWeekAverages[dayOfWeek]!.round();

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedRevenue': predictedRevenue,
          'confidence': 0.8,
          'dayName': _getDayName(date.weekday),
          'isWeekend': date.weekday == 6 || date.weekday == 7,
        });
      }

      return {
        'data': forecast,
        'model': 'historical_day_of_week',
        'note': 'Based on average revenue per day of week from last 60 days',
      };
    } catch (e) {
      // Fallback: return zeros if no data available
      return _generateEmptySalesForecast(days);
    }
  }

  static Map<String, dynamic> _generateEmptySalesForecast(int days) {
    final forecast = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (var i = 1; i <= days; i++) {
      final date = now.add(Duration(days: i));
      forecast.add({
        'day': i,
        'date': date.toIso8601String().split('T')[0],
        'predictedRevenue': 0,
        'confidence': 0.0,
        'dayName': _getDayName(date.weekday),
        'isWeekend': date.weekday == 6 || date.weekday == 7,
      });
    }
    return {
      'data': forecast,
      'model': 'empty',
      'note': 'No historical data available'
    };
  }

  static Future<Map<String, dynamic>> getRecommendations() async {
    try {
      // Fetch necessary data
      final now = DateTime.now();
      final lastMonthStart = DateTime(now.year, now.month - 1, 1);
      final lastMonthEnd = DateTime(now.year, now.month, 0);

      final ordersResult = await getOrdersByDateRange(
          startDate: lastMonthStart, endDate: lastMonthEnd);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      final inventoryResult = await getInventoryItems();
      final inventory = inventoryResult['data'] as List<dynamic>? ?? [];

      final menuResult = await getMenuItems();
      final menuItems = menuResult['data'] as List<dynamic>? ?? [];

      final promoteItems = <Map<String, dynamic>>[];
      final removeItems = <Map<String, dynamic>>[];
      final optimizeInventory = <Map<String, dynamic>>[];

      // Analyze item sales
      final itemSales = <String, Map<String, dynamic>>{};
      for (final order in orders) {
        if (order is Map) {
          final items = order['items'] as List<dynamic>? ?? [];
          final status = (order['status'] ?? '').toString().toLowerCase();

          if (status == 'completed') {
            for (final item in items) {
              if (item is Map) {
                final name = (item['name'] ?? 'Unknown').toString();
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final price = (item['price'] as num?)?.toDouble() ?? 0.0;

                if (!itemSales.containsKey(name)) {
                  itemSales[name] = {
                    'name': name,
                    'totalSold': 0,
                    'revenue': 0.0,
                  };
                }
                itemSales[name]!['totalSold'] =
                    (itemSales[name]!['totalSold'] as int) + qty;
                itemSales[name]!['revenue'] =
                    (itemSales[name]!['revenue'] as double) + (price * qty);
              }
            }
          }
        }
      }

      // Sort by sales performance
      final sortedItems = itemSales.values.toList()
        ..sort(
            (a, b) => (b['totalSold'] as int).compareTo(a['totalSold'] as int));

      // Top performers to promote
      if (sortedItems.isNotEmpty) {
        final topItem = sortedItems.first;
        if (topItem['totalSold'] > 10) {
          promoteItems.add({
            'name': topItem['name'],
            'reason':
                'High demand item - ${topItem['totalSold']} sold last month',
            'expectedIncrease': '15-20%',
          });
        }
      }

      // Low performers to consider removing
      if (sortedItems.length > 5) {
        final lowPerformers = sortedItems
            .where((item) =>
                (item['totalSold'] as int) < 3 &&
                sortedItems.indexOf(item) > sortedItems.length - 3)
            .toList();

        for (final item in lowPerformers.take(2)) {
          removeItems.add({
            'name': item['name'],
            'reason':
                'Very low sales - only ${item['totalSold']} sold last month',
            'wasteReduction': 'Reduce inventory costs',
          });
        }
      }

      // Inventory optimization recommendations
      for (final invItem in inventory) {
        if (invItem is Map) {
          final currentStock =
              (invItem['currentStock'] as num?)?.toDouble() ?? 0.0;
          final minStock = (invItem['minStock'] as num?)?.toDouble() ?? 0.0;
          final name = (invItem['name'] ?? '').toString();

          if (currentStock < minStock * 0.5) {
            optimizeInventory.add({
              'ingredient': name,
              'reason':
                  'Stock critically low (${currentStock.toStringAsFixed(1)} remaining)',
              'action':
                  'Order ${(minStock * 2).toStringAsFixed(0)} units immediately',
            });
          } else if (currentStock > minStock * 5) {
            optimizeInventory.add({
              'ingredient': name,
              'reason':
                  'Excess inventory (${currentStock.toStringAsFixed(1)} units)',
              'action': 'Reduce orders or create promotions to use stock',
            });
          }
        }
      }

      return {
        'data': {
          'promoteItems': promoteItems,
          'removeItems': removeItems,
          'optimizeInventory': optimizeInventory.take(5).toList(),
        }
      };
    } catch (e) {
      // Return basic recommendations if data fetch fails
      return {
        'data': {
          'promoteItems': [],
          'removeItems': [],
          'optimizeInventory': [],
        }
      };
    }
  }

  static String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // Finance endpoints
  static Future<Map<String, dynamic>> getExpenses() async {
    final items = await FirebaseService.getExpenses();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createExpense({
    required String name,
    required String category,
    required double amount,
    DateTime? date,
    String? notes,
  }) async {
    final item = await FirebaseService.createExpense({
      'name': name,
      'category': category,
      'amount': amount,
      if (date != null) 'date': date.toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> deleteExpense(String id) async {
    await FirebaseService.deleteExpense(id);
    return {'success': true};
  }

  static Future<Map<String, dynamic>> getPayables() async {
    final items = await FirebaseService.getPayables();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createPayable({
    required String name,
    required double amount,
    required String frequency,
    DateTime? dueDate,
    String? notes,
    String? vendor,
    int? dueDay,
    List<int>? dueDays,
    int? dueMonth,
  }) async {
    final item = await FirebaseService.createPayable({
      'name': name,
      'amount': amount,
      'frequency': frequency,
      if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (vendor != null && vendor.trim().isNotEmpty) 'vendor': vendor.trim(),
      if (dueDay != null) 'dueDay': dueDay,
      if (dueDays != null) 'dueDays': dueDays,
      if (dueMonth != null) 'dueMonth': dueMonth,
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> updatePayableStatus(
    String id, {
    required String status,
  }) async {
    await FirebaseService.updatePayableStatus(id, status: status);
    return {'success': true};
  }

  static Future<Map<String, dynamic>> updatePayable(
    String id, {
    required String name,
    required double amount,
    required String frequency,
    DateTime? dueDate,
    String? notes,
    String? vendor,
    int? dueDay,
    List<int>? dueDays,
    int? dueMonth,
  }) async {
    final item = await FirebaseService.updatePayable(id, {
      'name': name,
      'amount': amount,
      'frequency': frequency,
      if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
      if (notes != null) 'notes': notes.trim(),
      if (vendor != null && vendor.trim().isNotEmpty) 'vendor': vendor.trim(),
      if (dueDay != null) 'dueDay': dueDay,
      if (dueDays != null) 'dueDays': dueDays,
      if (dueMonth != null) 'dueMonth': dueMonth,
    });
    return {'data': item};
  }

  static Future<Map<String, dynamic>> deletePayable(String id) async {
    await FirebaseService.deletePayable(id);
    return {'success': true};
  }

  // Staff meal endpoints
  static Future<Map<String, dynamic>> createStaffMealOrder(
      Map<String, dynamic> data) async {
    final order = await FirebaseService.createStaffMealOrder(data);
    return {'data': order};
  }

  static Future<Map<String, dynamic>> getStaffMealOrders({
    String? eateryId,
    String? staffId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final orders = await FirebaseService.getStaffMealOrders(
      eateryId: eateryId,
      staffId: staffId,
      startDate: startDate,
      endDate: endDate,
    );
    return {'data': orders};
  }

  static Future<Map<String, dynamic>> updateStaffMealOrderStatus(
    String id, {
    required String eateryId,
    required String status,
  }) async {
    await FirebaseService.updateStaffMealOrderStatus(
      id,
      eateryId: eateryId,
      status: status,
    );
    return {'success': true};
  }

  static Future<Map<String, dynamic>> addItemsToOrder(
    String orderId,
    List<Map<String, dynamic>> items,
  ) async {
    final result = await FirebaseService.addItemsToPendingOrder(orderId, items);
    return {'success': true, 'data': result};
  }

  // Chatbot API Methods

  static Future<Map<String, dynamic>> sendChatMessage({
    required String message,
    List<Map<String, dynamic>>? history,
    String? context,
  }) async {
    final token = await _getAuthToken();
    final eateryId = await FirebaseService.getCurrentEateryId();
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (eateryId != null) {
      headers['x-eatery-id'] = eateryId;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/chatbot/chat'),
      headers: headers,
      body: jsonEncode({
        'message': message,
        'history': history ?? [],
        if (eateryId != null) 'eateryId': eateryId,
        if (context != null) 'context': context,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send message: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getChatbotStatus() async {
    final token = await _getAuthToken();
    final eateryId = await FirebaseService.getCurrentEateryId();
    final Map<String, String> headers = {};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (eateryId != null) {
      headers['x-eatery-id'] = eateryId;
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/chatbot/status'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get chatbot status: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getAIInsights() async {
    final token = await _getAuthToken();
    final eateryId = await FirebaseService.getCurrentEateryId();
    final Map<String, String> headers = {};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (eateryId != null) {
      headers['x-eatery-id'] = eateryId;
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/chatbot/insights'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get AI insights: ${response.body}');
    }
  }
}
