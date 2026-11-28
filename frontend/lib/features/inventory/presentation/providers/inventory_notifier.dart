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
import '../../domain/usecases/reports.dart';

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
    final isInitialLoad = _state.items.isEmpty &&
        _state.movements.isEmpty &&
        _state.purchases.isEmpty &&
        _state.adjustments.isEmpty;
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

    _state = _state.copyWith(items: items, loading: isInitialLoad);
    notifyListeners();

    final errors = <String>[];
    Future<T?> capture<T>(Future<T> future, String message) async {
      try {
        return await future;
      } catch (e) {
        errors.add('$message: $e');
        return null;
      }
    }

    final results = await Future.wait<dynamic>([
      capture(
          _repo.getMenuItemIngredients(), 'Menu links could not be refreshed'),
      capture(
          _repo.getStockMovements(), 'Stock movements could not be refreshed'),
      capture(_repo.getPurchaseReceipts(), 'Purchases could not be refreshed'),
      capture(
          _repo.getStockAdjustments(), 'Adjustments could not be refreshed'),
    ]);

    _state = _state.copyWith(
      menuIngredients: results[0] as List<MenuItemIngredient>?,
      movements: results[1] as List<StockMovement>?,
      purchases: results[2] as List<PurchaseReceipt>?,
      adjustments: results[3] as List<StockAdjustment>?,
      loading: false,
      error: errors.isEmpty ? null : errors.first,
    );
    notifyListeners();
  }

  void updateItemInState(InventoryItem item) {
    final items = _state.items
        .map((existing) => existing.id == item.id ? item : existing)
        .toList();
    _state = _state.copyWith(items: items);
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

  double suggestedReorderQty(InventoryItem item) => suggestedRestockQty(item);

  double computeValueFromLots(List<FifoLot> lots) {
    return FifoQueueService.computeTotalValue(lots);
  }

  double toBase(double qty, double factor) =>
      UnitConversion.toBase(qty, factor);
  double fromBase(double qtyBase, double factor) =>
      UnitConversion.fromBase(qtyBase, factor);
}
