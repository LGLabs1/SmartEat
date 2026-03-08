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
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

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
              : json['createdAt'].toDate())
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'])
              : json['updatedAt'].toDate())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
  }

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
  String toString() {
    return 'InventoryItem{id: $id, name: $name, category: $category, currentStock: $currentStock, unit: $unit}';
  }
}
