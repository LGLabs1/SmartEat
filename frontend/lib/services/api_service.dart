import 'firebase_service.dart';

class ApiService {
  // Menu endpoints - using Firebase
  static Future<Map<String, dynamic>> getMenuItems() async {
    final items = await FirebaseService.getMenuItems();
    return {'data': items};
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
  }) async {
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
      'isAvailable': availableServings > 0,
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
        updates['isAvailable'] = availableServings > 0;
      }
    }
    if (description != null) updates['description'] = description;
    if (isAvailable != null) updates['isAvailable'] = isAvailable;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;

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

  // Generate forecasts based on actual historical data
  static Future<Map<String, dynamic>> getDemandForecast({int days = 7}) async {
    try {
      // Get last 30 days of orders for trend analysis
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));
      final ordersResult =
          await getOrdersByDateRange(startDate: startDate, endDate: endDate);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      // Calculate daily order counts
      final dailyCounts = <String, int>{};
      for (var i = 0; i < 30; i++) {
        final date = endDate.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        dailyCounts[dateStr] = 0;
      }

      for (final order in orders) {
        if (order is Map) {
          final createdAt = order['createdAt'];
          if (createdAt != null) {
            final dateStr = createdAt.toString().split('T')[0];
            dailyCounts[dateStr] = (dailyCounts[dateStr] ?? 0) + 1;
          }
        }
      }

      // Calculate average daily orders
      final avgDailyOrders = dailyCounts.values.isEmpty
          ? 5.0
          : dailyCounts.values.reduce((a, b) => a + b) /
              dailyCounts.values.length;

      // Generate forecast with slight trend based on recent performance
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;

        // Adjust for weekend patterns (higher on weekends)
        var multiplier = 1.0;
        if (dayOfWeek == 6 || dayOfWeek == 7) {
          // Saturday or Sunday
          multiplier = 1.2;
        } else if (dayOfWeek == 1) {
          // Monday
          multiplier = 0.9;
        }

        final predictedDemand = (avgDailyOrders * multiplier).round();

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedDemand': predictedDemand,
          'confidence':
              0.75 + (i * 0.01), // Confidence decreases slightly further out
        });
      }

      return {'data': forecast};
    } catch (e) {
      // Fallback to simple forecast if data fetch fails
      return _generateSimpleForecast(days);
    }
  }

  static Future<Map<String, dynamic>> getSalesForecast({int days = 7}) async {
    try {
      // Get last 30 days of orders for revenue trend analysis
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));
      final ordersResult =
          await getOrdersByDateRange(startDate: startDate, endDate: endDate);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      // Calculate daily revenue
      final dailyRevenue = <String, double>{};
      for (var i = 0; i < 30; i++) {
        final date = endDate.subtract(Duration(days: i));
        final dateStr = date.toIso8601String().split('T')[0];
        dailyRevenue[dateStr] = 0.0;
      }

      for (final order in orders) {
        if (order is Map) {
          final createdAt = order['createdAt'];
          final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
          final status = (order['status'] ?? '').toString().toLowerCase();

          if (createdAt != null && status == 'completed') {
            final dateStr = createdAt.toString().split('T')[0];
            dailyRevenue[dateStr] = (dailyRevenue[dateStr] ?? 0.0) + total;
          }
        }
      }

      // Calculate average daily revenue
      final avgDailyRevenue = dailyRevenue.values.isEmpty
          ? 5000.0
          : dailyRevenue.values.reduce((a, b) => a + b) /
              dailyRevenue.values.length;

      // Generate forecast with trend
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;

        // Adjust for weekend patterns
        var multiplier = 1.0;
        if (dayOfWeek == 6 || dayOfWeek == 7) {
          multiplier = 1.3;
        } else if (dayOfWeek == 1) {
          multiplier = 0.85;
        }

        final predictedSales = avgDailyRevenue * multiplier;

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedSales': predictedSales.round(),
          'confidence': 0.75 + (i * 0.01),
        });
      }

      return {'data': forecast};
    } catch (e) {
      return _generateSimpleSalesForecast(days);
    }
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

  // Fallback forecast generators
  static Map<String, dynamic> _generateSimpleForecast(int days) {
    final forecast = <Map<String, dynamic>>[];
    for (var i = 1; i <= days; i++) {
      forecast.add({
        'day': i,
        'predictedDemand': 5 + (i % 3),
        'confidence': 0.7,
      });
    }
    return {'data': forecast};
  }

  static Map<String, dynamic> _generateSimpleSalesForecast(int days) {
    final forecast = <Map<String, dynamic>>[];
    for (var i = 1; i <= days; i++) {
      forecast.add({
        'day': i,
        'predictedSales': 5000 + (i * 100),
        'confidence': 0.7,
      });
    }
    return {'data': forecast};
  }

  // Finance endpoints
  static Future<Map<String, dynamic>> getExpenses() async {
    final items = await FirebaseService.getExpenses();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createExpense({
    required String category,
    required double amount,
    DateTime? date,
    String? vendor,
    String? notes,
  }) async {
    final item = await FirebaseService.createExpense({
      'category': category,
      'amount': amount,
      if (date != null) 'date': date.toIso8601String(),
      if (vendor != null && vendor.trim().isNotEmpty) 'vendor': vendor.trim(),
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
}
