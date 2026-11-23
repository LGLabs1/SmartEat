import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../services/api_service.dart';
import '../../../../../theme.dart';
import '../../../../../widgets/dashboard/dashboard_back_handler.dart';
import '../../../../../widgets/skeleton_loaders.dart';
import '../../data/models/purchase_receipt.dart';
import '../../data/models/stock_adjustment.dart';
import '../../presentation/providers/inventory_notifier.dart';
import '../../presentation/providers/purchase_list_notifier.dart';
import 'items_list_screen.dart';
import 'item_detail_screen.dart';
import 'movements_screen.dart';
import 'purchases_screen.dart';
import 'adjustments_screen.dart';
import 'reports_screen.dart';
import 'purchase_list_screen.dart';
import 'inventory_overview_screen.dart';

Widget inventoryCompactNavIcon(IconData icon, String label) {
  return Semantics(
    label: label,
    child: Tooltip(message: label, child: Icon(icon)),
  );
}

class InventoryFeatureScreen extends StatefulWidget {
  const InventoryFeatureScreen({Key? key, this.onBackHandlerChanged})
      : super(key: key);

  final DashboardBackHandlerChanged? onBackHandlerChanged;

  @override
  State<InventoryFeatureScreen> createState() => _InventoryFeatureScreenState();
}

class _InventoryFeatureScreenState extends State<InventoryFeatureScreen> {
  int _index = 0;
  final List<int> _sectionHistory = <int>[0];
  String? _dismissedError;

  void _goToSection(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _sectionHistory.add(index);
  }

  bool _popSection() {
    if (_sectionHistory.length <= 1) return false;
    _sectionHistory.removeLast();
    setState(() => _index = _sectionHistory.last);
    return true;
  }

  // Ensures the one-off backfill of pre-existing purchase receipts runs at
  // most once per app session, so we do not re-query finance on every visit.
  static bool _autoFinanceSyncRan = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<PurchaseListNotifier>().load();
      await context.read<InventoryNotifier>().load();
      if (!mounted || _autoFinanceSyncRan) return;
      _autoFinanceSyncRan = true;
      await _syncExistingPurchasesToFinance(reportFailures: false);
    });
    widget.onBackHandlerChanged?.call(
      DashboardBackHandler(
        canUnwind: () => _sectionHistory.length > 1,
        unwind: _popSection,
      ),
    );
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    super.dispose();
  }

  /// Mirrors a recorded inventory purchase (GRN) into the finance ledger as an
  /// expense. Non-fatal: a failure never blocks the inventory update, but the
  /// user is notified so the books can be reconciled.
  Future<void> _postPurchaseToFinance(PurchaseReceipt receipt) async {
    try {
      await _syncReceiptToFinance(receipt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchase saved, but finance sync failed: $e'),
        ),
      );
    }
  }

  Future<bool> _syncReceiptToFinance(PurchaseReceipt receipt) async {
    final total = receipt.items.fold<double>(
      0,
      (sum, item) => sum + (item.qtyBase * item.unitCostPerBase),
    );
    if (receipt.id.isEmpty || total <= 0) return false;

    await ApiService.postInventoryPurchaseExpense(
      purchaseReceiptId: receipt.id,
      receiptNumber: receipt.receiptNumber,
      total: total,
      date: receipt.receivedAt,
      supplierName: receipt.supplierName,
      supplierId: receipt.supplierId,
      notes: receipt.notes,
    );
    return true;
  }

  /// Backfills any purchase receipts already stored in inventory that have not
  /// yet been mirrored to finance. Safe to run repeatedly - already linked
  /// receipts are skipped, so re-running never duplicates an expense.
  Future<void> _syncExistingPurchasesToFinance({
    bool reportFailures = true,
  }) async {
    final purchases = context.read<InventoryNotifier>().state.purchases;
    if (purchases.isEmpty) return;

    int posted = 0;
    int failed = 0;
    String lastError = '';

    for (final receipt in purchases) {
      try {
        final existing = await ApiService.findLinkedPurchaseExpense(receipt.id);
        if (existing != null) continue;
        if (await _syncReceiptToFinance(receipt)) posted++;
      } catch (e) {
        failed++;
        lastError = e.toString();
      }
    }

    if (!mounted || (posted == 0 && failed == 0)) return;
    final messenger = ScaffoldMessenger.of(context);
    if (posted > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Posted $posted purchase(s) to Expenses.'),
        ),
      );
    } else if (failed > 0 && reportFailures) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not sync purchases to finance ($failed failed): $lastError',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<InventoryNotifier>();
    final state = notifier.state;
    final items = state.items;
    final error = state.error;
    final showError = error != null && error != _dismissedError;

    final screens = [
      InventoryOverviewScreen(
        key: const ValueKey('inventory-overview'),
        items: items,
        movements: state.movements,
        onViewReports: () => _goToSection(5),
        onViewLowStock: () => _goToSection(1),
        onViewMovements: () => _goToSection(2),
      ),
      ItemsListScreen(
        key: const ValueKey('inventory-items'),
        items: items,
        onRefresh: notifier.load,
        onItemTap: (item) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailScreen(
                item: item,
                onItemUpdated: (updated) {
                  if (!mounted) return;
                  notifier.updateItemInState(updated);
                },
              ),
            ),
          );
        },
        onPurchase: (PurchaseReceipt r) async {
          await notifier.applyPurchase(r);
          await _postPurchaseToFinance(r);
        },
        onAdjustment: (StockAdjustment a) async {
          await notifier.applyAdjustment(a);
        },
        onAddItem: (_) async {
          await notifier.load();
        },
      ),
      MovementsScreen(
        key: const ValueKey('inventory-movements'),
        movements: state.movements,
        items: items,
      ),
      PurchasesScreen(
        key: const ValueKey('inventory-purchases'),
        purchases: state.purchases,
        items: items,
        onSyncToFinance: () => _syncExistingPurchasesToFinance(),
        onOpenPurchaseList: () {
          final purchaseNotifier = context.read<PurchaseListNotifier>();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: purchaseNotifier,
                child: PurchaseListScreen(
                  items: items,
                  onRecordPurchase: (receipt) async {
                    await notifier.applyPurchase(receipt);
                    await _postPurchaseToFinance(receipt);
                  },
                ),
              ),
            ),
          );
        },
      ),
      AdjustmentsScreen(
        key: const ValueKey('inventory-adjustments'),
        adjustments: state.adjustments,
        items: items,
      ),
      ReportsScreen(
        key: const ValueKey('inventory-reports'),
        items: items,
        movements: state.movements,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.sageNavy,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: screens),
          if (state.loading && items.isEmpty)
            Positioned.fill(
              child: Container(
                color: AppTheme.sageNavy,
                child: const SkeletonInventory(),
              ),
            ),
          if (state.loading && items.isNotEmpty)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (showError)
            Positioned(
              top: state.loading ? 4 : 0,
              left: 12,
              right: 12,
              child: Material(
                color: AppTheme.sagePanel,
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Retry',
                        onPressed: () {
                          setState(() => _dismissedError = null);
                          notifier.load();
                        },
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.sageAccent,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () =>
                            setState(() => _dismissedError = error),
                        icon: const Icon(Icons.close, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToSection,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.sagePanel,
        selectedItemColor: AppTheme.sageAccent,
        unselectedItemColor: Colors.white.withValues(alpha: 0.52),
        items: [
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.dashboard, 'Overview'),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.inventory, 'Items'),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.history, 'Movements'),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.shopping_cart, 'Purchases'),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.tune, 'Adjustments'),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: inventoryCompactNavIcon(Icons.bar_chart, 'Reports'),
            label: '',
          ),
        ],
      ),
    );
  }
}
