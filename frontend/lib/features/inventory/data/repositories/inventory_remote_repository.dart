import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../services/api_service.dart';
import '../../../../../services/firebase_service.dart';
import '../../../../../models/inventory_item.dart';
import '../../domain/services/fifo_queue.dart';
import '../models/stock_movement.dart';
import '../models/purchase_receipt.dart';
import '../models/stock_adjustment.dart';
import '../models/menu_item_ingredient.dart';
import 'inventory_repository.dart';

class InventoryRemoteRepository implements InventoryRepository {
  static const _fifoPrefix = 'inventory_fifo_';
  static const _movementsKey = 'inventory_movements';
  static const _adjustmentsKey = 'inventory_adjustments';
  static const _purchasesKey = 'inventory_purchases';

  // History is persisted in Firestore (durable, shared across devices) with
  // SharedPreferences kept as an offline cache/fallback. The cache key is
  // scoped per eatery so switching accounts never mixes histories.
  String? _eateryScope;

  Future<String> _scope() async {
    if (_eateryScope != null) return _eateryScope!;
    String id = '';
    try {
      id = (await FirebaseService.getCurrentEateryId()) ?? '';
    } catch (_) {
      id = '';
    }
    _eateryScope = id;
    return id;
  }

  Future<String> _cacheKey(String base) async {
    final scope = await _scope();
    return scope.isEmpty ? base : '${base}_$scope';
  }

  @override
  Future<List<InventoryItem>> getInventoryItems() async {
    final response = await ApiService.getInventoryItems();
    final items = (response['data'] as List?)
            ?.map((item) => InventoryItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];
    return items;
  }

  // --- Local cache read/write -------------------------------------------------

  Future<List<Map<String, dynamic>>> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(await _cacheKey(key));
    if (s == null || s.isEmpty) return [];
    try {
      final List<dynamic> arr = jsonDecode(s);
      return arr
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCache(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _cacheKey(key), jsonEncode(rows));
  }

  /// Merges [remote] (authoritative) with [local] (offline-only rows not yet
  /// synced), de-duplicating by `id`. Remote wins on conflict.
  List<Map<String, dynamic>> _merge(
    List<Map<String, dynamic>> remote,
    List<Map<String, dynamic>> local,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in remote) {
      final id = (r['id'] ?? '').toString();
      byId[id.isEmpty ? 'remote_${byId.length}' : id] = r;
    }
    for (final l in local) {
      final id = (l['id'] ?? '').toString();
      if (id.isEmpty || !byId.containsKey(id)) {
        byId[id.isEmpty ? 'local_${byId.length}' : id] = l;
      }
    }
    return byId.values.toList();
  }

  // --- Movements --------------------------------------------------------------

  Future<List<StockMovement>> _loadMovements() async {
    final cached = await _readCache(_movementsKey);
    List<Map<String, dynamic>> remote = const [];
    try {
      final res = await ApiService.getStockMovements();
      remote = List<Map<String, dynamic>>.from(res['data'] ?? const []);
    } catch (_) {
      remote = const [];
    }
    final merged = _merge(remote, cached);
    if (merged.isNotEmpty) await _writeCache(_movementsKey, merged);
    return merged
        .map((e) => StockMovement.fromJson(e))
        .toList();
  }

  Future<void> _appendMovement(StockMovement movement) async {
    final row = movement.toJson();
    // Durable write first; the local cache is best-effort.
    try {
      await ApiService.createStockMovement(row);
    } catch (_) {
      // Offline: keep the row cached so it can be retried/synced later.
    }
    final cached = await _readCache(_movementsKey);
    cached.add(row);
    await _writeCache(_movementsKey, cached);
  }

  // --- Adjustments ------------------------------------------------------------

  Future<List<StockAdjustment>> _loadAdjustments() async {
    final cached = await _readCache(_adjustmentsKey);
    List<Map<String, dynamic>> remote = const [];
    try {
      final res = await ApiService.getStockAdjustments();
      remote = List<Map<String, dynamic>>.from(res['data'] ?? const []);
    } catch (_) {
      remote = const [];
    }
    final merged = _merge(remote, cached);
    if (merged.isNotEmpty) await _writeCache(_adjustmentsKey, merged);
    return merged.map((e) => StockAdjustment.fromJson(e)).toList();
  }

  Future<void> _appendAdjustment(StockAdjustment adjustment) async {
    final row = adjustment.toJson();
    try {
      await ApiService.createStockAdjustment(row);
    } catch (_) {
      // Cache fallback below.
    }
    final cached = await _readCache(_adjustmentsKey);
    cached.add(row);
    await _writeCache(_adjustmentsKey, cached);
  }

  // --- Purchases --------------------------------------------------------------

  Future<List<PurchaseReceipt>> _loadPurchases() async {
    final cached = await _readCache(_purchasesKey);
    List<Map<String, dynamic>> remote = const [];
    try {
      final res = await ApiService.getPurchaseReceipts();
      remote = List<Map<String, dynamic>>.from(res['data'] ?? const []);
    } catch (_) {
      remote = const [];
    }
    final merged = _merge(remote, cached);
    if (merged.isNotEmpty) await _writeCache(_purchasesKey, merged);
    return merged.map((e) => PurchaseReceipt.fromJson(e)).toList();
  }

  Future<void> _appendPurchase(PurchaseReceipt receipt) async {
    final row = receipt.toJson();
    try {
      await ApiService.createPurchaseReceipt(row);
    } catch (_) {
      // Cache fallback below.
    }
    final cached = await _readCache(_purchasesKey);
    cached.add(row);
    await _writeCache(_purchasesKey, cached);
  }

  @override
  Future<List<StockMovement>> getStockMovements({String? itemId}) async {
    final list = await _loadMovements();
    if (itemId == null) return list;
    return list.where((m) => m.itemId == itemId).toList();
  }

  @override
  Future<List<PurchaseReceipt>> getPurchaseReceipts() async {
    return await _loadPurchases();
  }

  @override
  Future<List<StockAdjustment>> getStockAdjustments() async {
    return await _loadAdjustments();
  }

  @override
  Future<void> applyPurchase(PurchaseReceipt receipt) async {
    // Persist the receipt (GRN) first so the purchase history is never lost,
    // even if a later inventory update step fails.
    await _appendPurchase(receipt);

    for (final it in receipt.items) {
      await ApiService.updateInventoryStock(
        it.itemId,
        quantity: it.qtyBase,
        operation: 'add',
      );
      final items = await getInventoryItems();
      final item = items.firstWhere((x) => x.id == it.itemId, orElse: () => throw Exception('Inventory item not found'));
      final before = item.currentStock - it.qtyBase;
      final after = item.currentStock;
      await _appendMovement(StockMovement(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        itemId: it.itemId,
        type: StockMovementType.purchase,
        referenceType: StockMovementRefType.purchase,
        referenceId: receipt.id,
        qtyBeforeBase: before,
        qtyAfterBase: after,
        changeBase: it.qtyBase,
        unitCostAtEvent: it.unitCostPerBase,
        totalCostImpact: 0,
        performedBy: receipt.receivedBy,
        notes: receipt.notes,
      ));
      final lots = await getFifoLots(it.itemId);
      final nl = FifoQueueService.addPurchase(lots, it.qtyBase, it.unitCostPerBase);
      await saveFifoLots(it.itemId, nl);
    }
  }

  @override
  Future<void> applyAdjustment(StockAdjustment adjustment) async {
    await ApiService.updateInventoryStock(
      adjustment.itemId,
      quantity: adjustment.deltaBase,
      operation: adjustment.reasonCode,
    );
    final items = await getInventoryItems();
    final item = items.firstWhere((x) => x.id == adjustment.itemId, orElse: () => throw Exception('Inventory item not found'));
    final before = adjustment.qtyBeforeBase > 0
        ? adjustment.qtyBeforeBase
        : (item.currentStock - adjustment.deltaBase);
    final after = item.currentStock;
    await _appendMovement(StockMovement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      itemId: adjustment.itemId,
      type: adjustment.deltaBase >= 0 ? StockMovementType.adjustIncrease : StockMovementType.adjustDecrease,
      referenceType: StockMovementRefType.adjustment,
      referenceId: adjustment.id,
      qtyBeforeBase: before,
      qtyAfterBase: after,
      changeBase: adjustment.deltaBase,
      performedBy: adjustment.performedBy,
      reasonCode: adjustment.reasonCode,
      notes: adjustment.notes,
    ));
    if (adjustment.deltaBase < 0) {
      final lots = await getFifoLots(adjustment.itemId);
      final res = FifoQueueService.consume(lots, -adjustment.deltaBase);
      await saveFifoLots(adjustment.itemId, res.remainingLots);
    } else {
      final lots = await getFifoLots(adjustment.itemId);
      await saveFifoLots(adjustment.itemId, lots);
    }
    await _appendAdjustment(adjustment);
  }

  @override
  Future<void> recordDirectSaleConsumption({
    required String itemId,
    required double qtyBaseSold,
    String? referenceId,
    String? performedBy,
  }) async {
    if (qtyBaseSold <= 0) return;
    final items = await getInventoryItems();
    final item = items.firstWhere((x) => x.id == itemId, orElse: () => null as dynamic);
    if (item.consumptionMode != ConsumptionMode.direct) return;
    await ApiService.updateInventoryStock(
      itemId,
      quantity: -qtyBaseSold,
      operation: 'Sale consumption',
    );
    final afterItem = (await getInventoryItems()).firstWhere((x) => x.id == itemId, orElse: () => item);
    final before = item.currentStock;
    final after = afterItem.currentStock;
    final lots = await getFifoLots(itemId);
    final res = FifoQueueService.consume(lots, qtyBaseSold);
    await saveFifoLots(itemId, res.remainingLots);
    await _appendMovement(StockMovement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      itemId: itemId,
      type: StockMovementType.saleConsumption,
      referenceType: StockMovementRefType.order,
      referenceId: referenceId,
      qtyBeforeBase: before,
      qtyAfterBase: after,
      changeBase: -qtyBaseSold,
      totalCostImpact: res.totalCostImpact,
      performedBy: performedBy,
    ));
  }

  @override
  Future<List<FifoLot>> getFifoLots(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _fifoPrefix + itemId;
    final s = prefs.getString(key);
    if (s == null || s.isEmpty) return [];
    try {
      final List<dynamic> arr = jsonDecode(s);
      return arr
          .map((e) => FifoLot(
                qtyRemainingBase: (e['qtyRemainingBase'] ?? 0).toDouble(),
                unitCostPerBase: (e['unitCostPerBase'] ?? 0).toDouble(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveFifoLots(String itemId, List<FifoLot> lots) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _fifoPrefix + itemId;
    final arr = lots
        .map((e) => {
              'qtyRemainingBase': e.qtyRemainingBase,
              'unitCostPerBase': e.unitCostPerBase,
            })
        .toList();
    await prefs.setString(key, jsonEncode(arr));
  }

  @override
  Future<List<MenuItemIngredient>> getMenuItemIngredients() async {
    return [];
  }
}
