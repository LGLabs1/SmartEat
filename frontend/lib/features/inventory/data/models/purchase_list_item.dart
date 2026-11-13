class PurchaseListItem {
  final String itemId;
  final String name;
  final String unit;
  final double qty;
  final double unitCost;
  final bool checked;

  PurchaseListItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitCost,
    this.checked = false,
  });

  double get lineCost => qty * unitCost;

  PurchaseListItem copyWith({
    String? itemId,
    String? name,
    String? unit,
    double? qty,
    double? unitCost,
    bool? checked,
  }) {
    return PurchaseListItem(
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      qty: qty ?? this.qty,
      unitCost: unitCost ?? this.unitCost,
      checked: checked ?? this.checked,
    );
  }

  factory PurchaseListItem.fromJson(Map<String, dynamic> json) {
    return PurchaseListItem(
      itemId: json['itemId'] ?? '',
      name: json['name'] ?? '',
      unit: json['unit'] ?? '',
      qty: (json['qty'] ?? 0).toDouble(),
      unitCost: (json['unitCost'] ?? 0).toDouble(),
      checked: json['checked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'unit': unit,
        'qty': qty,
        'unitCost': unitCost,
        'checked': checked,
      };
}
