import 'package:cloud_firestore/cloud_firestore.dart';

enum ConsumptionMode { direct, recipePending }

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime _asDate(dynamic value, [DateTime? fallback]) {
  final result = fallback ?? DateTime.now();
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value == null) return result;
  return DateTime.tryParse(value.toString()) ?? result;
}

class StockLog {
  final DateTime timestamp;
  final double change;
  final String reason;

  StockLog(
      {required this.timestamp, required this.change, required this.reason});

  factory StockLog.fromJson(Map<String, dynamic> json) => StockLog(
        timestamp: _asDate(json['timestamp']),
        change: _asDouble(json['change']),
        reason: json['reason']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'change': change,
        'reason': reason,
      };
}

class InventoryItem {
  final String id;
  final String name;
  final String? sku;
  final String? description;
  final String? brand;
  final List<String> tags;
  final String category;
  final double currentStock;
  final String unit;
  final String? baseUnit;
  final String? purchaseUnit;
  final String? saleUnit;
  final double conversionFactor;
  final double minStock;
  final double reorderPoint;
  final double safetyStock;
  final double maxStock;
  final int leadTimeDays;
  final double unitCost;
  final double lastPurchaseCost;
  final double avgCost;
  final double sellingPrice;
  final String supplier;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBadStock;
  final double badStockQuantity;
  final List<StockLog> stockLogs;
  final bool isActive;
  final String? imageUrl;
  final String? notes;
  final ConsumptionMode consumptionMode;

  InventoryItem({
    required this.id,
    required this.name,
    this.sku,
    this.description,
    this.brand,
    List<String>? tags,
    required this.category,
    required this.currentStock,
    required this.unit,
    this.baseUnit,
    this.purchaseUnit,
    this.saleUnit,
    this.conversionFactor = 1.0,
    required this.minStock,
    this.reorderPoint = 0.0,
    this.safetyStock = 0.0,
    this.maxStock = 0.0,
    this.leadTimeDays = 0,
    required this.unitCost,
    this.lastPurchaseCost = 0.0,
    this.avgCost = 0.0,
    this.sellingPrice = 0,
    this.supplier = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isBadStock = false,
    this.badStockQuantity = 0,
    List<StockLog>? stockLogs,
    this.isActive = true,
    this.imageUrl,
    this.notes,
    this.consumptionMode = ConsumptionMode.direct,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        stockLogs = stockLogs ?? [],
        tags = tags ?? const [];

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString(),
      description: json['description']?.toString(),
      brand: json['brand']?.toString(),
      tags: json['tags'] is List
          ? (json['tags'] as List).map((e) => e.toString()).toList()
          : const [],
      category: json['category']?.toString() ?? '',
      currentStock: _asDouble(json['currentStock']),
      unit: json['unit']?.toString() ?? '',
      baseUnit: json['baseUnit']?.toString() ?? json['unit']?.toString(),
      purchaseUnit: json['purchaseUnit']?.toString(),
      saleUnit: json['saleUnit']?.toString(),
      conversionFactor: _asDouble(json['conversionFactor'], 1),
      minStock: _asDouble(json['minStock']),
      reorderPoint: _asDouble(json['reorderPoint']),
      safetyStock: _asDouble(json['safetyStock']),
      maxStock: _asDouble(json['maxStock']),
      leadTimeDays: _asInt(json['leadTimeDays']),
      unitCost: _asDouble(json['unitCost']),
      lastPurchaseCost: _asDouble(json['lastPurchaseCost']),
      avgCost: _asDouble(json['avgCost']),
      sellingPrice: _asDouble(json['sellingPrice']),
      supplier: json['supplier']?.toString() ?? '',
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
      isBadStock: json['isBadStock'] == true,
      badStockQuantity: _asDouble(json['badStockQuantity']),
      stockLogs: _parseStockLogs(json['stockLogs']),
      isActive: json['isActive'] != false,
      imageUrl: json['imageUrl']?.toString(),
      notes: json['notes']?.toString(),
      consumptionMode: _parseConsumptionMode(json['consumptionMode']),
    );
  }

  static List<StockLog> _parseStockLogs(dynamic value) {
    if (value is! List) return const [];
    final logs = <StockLog>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      try {
        logs.add(StockLog.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {}
    }
    return logs;
  }

  static ConsumptionMode _parseConsumptionMode(dynamic v) {
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'direct') return ConsumptionMode.direct;
      if (s == 'recipe_pending' || s == 'recipepending') {
        return ConsumptionMode.recipePending;
      }
    }
    return ConsumptionMode.direct;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'description': description,
        'brand': brand,
        'tags': tags,
        'category': category,
        'currentStock': currentStock,
        'unit': unit,
        'baseUnit': baseUnit ?? unit,
        'purchaseUnit': purchaseUnit,
        'saleUnit': saleUnit,
        'conversionFactor': conversionFactor,
        'minStock': minStock,
        'reorderPoint': reorderPoint,
        'safetyStock': safetyStock,
        'maxStock': maxStock,
        'leadTimeDays': leadTimeDays,
        'unitCost': unitCost,
        'lastPurchaseCost': lastPurchaseCost,
        'avgCost': avgCost,
        'sellingPrice': sellingPrice,
        'supplier': supplier,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'isBadStock': isBadStock,
        'badStockQuantity': badStockQuantity,
        'stockLogs': stockLogs.map((e) => e.toJson()).toList(),
        'isActive': isActive,
        'imageUrl': imageUrl,
        'notes': notes,
        'consumptionMode': consumptionMode == ConsumptionMode.direct
            ? 'direct'
            : 'recipe_pending',
      };

  bool get isLowStock =>
      currentStock <= (reorderPoint > 0 ? reorderPoint : minStock);
  double get totalValue =>
      currentStock * (lastPurchaseCost > 0 ? lastPurchaseCost : unitCost);
  String get effectiveBaseUnit => baseUnit ?? unit;

  InventoryItem copyWith({
    String? id,
    String? name,
    String? sku,
    String? description,
    String? brand,
    List<String>? tags,
    String? category,
    double? currentStock,
    String? unit,
    String? baseUnit,
    String? purchaseUnit,
    String? saleUnit,
    double? conversionFactor,
    double? minStock,
    double? reorderPoint,
    double? safetyStock,
    double? maxStock,
    int? leadTimeDays,
    double? unitCost,
    double? lastPurchaseCost,
    double? avgCost,
    double? sellingPrice,
    String? supplier,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isBadStock,
    double? badStockQuantity,
    List<StockLog>? stockLogs,
    bool? isActive,
    String? imageUrl,
    String? notes,
    ConsumptionMode? consumptionMode,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      description: description ?? this.description,
      brand: brand ?? this.brand,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      baseUnit: baseUnit ?? this.baseUnit,
      purchaseUnit: purchaseUnit ?? this.purchaseUnit,
      saleUnit: saleUnit ?? this.saleUnit,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      minStock: minStock ?? this.minStock,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      safetyStock: safetyStock ?? this.safetyStock,
      maxStock: maxStock ?? this.maxStock,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      unitCost: unitCost ?? this.unitCost,
      lastPurchaseCost: lastPurchaseCost ?? this.lastPurchaseCost,
      avgCost: avgCost ?? this.avgCost,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      supplier: supplier ?? this.supplier,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isBadStock: isBadStock ?? this.isBadStock,
      badStockQuantity: badStockQuantity ?? this.badStockQuantity,
      stockLogs: stockLogs ?? this.stockLogs,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      consumptionMode: consumptionMode ?? this.consumptionMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InventoryItem{id: $id, name: $name, category: $category, currentStock: $currentStock, unit: $unit}';
}
