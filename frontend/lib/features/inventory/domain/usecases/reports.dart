import '../../data/models/stock_movement.dart';
import '../../../../../models/inventory_item.dart';
import '../../domain/services/fifo_queue.dart';

class RestockSuggestion {
  final InventoryItem item;
  final double suggestedQtyBase;

  RestockSuggestion({required this.item, required this.suggestedQtyBase});
}

class RestockSuggestionsUseCase {
  List<RestockSuggestion> compute(List<InventoryItem> items) {
    final list = <RestockSuggestion>[];
    for (final i in items.where((e) => e.isActive)) {
      final s = i.maxStock - i.currentStock;
      if (s > 0) {
        list.add(RestockSuggestion(item: i, suggestedQtyBase: s));
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
