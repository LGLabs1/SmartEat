import '../../domain/services/fifo_queue.dart';
import '../models/stock_movement.dart';
import '../models/purchase_receipt.dart';
import '../models/stock_adjustment.dart';
import '../models/damaged_record.dart';
import '../models/menu_item_ingredient.dart';
import '../../../../../models/inventory_item.dart';

abstract class InventoryRepository {
  Future<List<InventoryItem>> getInventoryItems();
  Future<List<StockMovement>> getStockMovements({String? itemId});
  Future<List<PurchaseReceipt>> getPurchaseReceipts();
  Future<List<StockAdjustment>> getStockAdjustments();
  Future<void> applyPurchase(PurchaseReceipt receipt);
  Future<void> applyAdjustment(StockAdjustment adjustment);
  Future<void> recordDirectSaleConsumption({
    required String itemId,
    required double qtyBaseSold,
    String? referenceId,
    String? performedBy,
  });
  Future<List<FifoLot>> getFifoLots(String itemId);
  Future<void> saveFifoLots(String itemId, List<FifoLot> lots);
  Future<List<MenuItemIngredient>> getMenuItemIngredients();
}
