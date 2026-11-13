class MenuItemIngredient {
  final String menuItemId;
  final String ingredientItemId;
  final double qtyPerMenuUnitBase;

  MenuItemIngredient({
    required this.menuItemId,
    required this.ingredientItemId,
    required this.qtyPerMenuUnitBase,
  });

  factory MenuItemIngredient.fromJson(Map<String, dynamic> json) {
    return MenuItemIngredient(
      menuItemId: json['menuItemId'] ?? '',
      ingredientItemId: json['ingredientItemId'] ?? '',
      qtyPerMenuUnitBase: (json['qtyPerMenuUnitBase'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'ingredientItemId': ingredientItemId,
        'qtyPerMenuUnitBase': qtyPerMenuUnitBase,
      };
}
