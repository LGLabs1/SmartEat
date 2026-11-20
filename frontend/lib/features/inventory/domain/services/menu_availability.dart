import 'dart:math' as math;

import 'recipe_consumption.dart';
import 'unit_conversion.dart';

class MenuStockIssue {
  const MenuStockIssue({
    required this.name,
    required this.severity,
    required this.message,
    this.requiredQuantity,
    this.currentStock,
    this.unit = '',
  });

  final String name;
  final String severity;
  final String message;
  final double? requiredQuantity;
  final double? currentStock;
  final String unit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'severity': severity,
        'message': message,
        if (requiredQuantity != null) 'requiredQuantity': requiredQuantity,
        if (currentStock != null) 'currentStock': currentStock,
        if (unit.isNotEmpty) 'unit': unit,
      };
}

class MenuAvailabilityResult {
  const MenuAvailabilityResult({
    required this.availableServings,
    required this.stockIssues,
    required this.isDirectLinked,
    required this.isRecipeLinked,
  });

  final int? availableServings;
  final List<MenuStockIssue> stockIssues;
  final bool isDirectLinked;
  final bool isRecipeLinked;

  bool get isLinked => isDirectLinked || isRecipeLinked;
  bool get hasStockIssues => stockIssues.isNotEmpty;
  bool get blocksOrder =>
      isLinked && ((availableServings ?? 0) <= 0 || hasStockIssues);

  String get issueSummary {
    final names = stockIssues
        .map((issue) => issue.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (names.isEmpty) return '';
    return names.take(3).join(', ');
  }
}

class MenuAvailability {
  static MenuAvailabilityResult resolve({
    required Map<String, dynamic> menuItem,
    required Map<String, Map<String, dynamic>> inventoryById,
    required Map<String, Map<String, dynamic>> recipeById,
    Map<String, Map<String, dynamic>>? inventoryByName,
  }) {
    final inventoryItemId =
        (menuItem['inventoryItemId'] ?? '').toString().trim();
    final recipeId = (menuItem['recipeId'] ?? '').toString().trim();

    if (recipeId.isNotEmpty) {
      return _resolveRecipe(
        recipeId: recipeId,
        inventoryById: inventoryById,
        recipeById: recipeById,
        inventoryByName: inventoryByName ??
            RecipeConsumption.indexByName(inventoryById.values),
      );
    }

    if (inventoryItemId.isNotEmpty) {
      return _resolveDirect(
        inventoryItemId: inventoryItemId,
        inventoryById: inventoryById,
      );
    }

    return const MenuAvailabilityResult(
      availableServings: null,
      stockIssues: <MenuStockIssue>[],
      isDirectLinked: false,
      isRecipeLinked: false,
    );
  }

  static Map<String, MenuAvailabilityResult> resolveAll({
    required List<Map<String, dynamic>> menuItems,
    required List<Map<String, dynamic>> inventoryItems,
    required List<Map<String, dynamic>> recipes,
  }) {
    final inventoryById = RecipeConsumption.indexById(inventoryItems);
    final inventoryByName = RecipeConsumption.indexByName(inventoryItems);
    final recipeById = RecipeConsumption.indexById(recipes);
    final results = <String, MenuAvailabilityResult>{};

    for (final item in menuItems) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      results[id] = resolve(
        menuItem: item,
        inventoryById: inventoryById,
        inventoryByName: inventoryByName,
        recipeById: recipeById,
      );
    }

    return results;
  }

  static void applyTo(
    Map<String, dynamic> menuItem,
    MenuAvailabilityResult result,
  ) {
    menuItem['availableServings'] = result.availableServings;
    menuItem['stockIssues'] =
        result.stockIssues.map((issue) => issue.toJson()).toList();
    menuItem['stockIssueSummary'] = result.issueSummary;
    menuItem['isDirectInventoryLinked'] = result.isDirectLinked;
    menuItem['isRecipeLinked'] = result.isRecipeLinked;
  }

  static MenuAvailabilityResult _resolveDirect({
    required String inventoryItemId,
    required Map<String, Map<String, dynamic>> inventoryById,
  }) {
    final inventoryItem = inventoryById[inventoryItemId];
    if (inventoryItem == null) {
      return const MenuAvailabilityResult(
        availableServings: 0,
        stockIssues: [
          MenuStockIssue(
            name: 'Inventory item',
            severity: 'missing',
            message: 'Linked inventory item was not found',
          ),
        ],
        isDirectLinked: true,
        isRecipeLinked: false,
      );
    }

    final name = (inventoryItem['name'] ?? 'Inventory item').toString();
    final unit = (inventoryItem['unit'] ?? '').toString();
    final stock = _asDouble(inventoryItem['currentStock']);
    final issues = <MenuStockIssue>[];

    if (stock <= 0) {
      issues.add(MenuStockIssue(
        name: name,
        severity: 'out_of_stock',
        message: 'Out of stock',
        currentStock: stock,
        unit: unit,
      ));
    } else if (stock < 1) {
      issues.add(MenuStockIssue(
        name: name,
        severity: 'insufficient',
        message: 'Not enough stock for one item',
        requiredQuantity: 1,
        currentStock: stock,
        unit: unit,
      ));
    }

    return MenuAvailabilityResult(
      availableServings: math.max(0, stock.floor()),
      stockIssues: issues,
      isDirectLinked: true,
      isRecipeLinked: false,
    );
  }

  static MenuAvailabilityResult _resolveRecipe({
    required String recipeId,
    required Map<String, Map<String, dynamic>> inventoryById,
    required Map<String, Map<String, dynamic>> recipeById,
    required Map<String, Map<String, dynamic>> inventoryByName,
  }) {
    final recipe = recipeById[recipeId];
    if (recipe == null) {
      return const MenuAvailabilityResult(
        availableServings: 0,
        stockIssues: [
          MenuStockIssue(
            name: 'Recipe',
            severity: 'missing',
            message: 'Linked recipe was not found',
          ),
        ],
        isDirectLinked: false,
        isRecipeLinked: true,
      );
    }

    final normalized = RecipeConsumption.normalizeRecipe(recipe);
    final rawIngredients = normalized['ingredients'];
    final ingredients = rawIngredients is List ? rawIngredients : const [];
    if (ingredients.isEmpty) {
      return const MenuAvailabilityResult(
        availableServings: 0,
        stockIssues: [
          MenuStockIssue(
            name: 'Recipe',
            severity: 'empty',
            message: 'Recipe has no ingredients',
          ),
        ],
        isDirectLinked: false,
        isRecipeLinked: true,
      );
    }

    final issues = <MenuStockIssue>[];
    double? limiting;

    for (final raw in ingredients) {
      if (raw is! Map) continue;
      final ingredient = Map<String, dynamic>.from(raw);
      final ingredientName = (ingredient['name'] ?? '').toString().trim();
      final ingredientId =
          (ingredient['inventoryItemId'] ?? '').toString().trim();
      final inventoryItem = _resolveInventory(
        ingredientId: ingredientId,
        ingredientName: ingredientName,
        inventoryById: inventoryById,
        inventoryByName: inventoryByName,
      );
      if (inventoryItem == null) {
        issues.add(MenuStockIssue(
          name: ingredientName.isEmpty ? 'Ingredient' : ingredientName,
          severity: 'missing',
          message: 'Ingredient was not found in inventory',
        ));
        limiting = 0;
        continue;
      }

      final inventoryName =
          (inventoryItem['name'] ?? ingredientName).toString();
      final inventoryUnit =
          (inventoryItem['unit'] ?? inventoryItem['baseUnit'] ?? '').toString();
      final recipeUnit =
          (ingredient['unit'] ?? inventoryUnit).toString().trim();
      final stock = _asDouble(inventoryItem['currentStock']);
      final quantityRaw =
          ingredient['quantityPerServing'] ?? ingredient['quantity'];
      final quantityPerServing = _asDouble(quantityRaw);

      if (stock <= 0) {
        issues.add(MenuStockIssue(
          name: inventoryName.isEmpty ? ingredientName : inventoryName,
          severity: 'out_of_stock',
          message: 'Out of stock',
          currentStock: stock,
          unit: inventoryUnit,
        ));
        limiting = 0;
        continue;
      }

      if (quantityPerServing <= 0) continue;

      final double quantityBase;
      try {
        quantityBase = _toInventoryUnit(
          quantity: quantityPerServing,
          recipeUnit: recipeUnit,
          inventoryUnit: inventoryUnit,
        );
      } on UnitConversionException {
        issues.add(MenuStockIssue(
          name: inventoryName.isEmpty ? ingredientName : inventoryName,
          severity: 'incompatible',
          message: 'Incompatible recipe and inventory units',
          requiredQuantity: quantityPerServing,
          currentStock: stock,
          unit: recipeUnit.isEmpty ? inventoryUnit : recipeUnit,
        ));
        limiting = 0;
        continue;
      }

      if (quantityBase <= 0) continue;

      final servings = stock / quantityBase;
      limiting = limiting == null ? servings : math.min(limiting, servings);
      if (servings < 1) {
        issues.add(MenuStockIssue(
          name: inventoryName.isEmpty ? ingredientName : inventoryName,
          severity: 'insufficient',
          message: 'Not enough stock for one serving',
          requiredQuantity: quantityBase,
          currentStock: stock,
          unit: inventoryUnit,
        ));
      }
    }

    return MenuAvailabilityResult(
      availableServings: limiting == null ? 0 : math.max(0, limiting.floor()),
      stockIssues: issues,
      isDirectLinked: false,
      isRecipeLinked: true,
    );
  }

  static Map<String, dynamic>? _resolveInventory({
    required String ingredientId,
    required String ingredientName,
    required Map<String, Map<String, dynamic>> inventoryById,
    required Map<String, Map<String, dynamic>> inventoryByName,
  }) {
    if (ingredientId.isNotEmpty) {
      final byId = inventoryById[ingredientId];
      if (byId != null) return byId;
    }
    if (ingredientName.isNotEmpty) {
      return inventoryByName[_normName(ingredientName)];
    }
    return null;
  }

  static double _toInventoryUnit({
    required double quantity,
    required String recipeUnit,
    required String inventoryUnit,
  }) {
    if (recipeUnit.isEmpty ||
        inventoryUnit.isEmpty ||
        UnitConversion.normalizeUnit(recipeUnit) ==
            UnitConversion.normalizeUnit(inventoryUnit)) {
      return quantity;
    }
    return UnitConversion.convert(quantity, recipeUnit, inventoryUnit);
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0.0;
  }

  static String _normName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
