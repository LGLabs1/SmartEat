import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../models/inventory_item.dart';
import '../../data/models/purchase_list_item.dart';

class PurchaseListNotifier extends ChangeNotifier {
  static const _prefsKey = 'inventory_purchase_list';
  static const _legacyPrefsKey = 'inventory_grocery_list';

  List<PurchaseListItem> _list = [];
  List<PurchaseListItem> get list => List.unmodifiable(_list);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    var s = prefs.getString(_prefsKey);
    if (s == null || s.isEmpty) {
      s = prefs.getString(_legacyPrefsKey);
    }
    if (s != null && s.isNotEmpty) {
      try {
        final List<dynamic> arr = jsonDecode(s);
        _list = arr
            .map((e) => PurchaseListItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _list = [];
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final arr = _list.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(arr));
  }

  void addItem(InventoryItem item, {double? qty}) {
    if (_list.any((e) => e.itemId == item.id)) return;
    final suggested = qty ?? (item.maxStock - item.currentStock);
    _list.add(PurchaseListItem(
      itemId: item.id,
      name: item.name,
      unit: item.unit,
      qty: suggested > 0 ? suggested : 1,
      unitCost: item.lastPurchaseCost > 0 ? item.lastPurchaseCost : item.unitCost,
    ));
    _save();
    notifyListeners();
  }

  void removeItem(String itemId) {
    _list.removeWhere((e) => e.itemId == itemId);
    _save();
    notifyListeners();
  }

  void removeItems(Iterable<String> itemIds) {
    final ids = itemIds.toSet();
    if (ids.isEmpty) return;
    _list.removeWhere((e) => ids.contains(e.itemId));
    _save();
    notifyListeners();
  }

  void updateQty(String itemId, double qty) {
    final idx = _list.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    _list[idx] = _list[idx].copyWith(qty: qty < 0 ? 0 : qty);
    _save();
    notifyListeners();
  }

  void incrementQty(String itemId, {double step = 1}) {
    final idx = _list.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    final newQty = _list[idx].qty + step;
    _list[idx] = _list[idx].copyWith(qty: newQty < 0 ? 0 : newQty);
    _save();
    notifyListeners();
  }

  void decrementQty(String itemId, {double step = 1}) {
    final idx = _list.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    final newQty = _list[idx].qty - step;
    _list[idx] = _list[idx].copyWith(qty: newQty < 0 ? 0 : newQty);
    _save();
    notifyListeners();
  }

  void toggleChecked(String itemId) {
    final idx = _list.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    _list[idx] = _list[idx].copyWith(checked: !_list[idx].checked);
    _save();
    notifyListeners();
  }

  void clearChecked() {
    _list.removeWhere((e) => e.checked);
    _save();
    notifyListeners();
  }

  void clear() {
    _list = [];
    _save();
    notifyListeners();
  }

  void generateFromCritical(List<InventoryItem> items) {
    _list = [];
    for (final item in items.where((e) => e.isActive)) {
      if (_isCritical(item)) {
        final suggested = item.maxStock - item.currentStock;
        _list.add(PurchaseListItem(
          itemId: item.id,
          name: item.name,
          unit: item.unit,
          qty: suggested > 0 ? suggested : 1,
          unitCost: item.lastPurchaseCost > 0 ? item.lastPurchaseCost : item.unitCost,
        ));
      }
    }
    _save();
    notifyListeners();
  }

  bool isInList(String itemId) => _list.any((e) => e.itemId == itemId);

  double get pendingCost => _list
      .where((e) => !e.checked)
      .fold(0.0, (sum, e) => sum + e.lineCost);

  double get checkedCost => _list
      .where((e) => e.checked)
      .fold(0.0, (sum, e) => sum + e.lineCost);

  int get pendingCount => _list.where((e) => !e.checked).length;
  int get checkedCount => _list.where((e) => e.checked).length;

  bool _isCritical(InventoryItem item) {
    return item.currentStock <= 0 || item.isLowStock;
  }

  List<InventoryItem> criticalItems(List<InventoryItem> items) {
    return items.where((e) => e.isActive && _isCritical(e)).toList();
  }

  List<InventoryItem> safeItems(List<InventoryItem> items) {
    return items
        .where((e) =>
            e.isActive &&
            !_isCritical(e) &&
            e.maxStock > 0 &&
            e.currentStock < e.maxStock)
        .toList();
  }

  List<InventoryItem> allItems(List<InventoryItem> items) {
    return items.where((e) => e.isActive).toList();
  }
}
