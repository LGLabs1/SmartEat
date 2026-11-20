import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/domain/services/recipe_consumption.dart';

Map<String, dynamic> _inventory({
  required String id,
  required String name,
  required String unit,
  double stock = 1000,
  double unitCost = 100,
}) {
  return {
    'id': id,
    'name': name,
    'unit': unit,
    'currentStock': stock,
    'unitCost': unitCost,
  };
}

void main() {
  group('RecipeConsumption.normalizeRecipe', () {
    test('converts legacy batch quantities to per-serving values', () {
      final recipe = RecipeConsumption.normalizeRecipe({
        'name': 'Chicken Rice',
        'batchYield': 10,
        'ingredients': [
          {
            'name': 'Rice',
            'inventoryItemId': 'rice',
            'unit': 'g',
            'quantity': 500,
            'unitCost': 0.1,
          },
        ],
      });

      expect(recipe['baseServings'], 1.0);
      expect(recipe['batchYield'], 1.0);
      final ingredient =
          (recipe['ingredients'] as List).single as Map<String, dynamic>;
      expect(ingredient['quantityPerServing'], closeTo(50, 0.0001));
      expect(ingredient['quantity'], closeTo(50, 0.0001));
      expect(ingredient['totalCost'], closeTo(5, 0.0001));
      expect(recipe['batchCost'], closeTo(5, 0.0001));
      expect(recipe['costPerServing'], closeTo(5, 0.0001));
    });

    test('keeps already-normalized per-serving quantities', () {
      final recipe = RecipeConsumption.normalizeRecipe({
        'baseServings': 1,
        'ingredients': [
          {
            'name': 'Rice',
            'unit': 'g',
            'quantityPerServing': 75,
            'quantity': 75,
            'unitCost': 0.2,
          },
        ],
      });

      final ingredient =
          (recipe['ingredients'] as List).single as Map<String, dynamic>;
      expect(ingredient['quantityPerServing'], 75);
      expect(recipe['costPerServing'], closeTo(15, 0.0001));
    });
  });

  group('RecipeConsumption.buildPlan', () {
    test('converts recipe units and multiplies by order quantity', () {
      final inventory = _inventory(
        id: 'rice',
        name: 'Rice',
        unit: 'g',
        stock: 500,
        unitCost: 0.1,
      );
      final plan = RecipeConsumption.buildPlan(
        orderItems: [
          {'menuItemId': 'm1', 'quantity': 2},
        ],
        menuById: {
          'm1': {'id': 'm1', 'name': 'Chicken Rice', 'recipeId': 'r1'},
        },
        recipeById: {
          'r1': {
            'id': 'r1',
            'baseServings': 1,
            'ingredients': [
              {
                'name': 'Rice',
                'inventoryItemId': 'rice',
                'unit': 'kg',
                'quantityPerServing': 0.05,
              },
            ],
          },
        },
        inventoryById: RecipeConsumption.indexById([inventory]),
        inventoryByName: RecipeConsumption.indexByName([inventory]),
      );

      expect(plan.requiredByInventoryId['rice'], closeTo(100, 0.0001));
      expect(plan.perServingByMenuId['m1']?['rice'], closeTo(50, 0.0001));
      expect(plan.recipeMenuItemIds, contains('m1'));
      expect(plan.lines.single.quantityBase, closeTo(100, 0.0001));
      expect(plan.lines.single.source, 'recipe');
    });

    test('resolves ingredients by normalized name', () {
      final inventory = _inventory(
        id: 'rice',
        name: 'Jasmine  Rice',
        unit: 'g',
      );
      final plan = RecipeConsumption.buildPlan(
        orderItems: [
          {'menuItemId': 'm1', 'quantity': 1},
        ],
        menuById: {
          'm1': {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        },
        recipeById: {
          'r1': {
            'ingredients': [
              {
                'name': ' jasmine rice ',
                'unit': 'g',
                'quantityPerServing': 80,
              },
            ],
          },
        },
        inventoryById: RecipeConsumption.indexById([inventory]),
        inventoryByName: RecipeConsumption.indexByName([inventory]),
      );

      expect(plan.requiredByInventoryId['rice'], closeTo(80, 0.0001));
    });

    test('supports direct inventory links', () {
      final inventory = _inventory(
        id: 'bottle',
        name: 'Bottled Water',
        unit: 'bottle',
      );
      final plan = RecipeConsumption.buildPlan(
        orderItems: [
          {'menuItemId': 'm1', 'quantity': 3},
        ],
        menuById: {
          'm1': {
            'id': 'm1',
            'name': 'Bottled Water',
            'inventoryItemId': 'bottle',
          },
        },
        recipeById: const {},
        inventoryById: RecipeConsumption.indexById([inventory]),
      );

      expect(plan.requiredByInventoryId['bottle'], 3);
      expect(plan.lines.single.source, 'direct');
      expect(plan.perServingByMenuId, isEmpty);
    });

    test('throws when an ingredient inventory item is missing', () {
      expect(
        () => RecipeConsumption.buildPlan(
          orderItems: [
            {'menuItemId': 'm1', 'quantity': 1},
          ],
          menuById: {
            'm1': {'id': 'm1', 'name': 'Rice', 'recipeId': 'r1'},
          },
          recipeById: {
            'r1': {
              'ingredients': [
                {
                  'name': 'Missing Rice',
                  'inventoryItemId': 'missing',
                  'unit': 'g',
                  'quantityPerServing': 50,
                },
              ],
            },
          },
          inventoryById: const {},
        ),
        throwsA(isA<RecipeConsumptionException>()),
      );
    });

    test('throws when recipe and inventory units are incompatible', () {
      final inventory = _inventory(id: 'rice', name: 'Rice', unit: 'g');
      expect(
        () => RecipeConsumption.buildPlan(
          orderItems: [
            {'menuItemId': 'm1', 'quantity': 1},
          ],
          menuById: {
            'm1': {'id': 'm1', 'name': 'Rice', 'recipeId': 'r1'},
          },
          recipeById: {
            'r1': {
              'ingredients': [
                {
                  'name': 'Rice',
                  'inventoryItemId': 'rice',
                  'unit': 'ml',
                  'quantityPerServing': 50,
                },
              ],
            },
          },
          inventoryById: RecipeConsumption.indexById([inventory]),
        ),
        throwsA(isA<RecipeConsumptionException>()),
      );
    });
  });

  group('RecipeConsumption.remainingServings', () {
    test('uses the most limiting ingredient', () {
      final inventory = [
        _inventory(id: 'rice', name: 'Rice', unit: 'g', stock: 500),
        _inventory(id: 'egg', name: 'Egg', unit: 'pcs', stock: 3),
      ];
      final plan = RecipeConsumption.buildPlan(
        orderItems: [
          {'menuItemId': 'm1', 'quantity': 1},
        ],
        menuById: {
          'm1': {'id': 'm1', 'name': 'Rice Bowl', 'recipeId': 'r1'},
        },
        recipeById: {
          'r1': {
            'ingredients': [
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
          },
        },
        inventoryById: RecipeConsumption.indexById(inventory),
        inventoryByName: RecipeConsumption.indexByName(inventory),
      );

      final remaining = RecipeConsumption.remainingServings(
        plan: plan,
        nextStockById: {'rice': 500, 'egg': 3},
      );
      expect(remaining['m1'], 3);
    });
  });

  group('RecipeConsumption.costPerRecipeUnit', () {
    test('uses the inventory unit cost and conversion', () {
      final cost = RecipeConsumption.costPerRecipeUnit(
        inventoryItem: _inventory(
          id: 'rice',
          name: 'Rice',
          unit: 'kg',
          unitCost: 120,
        ),
        recipeUnit: 'g',
      );
      expect(cost, closeTo(0.12, 0.0001));
    });
  });
}
