import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/domain/services/menu_availability.dart';
import 'package:smarteat/features/inventory/domain/services/recipe_consumption.dart';

Map<String, dynamic> _inventory({
  required String id,
  required String name,
  required String unit,
  double stock = 10,
  double unitCost = 1,
}) {
  return {
    'id': id,
    'name': name,
    'unit': unit,
    'currentStock': stock,
    'unitCost': unitCost,
  };
}

Map<String, dynamic> _recipe({
  required String id,
  required List<Map<String, dynamic>> ingredients,
}) {
  return {
    'id': id,
    'name': 'Recipe $id',
    'baseServings': 1,
    'ingredients': ingredients,
  };
}

void main() {
  group('MenuAvailability direct inventory', () {
    test('uses current stock as available servings', () {
      final inventory = _inventory(
        id: 'bottle',
        name: 'Bottled Water',
        unit: 'bottle',
        stock: 7,
      );

      final result = MenuAvailability.resolve(
        menuItem: {
          'id': 'm1',
          'name': 'Water',
          'inventoryItemId': 'bottle',
        },
        inventoryById: RecipeConsumption.indexById([inventory]),
        recipeById: const {},
      );

      expect(result.isDirectLinked, isTrue);
      expect(result.availableServings, 7);
      expect(result.stockIssues, isEmpty);
      expect(result.blocksOrder, isFalse);
    });

    test('flags zero stock and blocks ordering', () {
      final inventory = _inventory(
        id: 'bottle',
        name: 'Bottled Water',
        unit: 'bottle',
        stock: 0,
      );

      final result = MenuAvailability.resolve(
        menuItem: {
          'id': 'm1',
          'name': 'Water',
          'inventoryItemId': 'bottle',
        },
        inventoryById: RecipeConsumption.indexById([inventory]),
        recipeById: const {},
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.severity, 'out_of_stock');
      expect(result.blocksOrder, isTrue);
    });

    test('flags missing inventory links', () {
      final result = MenuAvailability.resolve(
        menuItem: {
          'id': 'm1',
          'name': 'Water',
          'inventoryItemId': 'missing',
        },
        inventoryById: const {},
        recipeById: const {},
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.severity, 'missing');
      expect(result.blocksOrder, isTrue);
    });
  });

  group('MenuAvailability recipe links', () {
    test('uses the most limiting ingredient', () {
      final inventory = [
        _inventory(id: 'rice', name: 'Rice', unit: 'g', stock: 500),
        _inventory(id: 'egg', name: 'Egg', unit: 'pcs', stock: 3),
      ];
      final recipe = _recipe(
        id: 'r1',
        ingredients: [
          {
            'name': 'Rice',
            'inventoryItemId': 'rice',
            'unit': 'g',
            'quantityPerServing': 50,
          },
          {
            'name': 'Egg',
            'inventoryItemId': 'egg',
            'unit': 'pcs',
            'quantityPerServing': 1,
          },
        ],
      );

      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        inventoryById: RecipeConsumption.indexById(inventory),
        recipeById: RecipeConsumption.indexById([recipe]),
      );

      expect(result.isRecipeLinked, isTrue);
      expect(result.availableServings, 3);
      expect(result.stockIssues, isEmpty);
      expect(result.blocksOrder, isFalse);
    });

    test('flags zero-stock ingredients without auto-disabling availability',
        () {
      final inventory = [
        _inventory(id: 'rice', name: 'Rice', unit: 'g', stock: 500),
        _inventory(id: 'egg', name: 'Egg', unit: 'pcs', stock: 0),
      ];
      final recipe = _recipe(
        id: 'r1',
        ingredients: [
          {
            'name': 'Rice',
            'inventoryItemId': 'rice',
            'unit': 'g',
            'quantityPerServing': 50,
          },
          {
            'name': 'Egg',
            'inventoryItemId': 'egg',
            'unit': 'pcs',
            'quantityPerServing': 1,
          },
        ],
      );

      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        inventoryById: RecipeConsumption.indexById(inventory),
        recipeById: RecipeConsumption.indexById([recipe]),
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.name, 'Egg');
      expect(result.stockIssues.single.severity, 'out_of_stock');
      expect(result.blocksOrder, isTrue);
    });

    test('flags missing ingredients', () {
      final recipe = _recipe(
        id: 'r1',
        ingredients: [
          {
            'name': 'Missing Rice',
            'inventoryItemId': 'missing',
            'unit': 'g',
            'quantityPerServing': 50,
          },
        ],
      );

      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        inventoryById: const {},
        recipeById: RecipeConsumption.indexById([recipe]),
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.severity, 'missing');
      expect(result.blocksOrder, isTrue);
    });

    test('flags insufficient stock for one serving', () {
      final inventory = [
        _inventory(id: 'rice', name: 'Rice', unit: 'g', stock: 25),
      ];
      final recipe = _recipe(
        id: 'r1',
        ingredients: [
          {
            'name': 'Rice',
            'inventoryItemId': 'rice',
            'unit': 'g',
            'quantityPerServing': 50,
          },
        ],
      );

      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        inventoryById: RecipeConsumption.indexById(inventory),
        recipeById: RecipeConsumption.indexById([recipe]),
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.severity, 'insufficient');
      expect(result.blocksOrder, isTrue);
    });

    test('flags incompatible recipe and inventory units', () {
      final inventory = [
        _inventory(id: 'rice', name: 'Rice', unit: 'g', stock: 500),
      ];
      final recipe = _recipe(
        id: 'r1',
        ingredients: [
          {
            'name': 'Rice',
            'inventoryItemId': 'rice',
            'unit': 'ml',
            'quantityPerServing': 50,
          },
        ],
      );

      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        inventoryById: RecipeConsumption.indexById(inventory),
        recipeById: RecipeConsumption.indexById([recipe]),
      );

      expect(result.availableServings, 0);
      expect(result.stockIssues.single.severity, 'incompatible');
      expect(result.blocksOrder, isTrue);
    });
  });

  group('MenuAvailability no link', () {
    test('does not create stock limits', () {
      final result = MenuAvailability.resolve(
        menuItem: {'id': 'm1', 'name': 'Manual Item'},
        inventoryById: const {},
        recipeById: const {},
      );

      expect(result.isLinked, isFalse);
      expect(result.availableServings, isNull);
      expect(result.stockIssues, isEmpty);
      expect(result.blocksOrder, isFalse);
    });
  });

  group('MenuAvailability.applyTo', () {
    test('writes derived fields without changing manual availability', () {
      final inventory = _inventory(
        id: 'bottle',
        name: 'Bottled Water',
        unit: 'bottle',
        stock: 0,
      );
      final item = <String, dynamic>{
        'id': 'm1',
        'name': 'Water',
        'inventoryItemId': 'bottle',
        'isAvailable': true,
      };

      final result = MenuAvailability.resolve(
        menuItem: item,
        inventoryById: RecipeConsumption.indexById([inventory]),
        recipeById: const {},
      );
      MenuAvailability.applyTo(item, result);

      expect(item['availableServings'], 0);
      expect(item['isAvailable'], isTrue);
      expect(item['stockIssues'], isNotEmpty);
      expect(item['stockIssueSummary'], 'Bottled Water');
    });
  });

  group('menuUnavailabilityReason', () {
    test('is empty for available items', () {
      expect(
        menuUnavailabilityReason({
          'name': 'Water',
          'isAvailable': true,
          'inventoryItemId': 'bottle',
          'availableServings': 5,
        }),
        isEmpty,
      );
    });

    test('uses the shared no-reason label for manual admin toggle', () {
      expect(
        menuUnavailabilityReason({'name': 'Water', 'isAvailable': false}),
        menuNoUnavailabilityReason,
      );
    });

    test('uses out of stock summary when stock caused unavailability', () {
      expect(
        menuUnavailabilityReason({
          'isAvailable': false,
          'inventoryItemId': 'bottle',
          'availableServings': 0,
          'stockIssues': [
            {'name': 'Bottled Water', 'severity': 'out_of_stock'},
          ],
          'stockIssueSummary': 'Bottled Water',
        }),
        'Out of stock: Bottled Water',
      );
    });

    test('uses insufficient stock wording for insufficient ingredients', () {
      expect(
        menuUnavailabilityReason({
          'isAvailable': true,
          'recipeId': 'recipe',
          'availableServings': 0,
          'stockIssues': [
            {'name': 'Rice', 'severity': 'insufficient'},
          ],
        }),
        'Not enough stock: Rice',
      );
    });

    test('derives a reason from issue names when summary is missing', () {
      expect(
        menuUnavailabilityReason({
          'isAvailable': false,
          'recipeId': 'recipe',
          'availableServings': 0,
          'stockIssues': [
            {'name': 'Egg', 'severity': 'out_of_stock'},
            {'name': 'Milk', 'severity': 'out_of_stock'},
          ],
        }),
        'Out of stock: Egg, Milk',
      );
    });
  });
}
