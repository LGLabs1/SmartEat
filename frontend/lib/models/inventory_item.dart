import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StockLog {
  final DateTime timestamp;
  final double change;
  final String reason;

  StockLog({required this.timestamp, required this.change, required this.reason});

  factory StockLog.fromJson(Map<String, dynamic> json) => StockLog(
        timestamp: json['timestamp'] is String
            ? DateTime.parse(json['timestamp'])
            : (json['timestamp'] as Timestamp).toDate(),
        change: (json['change'] ?? 0).toDouble(),
        reason: json['reason'] ?? '',
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
  final String category;
  final double currentStock;
  final String unit;
  final double minStock;
  final double unitCost;
  final double sellingPrice;
  final String supplier;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBadStock;
  final double badStockQuantity;
  final List<StockLog> stockLogs;

  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.currentStock,
    required this.unit,
    required this.minStock,
    required this.unitCost,
    this.sellingPrice = 0,
    this.supplier = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isBadStock = false,
    this.badStockQuantity = 0,
    List<StockLog>? stockLogs,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        stockLogs = stockLogs ?? [];

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      currentStock: (json['currentStock'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      minStock: (json['minStock'] ?? 0).toDouble(),
      unitCost: (json['unitCost'] ?? 0).toDouble(),
      sellingPrice: (json['sellingPrice'] ?? 0).toDouble(),
      supplier: json['supplier'] ?? '',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'])
              : (json['createdAt'] as Timestamp).toDate())
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'])
              : (json['updatedAt'] as Timestamp).toDate())
          : DateTime.now(),
      isBadStock: json['isBadStock'] ?? false,
      badStockQuantity: (json['badStockQuantity'] ?? 0).toDouble(),
      stockLogs: (json['stockLogs'] as List<dynamic>?)
              ?.map((e) => StockLog.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'currentStock': currentStock,
        'unit': unit,
        'minStock': minStock,
        'unitCost': unitCost,
        'sellingPrice': sellingPrice,
        'supplier': supplier,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'isBadStock': isBadStock,
        'badStockQuantity': badStockQuantity,
        'stockLogs': stockLogs.map((e) => e.toJson()).toList(),
      };

  bool get isLowStock => currentStock <= minStock;
  double get totalValue => currentStock * unitCost;

  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    double? currentStock,
    String? unit,
    double? minStock,
    double? unitCost,
    double? sellingPrice,
    String? supplier,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isBadStock,
    double? badStockQuantity,
    List<StockLog>? stockLogs,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      minStock: minStock ?? this.minStock,
      unitCost: unitCost ?? this.unitCost,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      supplier: supplier ?? this.supplier,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isBadStock: isBadStock ?? this.isBadStock,
      badStockQuantity: badStockQuantity ?? this.badStockQuantity,
      stockLogs: stockLogs ?? this.stockLogs,
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
