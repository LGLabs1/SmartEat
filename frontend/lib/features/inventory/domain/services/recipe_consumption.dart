import 'dart:math' as math;

import 'unit_conversion.dart';

class RecipeConsumptionException implements Exception {
  const RecipeConsumptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RecipeConsumptionLine {
  const RecipeConsumptionLine({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.inventoryUnit,
    required this.quantityBase,
    required this.menuItemId,
    required this.menuQuantity,
    required this.source,
    this.recipeId = '',
    this.recipeUnit = '',
  });

  final String inventoryItemId;
  final String inventoryItemName;
  final String inventoryUnit;
  final double quantityBase;
  final String menuItemId;
  final int menuQuantity;
  final String source;
  final String recipeId;
  final String recipeUnit;

  Map<String, dynamic> toJson() => {
        'inventoryItemId': inventoryItemId,
        'inventoryItemName': inventoryItemName,
        'inventoryUnit': inventoryUnit,
        'quantityBase': quantityBase,
        'menuItemId': menuItemId,
        'menuQuantity': menuQuantity,
        'source': source,
        if (recipeId.isNotEmpty) 'recipeId': recipeId,
        if (recipeUnit.isNotEmpty) 'recipeUnit': recipeUnit,
      };
}

class RecipeConsumptionPlan {
  const RecipeConsumptionPlan({
    required this.lines,
    required this.requiredByInventoryId,
    required this.perServingByMenuId,
    required this.inventoryNameById,
    required this.inventoryUnitById,
    required this.recipeMenuItemIds,
  });

  final List<RecipeConsumptionLine> lines;
  final Map<String, double> requiredByInventoryId;
  final Map<String, Map<String, double>> perServingByMenuId;
  final Map<String, String> inventoryNameById;
  final Map<String, String> inventoryUnitById;
  final Set<String> recipeMenuItemIds;

  List<Map<String, dynamic>> toJsonLines() =>
      lines.map((line) => line.toJson()).toList();
}

class RecipeConsumption {
  static double recipeYield(Map<String, dynamic> recipe) {
    final raw = recipe['baseServings'] ?? recipe['batchYield'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 1.0;
    return value > 0 ? value : 1.0;
  }

  static Map<String, dynamic> normalizeRecipe(Map<String, dynamic> recipe) {
    final normalized = Map<String, dynamic>.from(recipe);
    final yieldValue = recipeYield(recipe);
    final rawIngredients = recipe['ingredients'];
    final ingredients = <Map<String, dynamic>>[];

    if (rawIngredients is List) {
      for (final raw in rawIngredients) {
        if (raw is! Map) continue;
        final ingredient = Map<String, dynamic>.from(raw);
        final perServingRaw = ingredient['quantityPerServing'];
        final batchQtyRaw = ingredient['quantity'];
        final batchQty = batchQtyRaw is num
            ? batchQtyRaw.toDouble()
            : double.tryParse(batchQtyRaw?.toString() ?? '') ?? 0.0;
        final perServing = perServingRaw is num
            ? perServingRaw.toDouble()
            : double.tryParse(perServingRaw?.toString() ?? '') ??
                (batchQty / yieldValue);
        final unitCostRaw = ingredient['unitCost'];
        final unitCost = unitCostRaw is num
            ? unitCostRaw.toDouble()
            : double.tryParse(unitCostRaw?.toString() ?? '') ?? 0.0;
        ingredient['quantity'] = perServing;
        ingredient['quantityPerServing'] = perServing;
        ingredient['unitCost'] = unitCost;
        ingredient['totalCost'] = perServing * unitCost;
        ingredients.add(ingredient);
      }
    }

    final batchCost = ingredients.fold<double>(
      0,
      (sum, ingredient) =>
          sum + ((ingredient['totalCost'] as num?)?.toDouble() ?? 0.0),
    );

    normalized['ingredients'] = ingredients;
    normalized['baseServings'] = 1.0;
    normalized['batchYield'] = 1.0;
    normalized['batchCost'] = batchCost;
    normalized['costPerServing'] = batchCost;
    normalized['costingMethod'] = normalized['costingMethod'] ?? 'recipe';
    normalized['costSource'] = normalized['costSource'] ?? 'recipe_calculated';
    return normalized;
  }

  static double costPerRecipeUnit({
    required Map<String, dynamic> inventoryItem,
    required String recipeUnit,
  }) {
    final inventoryUnit =
        (inventoryItem['unit'] ?? inventoryItem['baseUnit'] ?? recipeUnit)
            .toString();
    final inventoryUnitCost = (inventoryItem['unitCost'] as num?)?.toDouble() ??
        double.tryParse(inventoryItem['unitCost']?.toString() ?? '') ??
        0.0;
    if (inventoryUnit.isEmpty || recipeUnit.isEmpty) return inventoryUnitCost;
    return UnitConversion.costPerUnit(
      inventoryUnitCost: inventoryUnitCost,
      inventoryUnit: inventoryUnit,
      recipeUnit: recipeUnit,
    );
  }

  static RecipeConsumptionPlan buildPlan({
    required List<Map<String, dynamic>> orderItems,
    required Map<String, Map<String, dynamic>> menuById,
    required Map<String, Map<String, dynamic>> recipeById,
    required Map<String, Map<String, dynamic>> inventoryById,
    Map<String, Map<String, dynamic>> inventoryByName = const {},
  }) {
    final lines = <RecipeConsumptionLine>[];
    final requiredByInventoryId = <String, double>{};
    final perServingByMenuId = <String, Map<String, double>>{};
    final inventoryNameById = <String, String>{};
    final inventoryUnitById = <String, String>{};
    final recipeMenuItemIds = <String>{};

    for (final raw in orderItems) {
      final menuItemId = (raw['menuItemId'] ?? '').toString().trim();
      final quantityRaw = raw['quantity'];
      final quantity = quantityRaw is num
          ? quantityRaw.toInt()
          : int.tryParse(quantityRaw?.toString() ?? '') ?? 0;
      if (menuItemId.isEmpty || quantity <= 0) continue;

      final menu = menuById[menuItemId];
      if (menu == null) {
        throw RecipeConsumptionException(
          'Menu item not found (id: $menuItemId).',
        );
      }

      final recipeId = (menu['recipeId'] ?? '').toString().trim();
      if (recipeId.isNotEmpty) {
        final recipe = recipeById[recipeId];
        if (recipe == null) {
          throw RecipeConsumptionException(
            'Recipe not found for ${(menu['name'] ?? 'menu item').toString()} '
            '(id: $recipeId).',
          );
        }
        recipeMenuItemIds.add(menuItemId);
        final perServing = perServingByMenuId.putIfAbsent(
          menuItemId,
          () => <String, double>{},
        );
        final normalizedRecipe = normalizeRecipe(recipe);
        final ingredients = normalizedRecipe['ingredients'] as List;

        for (final rawIngredient in ingredients) {
          final ingredient = rawIngredient as Map<String, dynamic>;
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
            throw RecipeConsumptionException(
              'Missing inventory item: ${ingredientName.isEmpty ? ingredientId : ingredientName}',
            );
          }

          final resolvedInventoryId =
              (inventoryItem['id'] ?? ingredientId).toString();
          final inventoryUnit =
              (inventoryItem['unit'] ?? inventoryItem['baseUnit'] ?? '')
                  .toString();
          final recipeUnit = (ingredient['unit'] ?? inventoryUnit).toString();
          final perServingQtyRaw =
              ingredient['quantityPerServing'] ?? ingredient['quantity'];
          final perServingQty = perServingQtyRaw is num
              ? perServingQtyRaw.toDouble()
              : double.tryParse(perServingQtyRaw?.toString() ?? '') ?? 0.0;
          if (perServingQty <= 0) continue;

          final qtyBasePerServing = _toInventoryUnit(
            quantity: perServingQty,
            recipeUnit: recipeUnit,
            inventoryUnit: inventoryUnit,
            ingredientName: ingredientName,
          );
          final totalQtyBase = qtyBasePerServing * quantity;

          perServing[resolvedInventoryId] =
              (perServing[resolvedInventoryId] ?? 0.0) + qtyBasePerServing;
          requiredByInventoryId[resolvedInventoryId] =
              (requiredByInventoryId[resolvedInventoryId] ?? 0.0) +
                  totalQtyBase;
          inventoryNameById[resolvedInventoryId] =
              (inventoryItem['name'] ?? ingredientName).toString();
          inventoryUnitById[resolvedInventoryId] = inventoryUnit;

          lines.add(RecipeConsumptionLine(
            inventoryItemId: resolvedInventoryId,
            inventoryItemName:
                (inventoryItem['name'] ?? ingredientName).toString(),
            inventoryUnit: inventoryUnit,
            quantityBase: totalQtyBase,
            menuItemId: menuItemId,
            menuQuantity: quantity,
            source: 'recipe',
            recipeId: recipeId,
            recipeUnit: recipeUnit,
          ));
        }
        continue;
      }

      final directInventoryId =
          (menu['inventoryItemId'] ?? '').toString().trim();
      if (directInventoryId.isEmpty) continue;
      final inventoryItem = inventoryById[directInventoryId];
      if (inventoryItem == null) {
        throw RecipeConsumptionException(
          'Inventory item not found for ${(menu['name'] ?? 'menu item').toString()}.',
        );
      }
      final inventoryUnit =
          (inventoryItem['unit'] ?? inventoryItem['baseUnit'] ?? '').toString();
      final totalQtyBase = quantity.toDouble();
      requiredByInventoryId[directInventoryId] =
          (requiredByInventoryId[directInventoryId] ?? 0.0) + totalQtyBase;
      inventoryNameById[directInventoryId] =
          (inventoryItem['name'] ?? '').toString();
      inventoryUnitById[directInventoryId] = inventoryUnit;

      lines.add(RecipeConsumptionLine(
        inventoryItemId: directInventoryId,
        inventoryItemName: (inventoryItem['name'] ?? '').toString(),
        inventoryUnit: inventoryUnit,
        quantityBase: totalQtyBase,
        menuItemId: menuItemId,
        menuQuantity: quantity,
        source: 'direct',
      ));
    }

    return RecipeConsumptionPlan(
      lines: lines,
      requiredByInventoryId: requiredByInventoryId,
      perServingByMenuId: perServingByMenuId,
      inventoryNameById: inventoryNameById,
      inventoryUnitById: inventoryUnitById,
      recipeMenuItemIds: recipeMenuItemIds,
    );
  }

  static Map<String, int> remainingServings({
    required RecipeConsumptionPlan plan,
    required Map<String, double> nextStockById,
  }) {
    final result = <String, int>{};
    for (final entry in plan.perServingByMenuId.entries) {
      double? limiting;
      for (final ingredient in entry.value.entries) {
        if (ingredient.value <= 0) continue;
        final stock = nextStockById[ingredient.key] ?? 0.0;
        final servings = stock / ingredient.value;
        limiting = limiting == null ? servings : math.min(limiting, servings);
      }
      if (limiting == null) continue;
      result[entry.key] = math.max(0, limiting.floor());
    }
    return result;
  }

  static Map<String, Map<String, dynamic>> indexByName(
    Iterable<Map<String, dynamic>> items,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final key = _normName((item['name'] ?? '').toString());
      if (key.isEmpty) continue;
      result.putIfAbsent(key, () => item);
    }
    return result;
  }

  static Map<String, Map<String, dynamic>> indexById(
    Iterable<Map<String, dynamic>> items,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      result[id] = item;
    }
    return result;
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
    required String ingredientName,
  }) {
    if (recipeUnit.trim().isEmpty ||
        inventoryUnit.trim().isEmpty ||
        UnitConversion.normalizeUnit(recipeUnit) ==
            UnitConversion.normalizeUnit(inventoryUnit)) {
      return quantity;
    }
    try {
      return UnitConversion.convert(quantity, recipeUnit, inventoryUnit);
    } on UnitConversionException catch (e) {
      throw RecipeConsumptionException(
        '${e.message} (${ingredientName.isEmpty ? 'ingredient' : ingredientName})',
      );
    }
  }

  static String _normName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
