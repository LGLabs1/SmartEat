import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class ChatApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ChatApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class ApiService {
  // Deployed demo backend (Render).
  static const String _baseUrl = 'https://smarteat-backend-n5ta.onrender.com/api';

  // A single keep-alive client reused across requests. Creating a new client
  // per call forced a fresh TCP connection every time, adding latency.
  static final http.Client _client = http.Client();

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
    bool completeNow = false,
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

    // `completeNow` is passed through rather than implemented by creating the
    // order and then calling completeOrder: createOrder already deducts stock
    // in its transaction, so completing afterwards would deduct it twice.
    final order = await FirebaseService.createOrder({
      'items': items,
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'notes': notes ?? '',
      'status': completeNow ? 'completed' : 'pending',
    }, orderId: orderId, status: completeNow ? 'completed' : 'pending');
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

  /// All orders for the current eatery. Shares the same de-duplicated query as
  /// the summary/item-performance helpers so one screen load fetches once.
  static Future<Map<String, dynamic>> getAllOrders() async {
    final orders = await FirebaseService.getOrders();
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
    Map<String, dynamic>? extra,
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
      ...?extra,
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

  // Inventory audit trail (durable, Firestore-backed history).
  static Future<Map<String, dynamic>> getStockMovements() async {
    final items = await FirebaseService.getStockMovements();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createStockMovement(
    Map<String, dynamic> movement,
  ) async {
    final result = await FirebaseService.createStockMovement(movement);
    return {'data': result};
  }

  static Future<Map<String, dynamic>> getPurchaseReceipts() async {
    final items = await FirebaseService.getPurchaseReceipts();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createPurchaseReceipt(
    Map<String, dynamic> receipt,
  ) async {
    final result = await FirebaseService.createPurchaseReceipt(receipt);
    return {'data': result};
  }

  static Future<Map<String, dynamic>> getStockAdjustments() async {
    final items = await FirebaseService.getStockAdjustments();
    return {'data': items};
  }

  static Future<Map<String, dynamic>> createStockAdjustment(
    Map<String, dynamic> adjustment,
  ) async {
    final result = await FirebaseService.createStockAdjustment(adjustment);
    return {'data': result};
  }

  // Analytics endpoints
  static Future<Map<String, dynamic>> getDailySalesAnalytics(
      {int days = 30}) async {
    final data = await FirebaseService.getDailySalesAnalytics(days: days);
    return {'data': data};
  }

  static Future<Map<String, dynamic>> getIngredientUsageByMenuItem(
      {int days = 30}) async {
    final data =
        await FirebaseService.getIngredientUsageByMenuItem(days: days);
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

      // Calculate average orders per day of week (plus spread for confidence)
      final dayOfWeekAverages = <int, double>{};
      final dayOfWeekStdDev = <int, double>{};
      final dayOfWeekSamples = <int, int>{};
      for (int i = 1; i <= 7; i++) {
        final counts = dayOfWeekOrderCounts[i]!;
        if (counts.isNotEmpty) {
          final sum = counts.reduce((a, b) => a + b);
          final mean = sum / counts.length;
          dayOfWeekAverages[i] = mean;
          // Standard deviation of the observations for this weekday.
          final variance = counts
                  .map((c) => (c - mean) * (c - mean))
                  .reduce((a, b) => a + b) /
              counts.length;
          dayOfWeekStdDev[i] = variance <= 0 ? 0.0 : math.sqrt(variance);
          // Only count days that actually had orders as usable samples.
          dayOfWeekSamples[i] = counts.where((c) => c > 0).length;
        } else {
          dayOfWeekAverages[i] = 0.0;
          dayOfWeekStdDev[i] = 0.0;
          dayOfWeekSamples[i] = 0;
        }
      }

      // Generate forecast
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;
        final mean = dayOfWeekAverages[dayOfWeek]!;
        final predictedOrders = mean.round();
        final confidence = _forecastConfidence(
          mean: mean,
          stdDev: dayOfWeekStdDev[dayOfWeek]!,
          sampleSize: dayOfWeekSamples[dayOfWeek]!,
        );

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedOrders': predictedOrders,
          'confidence': confidence,
          'sampleSize': dayOfWeekSamples[dayOfWeek],
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

      // Calculate average revenue per day of week (plus spread for confidence)
      final dayOfWeekAverages = <int, double>{};
      final dayOfWeekStdDev = <int, double>{};
      final dayOfWeekSamples = <int, int>{};
      for (int i = 1; i <= 7; i++) {
        final revenues = dayOfWeekRevenues[i]!;
        if (revenues.isNotEmpty) {
          final sum = revenues.reduce((a, b) => a + b);
          final mean = sum / revenues.length;
          dayOfWeekAverages[i] = mean;
          final variance = revenues
                  .map((r) => (r - mean) * (r - mean))
                  .reduce((a, b) => a + b) /
              revenues.length;
          dayOfWeekStdDev[i] = variance <= 0 ? 0.0 : math.sqrt(variance);
          dayOfWeekSamples[i] = revenues.where((r) => r > 0).length;
        } else {
          dayOfWeekAverages[i] = 0.0;
          dayOfWeekStdDev[i] = 0.0;
          dayOfWeekSamples[i] = 0;
        }
      }

      // Generate forecast
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i <= days; i++) {
        final date = endDate.add(Duration(days: i));
        final dayOfWeek = date.weekday;
        final mean = dayOfWeekAverages[dayOfWeek]!;
        final predictedRevenue = mean.round();
        final confidence = _forecastConfidence(
          mean: mean,
          stdDev: dayOfWeekStdDev[dayOfWeek]!,
          sampleSize: dayOfWeekSamples[dayOfWeek]!,
        );

        forecast.add({
          'day': i,
          'date': date.toIso8601String().split('T')[0],
          'predictedRevenue': predictedRevenue,
          'confidence': confidence,
          'sampleSize': dayOfWeekSamples[dayOfWeek],
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
      // Fetch necessary data for the previous month.
      final now = DateTime.now();
      final lastMonthStart = DateTime(now.year, now.month - 1, 1);
      final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59, 999);

      final ordersResult = await getOrdersByDateRange(
          startDate: lastMonthStart, endDate: lastMonthEnd);
      final orders = ordersResult['data'] as List<dynamic>? ?? [];

      final inventoryResult = await getInventoryItems();
      final inventory = inventoryResult['data'] as List<dynamic>? ?? [];

      final promoteItems = <Map<String, dynamic>>[];
      final removeItems = <Map<String, dynamic>>[];
      final optimizeInventory = <Map<String, dynamic>>[];

      // Analyze item sales for the period, tracking quantity, revenue and the
      // most recent sale date so we can reason about staleness too.
      final itemSales = <String, Map<String, dynamic>>{};
      for (final order in orders) {
        if (order is Map) {
          final items = order['items'] as List<dynamic>? ?? [];
          final status = (order['status'] ?? '').toString().toLowerCase();
          if (status != 'completed') continue;

          DateTime? orderDate;
          final createdAt = order['createdAt'] ?? order['completedAt'];
          if (createdAt is Timestamp) {
            orderDate = createdAt.toDate();
          } else if (createdAt is DateTime) {
            orderDate = createdAt;
          } else if (createdAt is String) {
            orderDate = DateTime.tryParse(createdAt);
          }

          for (final item in items) {
            if (item is! Map) continue;
            final name = (item['name'] ?? 'Unknown').toString();
            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;

            final entry = itemSales.putIfAbsent(
              name,
              () => {
                'name': name,
                'totalSold': 0,
                'revenue': 0.0,
                'lastSoldAt': null,
              },
            );
            entry['totalSold'] = (entry['totalSold'] as int) + qty;
            entry['revenue'] = (entry['revenue'] as double) + (price * qty);
            if (orderDate != null) {
              final prev = entry['lastSoldAt'] as DateTime?;
              if (prev == null || orderDate.isAfter(prev)) {
                entry['lastSoldAt'] = orderDate;
              }
            }
          }
        }
      }

      // Sort by units sold (primary), then revenue.
      final sortedItems = itemSales.values.toList()
        ..sort((a, b) {
          final bySold =
              (b['totalSold'] as int).compareTo(a['totalSold'] as int);
          if (bySold != 0) return bySold;
          return (b['revenue'] as double).compareTo(a['revenue'] as double);
        });

      final totalSold =
          sortedItems.fold<int>(0, (s, i) => s + (i['totalSold'] as int));

      // Top performers to promote — up to 3, quantified with quantity + revenue.
      final promoteCandidates = sortedItems
          .where((item) => (item['totalSold'] as int) >= 5)
          .take(3)
          .toList();
      for (final item in promoteCandidates) {
        final sold = item['totalSold'] as int;
        final revenue = item['revenue'] as double;
        promoteItems.add({
          'name': item['name'],
          'reason':
              'Strong seller — $sold sold last month (${_currencyShort(revenue)} revenue)',
          'expectedIncrease': '15-20%',
          'impact': '≈${_currencyShort(revenue * 0.15)} potential lift',
          'severity': sold >= 20 ? 'high' : 'medium',
        });
      }

      // Low performers / dead stock to consider removing — up to 3.
      if (sortedItems.length > 4 && totalSold > 0) {
        final lowPerformers = sortedItems.where((item) {
          final sold = item['totalSold'] as int;
          final lastSold = item['lastSoldAt'] as DateTime?;
          final stale = lastSold != null &&
              now.difference(lastSold).inDays >= 21;
          return sold < 3 || stale;
        }).toList();

        for (final item in lowPerformers.take(3)) {
          final sold = item['totalSold'] as int;
          final lastSold = item['lastSoldAt'] as DateTime?;
          final daysSince =
              lastSold == null ? null : now.difference(lastSold).inDays;
          removeItems.add({
            'name': item['name'],
            'reason': daysSince != null && daysSince >= 21
                ? 'No sales in $daysSince days — likely dead stock'
                : 'Very low demand — only $sold sold last month',
            'wasteReduction': 'Reduce inventory costs',
            'impact': daysSince != null && daysSince >= 21
                ? 'Frees shelf space & stock capital'
                : 'Cuts waste on slow movers',
            'severity': (sold == 0 || (daysSince ?? 0) >= 30) ? 'high' : 'low',
          });
        }
      }

      // Inventory optimization — quantify the gap and flag severity.
      for (final invItem in inventory) {
        if (invItem is! Map) continue;
        final currentStock =
            (invItem['currentStock'] as num?)?.toDouble() ?? 0.0;
        final minStock = (invItem['minStock'] as num?)?.toDouble() ?? 0.0;
        final name = (invItem['name'] ?? '').toString();
        if (name.isEmpty) continue;

        if (minStock > 0 && currentStock < minStock * 0.5) {
          final shortfall = (minStock * 2) - currentStock;
          optimizeInventory.add({
            'ingredient': name,
            'reason':
                'Stock critically low (${currentStock.toStringAsFixed(1)} of ${minStock.toStringAsFixed(1)} min)',
            'action':
                'Order ${shortfall.toStringAsFixed(0)} units immediately',
            'impact': 'Restock to 2× minimum',
            'severity': currentStock <= 0 ? 'high' : 'medium',
          });
        } else if (minStock > 0 && currentStock > minStock * 5) {
          final excess = currentStock - (minStock * 3);
          optimizeInventory.add({
            'ingredient': name,
            'reason':
                'Overstocked (${currentStock.toStringAsFixed(1)} units, ${(currentStock / minStock).toStringAsFixed(1)}× minimum)',
            'action': 'Pause reordering or run a promo to use stock',
            'impact': '${excess.toStringAsFixed(0)} units above target',
            'severity': 'low',
          });
        }
      }

      // Sort inventory warnings so critical items surface first.
      const severityRank = {'high': 0, 'medium': 1, 'low': 2};
      optimizeInventory.sort((a, b) {
        final sa = severityRank[a['severity']] ?? 3;
        final sb = severityRank[b['severity']] ?? 3;
        return sa.compareTo(sb);
      });

      return {
        'available': true,
        'data': {
          'promoteItems': promoteItems,
          'removeItems': removeItems,
          'optimizeInventory': optimizeInventory.take(6).toList(),
        }
      };
    } catch (e) {
      // Distinguish a failed fetch from a genuinely empty result so the UI can
      // show "couldn't load" instead of a misleading "All caught up!".
      return {
        'available': false,
        'error': e.toString(),
        'data': {
          'promoteItems': [],
          'removeItems': [],
          'optimizeInventory': [],
        }
      };
    }
  }

  /// Compact peso formatter for recommendation copy (e.g. ₱12.5k).
  static String _currencyShort(double value) {
    if (value >= 1000000) return '₱${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '₱${(value / 1000).toStringAsFixed(1)}k';
    return '₱${value.toStringAsFixed(0)}';
  }

  static String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  /// Derives a 0.5–0.95 confidence score for a weekday forecast from how
  /// consistent that weekday's history has been (coefficient of variation),
  /// with a small penalty for thin samples. Mirrors the server model so both
  /// paths report comparable numbers.
  static double _forecastConfidence({
    required double mean,
    required double stdDev,
    required int sampleSize,
  }) {
    if (mean <= 0) return 0.0;
    final cv = stdDev / mean;
    var confidence = 1 - cv;
    // Thin samples (few observed weeks) lower confidence.
    if (sampleSize < 4) {
      confidence -= (4 - sampleSize) * 0.05;
    }
    confidence = confidence.clamp(0.5, 0.95);
    return (confidence * 100).round() / 100;
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
    String? supplierName,
    String? supplierId,
    String? receiptNumber,
    String? paymentMethod,
    String? paymentStatus,
    double? taxAmount,
  }) async {
    final item = await FirebaseService.createExpense({
      'name': name,
      'category': category,
      'amount': amount,
      if (date != null) 'date': date.toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (supplierName != null && supplierName.trim().isNotEmpty)
        'supplierName': supplierName.trim(),
      if (supplierId != null && supplierId.trim().isNotEmpty)
        'supplierId': supplierId.trim(),
      if (receiptNumber != null && receiptNumber.trim().isNotEmpty)
        'receiptNumber': receiptNumber.trim(),
      if (paymentMethod != null && paymentMethod.trim().isNotEmpty)
        'paymentMethod': paymentMethod.trim(),
      if (paymentStatus != null && paymentStatus.trim().isNotEmpty)
        'paymentStatus': paymentStatus.trim(),
      if (taxAmount != null && taxAmount > 0) 'taxAmount': taxAmount,
    });
    return {'data': item};
  }

  /// Auto-posts a recorded inventory purchase to finance expenses. Idempotent:
  /// if the receipt was already posted, the existing expense is returned.
  static Future<Map<String, dynamic>> postInventoryPurchaseExpense({
    required String purchaseReceiptId,
    required String receiptNumber,
    required double total,
    required DateTime date,
    String? supplierName,
    String? supplierId,
    String? notes,
    String category = 'Ingredients',
    String paymentStatus = 'paid',
    String? paymentMethod,
    String? createdBy,
  }) async {
    final item = await FirebaseService.createExpenseFromPurchase(
      purchaseReceiptId: purchaseReceiptId,
      receiptNumber: receiptNumber,
      total: total,
      date: date,
      supplierName: supplierName,
      supplierId: supplierId,
      notes: notes,
      category: category,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      createdBy: createdBy,
    );
    return {'data': item};
  }

  static Future<Map<String, dynamic>?> findLinkedPurchaseExpense(
    String purchaseReceiptId,
  ) {
    return FirebaseService.findExpenseByLinkedPurchase(purchaseReceiptId);
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
    bool isVariable = false,
    double? estimateAmount,
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
      'isVariable': isVariable,
      if (isVariable && estimateAmount != null && estimateAmount > 0)
        'estimateAmount': estimateAmount,
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
    bool isVariable = false,
    double? estimateAmount,
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
      'isVariable': isVariable,
      'estimateAmount':
          (isVariable && estimateAmount != null && estimateAmount > 0)
              ? estimateAmount
              : FieldValue.delete(),
    });
    return {'data': item};
  }

  /// Records an actual payment for a payable, mirroring it into expenses and
  /// updating the bill's rolling amount history. Admin-only on the backend.
  static Future<Map<String, dynamic>> recordPayablePayment({
    required Map<String, dynamic> payable,
    required double amount,
    String category = 'Bills',
    DateTime? date,
  }) async {
    final expense = await FirebaseService.recordPayablePayment(
      payable: payable,
      amount: amount,
      category: category,
      date: date,
    );
    return {'data': expense};
  }

  /// Removes the expense mirrored when a payable was marked paid.
  static Future<Map<String, dynamic>> removePayablePaymentExpense(
    String payableId,
  ) async {
    await FirebaseService.removePayablePaymentExpense(payableId);
    return {'success': true};
  }

  static Future<Map<String, dynamic>?> findLinkedPayableExpense(
    String payableId,
  ) {
    return FirebaseService.findExpenseByLinkedPayable(payableId);
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
    // OPTIMIZATION: token refresh and the eatery lookup run concurrently.
    final results = await Future.wait<Object?>([
      _getAuthToken(),
      FirebaseService.getCurrentEateryId(),
    ]);
    final token = results[0] as String?;
    final eateryId = results[1] as String?;
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (eateryId != null) {
      headers['x-eatery-id'] = eateryId;
    }

    late http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/chatbot/chat'),
        headers: headers,
        body: jsonEncode({
          'message': message,
          'history': history ?? [],
          if (eateryId != null) 'eateryId': eateryId,
          if (context != null) 'context': context,
        }),
      );
    } on http.ClientException catch (error) {
      throw ChatApiException(
        code: 'network_unavailable',
        message: error.message,
      );
    } on SocketException catch (error) {
      throw ChatApiException(
        code: 'network_unavailable',
        message: error.message,
      );
    }

    Map<String, dynamic> payload = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // Keep a typed error even when the server or proxy returns non-JSON text.
    }

    if (response.statusCode == 200) {
      if (payload['response'] is! String ||
          (payload['response'] as String).trim().isEmpty) {
        throw const ChatApiException(
          code: 'empty_response',
          message: 'Sage returned an empty response.',
          statusCode: 502,
        );
      }
      return payload;
    }

    throw ChatApiException(
      code: (payload['code'] ?? payload['error'] ?? 'server_error').toString(),
      message: (payload['message'] ??
              payload['error'] ??
              'The Sage service returned an unexpected error.')
          .toString(),
      statusCode: response.statusCode,
    );
  }

  /// Streams Sage's reply token-by-token from `POST /chatbot/chat/stream`.
  ///
  /// Emits plain text deltas as they arrive so the UI can render progressively.
  /// Throws [ChatApiException] on transport or server errors.
  static Stream<String> sendChatMessageStream({
    required String message,
    List<Map<String, dynamic>>? history,
    String? context,
  }) async* {
    final results = await Future.wait<Object?>([
      _getAuthToken(),
      FirebaseService.getCurrentEateryId(),
    ]);
    final token = results[0] as String?;
    final eateryId = results[1] as String?;
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (eateryId != null) headers['x-eatery-id'] = eateryId;

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/chatbot/chat/stream'),
    );
    request.headers.addAll(headers);
    request.body = jsonEncode({
      'message': message,
      'history': history ?? [],
      if (eateryId != null) 'eateryId': eateryId,
      if (context != null) 'context': context,
    });

    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request);
    } on http.ClientException catch (error) {
      throw ChatApiException(code: 'network_unavailable', message: error.message);
    } on SocketException catch (error) {
      throw ChatApiException(code: 'network_unavailable', message: error.message);
    }

    if (streamed.statusCode != 200) {
      // Drain the body so the error message survives, then throw.
      final body = await streamed.stream.bytesToString();
      Map<String, dynamic> payload = {};
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
      throw ChatApiException(
        code: (payload['code'] ?? payload['error'] ?? 'server_error').toString(),
        message: (payload['message'] ??
                payload['error'] ??
                'The Sage service returned an unexpected error.')
            .toString(),
        statusCode: streamed.statusCode,
      );
    }

    // Parse the SSE stream: events are `data: {json}\n\n`. Buffer partial
    // lines across chunk boundaries.
    var buffer = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final raw = trimmed.substring(5).trim();
        if (raw.isEmpty) continue;
        Map<String, dynamic> event;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          event = decoded;
        } catch (_) {
          continue;
        }
        switch (event['type']) {
          case 'token':
            final text = event['text'];
            if (text is String && text.isNotEmpty) yield text;
            break;
          case 'error':
            throw ChatApiException(
              code: (event['error'] ?? 'server_error').toString(),
              message: (event['message'] ?? 'Sage could not complete the request.')
                  .toString(),
            );
          case 'done':
            return;
        }
      }
    }
  }

  static Future<Map<String, dynamic>> getChatbotStatus() async {
    final results = await Future.wait<Object?>([
      _getAuthToken(),
      FirebaseService.getCurrentEateryId(),
    ]);
    final token = results[0] as String?;
    final eateryId = results[1] as String?;
    final Map<String, String> headers = {};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (eateryId != null) headers['x-eatery-id'] = eateryId;

    final response = await http.get(
      Uri.parse('$_baseUrl/chatbot/status'),
      headers: headers,
    );

    // Any JSON payload is useful: the backend reports ollamaRunning:false
    // (with a reason code) on 503, which is a *different* cause than the
    // backend being unreachable.
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Non-JSON body — handled below as a typed error.
    }

    throw ChatApiException(
      code: 'status_unavailable',
      message: 'Backend status endpoint returned HTTP ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  static Future<Map<String, dynamic>> getAIInsights() async {
    final results = await Future.wait<Object?>([
      _getAuthToken(),
      FirebaseService.getCurrentEateryId(),
    ]);
    final token = results[0] as String?;
    final eateryId = results[1] as String?;
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
    }

    Map<String, dynamic> payload = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // Keep a typed error even when the body is not JSON.
    }

    throw ChatApiException(
      code: (payload['error'] ?? payload['code'] ?? 'server_error').toString(),
      message: (payload['message'] ??
              'The insights service returned an unexpected error.')
          .toString(),
      statusCode: response.statusCode,
    );
  }
}
