import '../../../../../models/inventory_item.dart';

class RestockSuggestion {
  final InventoryItem item;
  final double suggestedQtyBase;

  RestockSuggestion({required this.item, required this.suggestedQtyBase});
}

double suggestedRestockQty(InventoryItem item) {
  if (item.maxStock > item.currentStock) {
    return item.maxStock - item.currentStock;
  }

  final reorderLevel =
      item.reorderPoint > 0 ? item.reorderPoint : item.minStock;
  if (reorderLevel > item.currentStock) {
    return reorderLevel - item.currentStock;
  }

  if (item.currentStock <= 0) return 1;
  return 0;
}

class RestockSuggestionsUseCase {
  List<RestockSuggestion> compute(List<InventoryItem> items) {
    final list = <RestockSuggestion>[];
    for (final i in items.where((e) => e.isActive)) {
      final qty = suggestedRestockQty(i);
      if (qty > 0) {
        list.add(RestockSuggestion(item: i, suggestedQtyBase: qty));
      }
    }
    return list;
  }
}

class LowStockEntry {
  final InventoryItem item;
  final bool isOutOfStock;

  LowStockEntry({required this.item, required this.isOutOfStock});
}

class LowStockReportUseCase {
  List<LowStockEntry> compute(List<InventoryItem> items) {
    final list = <LowStockEntry>[];
    for (final i in items.where((e) => e.isActive)) {
      final out = i.currentStock <= 0;
      final low = i.isLowStock;
      if (out || low) {
        list.add(LowStockEntry(item: i, isOutOfStock: out));
      }
    }
    return list;
  }
}
