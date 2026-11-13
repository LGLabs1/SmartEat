# Inventory Feature (Redesigned)

## Structure
- data/models: StockMovement, PurchaseReceipt, StockAdjustment, DamagedRecord, MenuItemIngredient
- domain/services: FifoQueueService (on-the-fly), UnitConversion
- domain/usecases: HealthScore, Reports, InventoryValue, Consumption, MovementHistory
- data/repositories: InventoryRepository + InventoryRemoteRepository (movements/adjustments/purchases persisted in Firestore under the eatery, with SharedPreferences as an offline cache; FIFO lots stored per item)
- presentation/providers: InventoryNotifier
- presentation/widgets: InventoryTable, HealthScoreCard, PurchaseDialog, AdjustmentDialog
- presentation/screens: Overview, Items, ItemDetail, Movements, Purchases, Adjustments, Reports
- inventory_module.dart: Provider wrapper

## Key Design
- FIFO on-the-fly (no persistent lots table)
- consumptionMode: direct vs recipePending (per plan #4). Direct items generate saleConsumption movements on POS sales; recipePending do not auto-decrement until mapping exists.
- Restock: Max Stock - Current Stock (simple, #5)
- Health Score bands: 90-100 Excellent, 80-89 Good, 70-79 Fair, 50-69 Needs Attention, <50 Critical (#3)
- Movements persisted in Firestore (eatery-scoped) on purchases/adjustments/direct sales (Phase 5); SharedPreferences mirrors them as an offline cache so history survives restarts and reinstalls. FIFO cost impact recorded for decreases/sales (#2).
