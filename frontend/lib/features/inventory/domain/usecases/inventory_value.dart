import '../../data/models/stock_movement.dart';
import '../../../../../models/inventory_item.dart';
import '../../domain/services/fifo_queue.dart';

class InventoryValueUseCase {
  double computeTotalValue(List<InventoryItem> items, List<FifoLot>? lotsByItem) {
    if (lotsByItem != null && lotsByItem.isNotEmpty) {
      return FifoQueueService.computeTotalValue(lotsByItem);
    }
    double total = 0.0;
    for (final i in items) {
      total += i.currentStock * ((i.lastPurchaseCost > 0) ? i.lastPurchaseCost : i.unitCost);
    }
    return total;
  }
}
