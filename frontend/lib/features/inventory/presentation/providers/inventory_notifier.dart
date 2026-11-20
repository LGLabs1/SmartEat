import 'package:flutter/foundation.dart';
import '../../data/repositories/inventory_remote_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../../../../models/inventory_item.dart';
import '../../domain/services/fifo_queue.dart';
import '../../domain/services/unit_conversion.dart';
import '../../data/models/stock_movement.dart';
import '../../data/models/purchase_receipt.dart';
import '../../data/models/stock_adjustment.dart';
import '../../data/models/menu_item_ingredient.dart';

class InventoryState {
  final List<InventoryItem> items;
  final List<StockMovement> movements;
  final List<PurchaseReceipt> purchases;
  final List<StockAdjustment> adjustments;
  final List<MenuItemIngredient> menuIngredients;
  final bool loading;
  final String? error;

  InventoryState({
    this.items = const [],
    this.movements = const [],
    this.purchases = const [],
    this.adjustments = const [],
    this.menuIngredients = const [],
    this.loading = false,
    this.error,
  });

  InventoryState copyWith({
    List<InventoryItem>? items,
    List<StockMovement>? movements,
    List<PurchaseReceipt>? purchases,
    List<StockAdjustment>? adjustments,
    List<MenuItemIngredient>? menuIngredients,
    bool? loading,
    String? error,
  }) {
    return InventoryState(
      items: items ?? this.items,
      movements: movements ?? this.movements,
      purchases: purchases ?? this.purchases,
      adjustments: adjustments ?? this.adjustments,
      menuIngredients: menuIngredients ?? this.menuIngredients,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class InventoryNotifier extends ChangeNotifier {
  InventoryNotifier({InventoryRepository? repository})
      : _repo = repository ?? InventoryRemoteRepository();

  final InventoryRepository _repo;
  InventoryState _state = InventoryState();
  InventoryState get state => _state;

  Future<void> load() async {
    _state = _state.copyWith(loading: true, error: null);
    notifyListeners();

    late final List<InventoryItem> items;
    try {
      items = await _repo.getInventoryItems();
    } catch (e) {
      _state = _state.copyWith(
        loading: false,
        error: 'Unable to load inventory items: $e',
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(items: items, loading: false);
    notifyListeners();

    String? error;
    List<MenuItemIngredient>? menu;
    List<StockMovement>? movements;
    List<PurchaseReceipt>? purchases;
    List<StockAdjustment>? adjustments;

    try {
      menu = await _repo.getMenuItemIngredients();
    } catch (e) {
      error = 'Menu links could not be refreshed: $e';
    }
    try {
      movements = await _repo.getStockMovements();
    } catch (e) {
      error ??= 'Stock movements could not be refreshed: $e';
    }
    try {
      purchases = await _repo.getPurchaseReceipts();
    } catch (e) {
      error ??= 'Purchases could not be refreshed: $e';
    }
    try {
      adjustments = await _repo.getStockAdjustments();
    } catch (e) {
      error ??= 'Adjustments could not be refreshed: $e';
    }

    _state = _state.copyWith(
      menuIngredients: menu,
      movements: movements,
      purchases: purchases,
      adjustments: adjustments,
      loading: false,
      error: error,
    );
    notifyListeners();
  }

  Future<void> applyPurchase(PurchaseReceipt receipt) async {
    try {
      await _repo.applyPurchase(receipt);
    } finally {
      // Always refresh, even if a later inventory update step failed, so the
      // recorded receipt shows up in the purchases history.
      await load();
    }
  }

  Future<void> applyAdjustment(StockAdjustment adjustment) async {
    await _repo.applyAdjustment(adjustment);
    await load();
  }

  Future<void> recordDirectSale(String itemId, double qtyBaseSold) async {
    await _repo.recordDirectSaleConsumption(
        itemId: itemId, qtyBaseSold: qtyBaseSold);
    await load();
  }

  double suggestedReorderQty(InventoryItem item) {
    final s = item.maxStock - item.currentStock;
    return s > 0 ? s : 0;
  }

  double computeValueFromLots(List<FifoLot> lots) {
    return FifoQueueService.computeTotalValue(lots);
  }

  double toBase(double qty, double factor) =>
      UnitConversion.toBase(qty, factor);
  double fromBase(double qtyBase, double factor) =>
      UnitConversion.fromBase(qtyBase, factor);
}
