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
    });
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

  // Note: Demand forecast and recommendations would need ML service integration
  // For now, returning mock data
  static Future<Map<String, dynamic>> getDemandForecast({int days = 7}) async {
    return FirebaseService.mockDemandForecast(days);
  }

  static Future<Map<String, dynamic>> getSalesForecast({int days = 7}) async {
    return FirebaseService.mockSalesForecast(days);
  }

  static Future<Map<String, dynamic>> getRecommendations() async {
    return FirebaseService.mockRecommendations();
  }
}
