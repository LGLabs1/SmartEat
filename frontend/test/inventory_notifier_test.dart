import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/data/models/menu_item_ingredient.dart';
import 'package:smarteat/features/inventory/data/models/purchase_receipt.dart';
import 'package:smarteat/features/inventory/data/models/stock_adjustment.dart';
import 'package:smarteat/features/inventory/data/models/stock_movement.dart';
import 'package:smarteat/features/inventory/data/repositories/inventory_repository.dart';
import 'package:smarteat/features/inventory/domain/services/fifo_queue.dart';
import 'package:smarteat/features/inventory/domain/usecases/reports.dart';
import 'package:smarteat/features/inventory/presentation/providers/inventory_notifier.dart';
import 'package:smarteat/models/inventory_item.dart';

void main() {
  test('keeps loaded items when an auxiliary refresh fails', () async {
    final repository = _FakeInventoryRepository(
      items: [
        InventoryItem(
          id: 'rice',
          name: 'Rice',
          category: 'Grains',
          currentStock: 12,
          unit: 'kg',
          minStock: 2,
          unitCost: 50,
        ),
      ],
      throwMovements: true,
    );
    final notifier = InventoryNotifier(repository: repository);

    await notifier.load();

    expect(notifier.state.items, hasLength(1));
    expect(notifier.state.items.single.name, 'Rice');
    expect(notifier.state.loading, isFalse);
    expect(notifier.state.error, contains('Stock movements'));
  });

  test('parses inventory rows with non-numeric and malformed fields', () {
    final item = InventoryItem.fromJson({
      'id': 42,
      'name': 'Frozen Peas',
      'category': 'Frozen',
      'currentStock': '8.5',
      'unitCost': '12.25',
      'minStock': null,
      'tags': 'invalid',
      'createdAt': 'not-a-date',
      'stockLogs': [
        {'timestamp': 'not-a-date', 'change': '2.5', 'reason': 'count'},
        'invalid-row',
      ],
    });

    expect(item.id, '42');
    expect(item.currentStock, 8.5);
    expect(item.unitCost, 12.25);
    expect(item.minStock, 0);
    expect(item.tags, isEmpty);
    expect(item.stockLogs, hasLength(1));
    expect(item.stockLogs.single.change, 2.5);
  });

  test('suggests restock from reorder levels when max stock is missing', () {
    final lowStock = InventoryItem(
      id: 'rice',
      name: 'Rice',
      category: 'Grains',
      currentStock: 4,
      unit: 'kg',
      minStock: 10,
      unitCost: 50,
    );
    final outOfStock = InventoryItem(
      id: 'oil',
      name: 'Oil',
      category: 'Cooking',
      currentStock: 0,
      unit: 'L',
      minStock: 0,
      unitCost: 80,
    );
    final healthy = InventoryItem(
      id: 'beans',
      name: 'Beans',
      category: 'Legumes',
      currentStock: 12,
      unit: 'kg',
      minStock: 5,
      unitCost: 60,
    );

    final suggestions = RestockSuggestionsUseCase().compute([
      lowStock,
      outOfStock,
      healthy,
    ]);

    expect(suggestions.map((s) => s.item.id), ['rice', 'oil']);
    expect(suggestions.first.suggestedQtyBase, 6);
    expect(suggestions.last.suggestedQtyBase, 1);

    final notifier = InventoryNotifier(
      repository: _FakeInventoryRepository(),
    );
    expect(notifier.suggestedReorderQty(lowStock), 6);
    expect(notifier.suggestedReorderQty(healthy), 0);
  });
}

class _FakeInventoryRepository implements InventoryRepository {
  _FakeInventoryRepository({
    this.items = const [],
    this.throwMovements = false,
  });

  final List<InventoryItem> items;
  final bool throwMovements;

  @override
  Future<List<InventoryItem>> getInventoryItems() async => items;

  @override
  Future<List<StockMovement>> getStockMovements({String? itemId}) async {
    if (throwMovements) throw StateError('movements unavailable');
    return const [];
  }

  @override
  Future<List<PurchaseReceipt>> getPurchaseReceipts() async => const [];

  @override
  Future<List<StockAdjustment>> getStockAdjustments() async => const [];

  @override
  Future<void> applyPurchase(PurchaseReceipt receipt) async {}

  @override
  Future<void> applyAdjustment(StockAdjustment adjustment) async {}

  @override
  Future<void> recordDirectSaleConsumption({
    required String itemId,
    required double qtyBaseSold,
    String? referenceId,
    String? performedBy,
  }) async {}

  @override
  Future<List<FifoLot>> getFifoLots(String itemId) async => const [];

  @override
  Future<void> saveFifoLots(String itemId, List<FifoLot> lots) async {}

  @override
  Future<List<MenuItemIngredient>> getMenuItemIngredients() async => const [];
}
