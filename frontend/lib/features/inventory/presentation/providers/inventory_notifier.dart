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
  final InventoryRepository _repo = InventoryRemoteRepository();
  InventoryState _state = InventoryState();
  InventoryState get state => _state;

  Future<void> load() async {
    _state = _state.copyWith(loading: true, error: null);
    notifyListeners();
    try {
      final items = await _repo.getInventoryItems();
      final menu = await _repo.getMenuItemIngredients();
      final movements = await _repo.getStockMovements();
      final purchases = await _repo.getPurchaseReceipts();
      final adjustments = await _repo.getStockAdjustments();
      _state = _state.copyWith(
        items: items,
        menuIngredients: menu,
        movements: movements,
        purchases: purchases,
        adjustments: adjustments,
        loading: false,
      );
    } catch (e) {
      _state = _state.copyWith(loading: false, error: e.toString());
    }
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
    await _repo.recordDirectSaleConsumption(itemId: itemId, qtyBaseSold: qtyBaseSold);
    await load();
  }

  double suggestedReorderQty(InventoryItem item) {
    final s = item.maxStock - item.currentStock;
    return s > 0 ? s : 0;
  }

  double computeValueFromLots(List<FifoLot> lots) {
    return FifoQueueService.computeTotalValue(lots);
  }

  double toBase(double qty, double factor) => UnitConversion.toBase(qty, factor);
  double fromBase(double qtyBase, double factor) => UnitConversion.fromBase(qtyBase, factor);
}
