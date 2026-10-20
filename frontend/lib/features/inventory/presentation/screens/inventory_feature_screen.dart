import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../services/api_service.dart';
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

class InventoryFeatureScreen extends StatefulWidget {
  const InventoryFeatureScreen({Key? key}) : super(key: key);

  @override
  State<InventoryFeatureScreen> createState() => _InventoryFeatureScreenState();
}

class _InventoryFeatureScreenState extends State<InventoryFeatureScreen> {
  int _index = 0;

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

    final screens = [
      InventoryOverviewScreen(
        items: items,
        movements: state.movements,
        onViewReports: () => setState(() => _index = 5),
        onViewLowStock: () => setState(() => _index = 1),
        onViewMovements: () => setState(() => _index = 2),
      ),
      ItemsListScreen(
        items: items,
        onItemTap: (item) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
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
      MovementsScreen(movements: state.movements, items: items),
      PurchasesScreen(
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
      AdjustmentsScreen(adjustments: state.adjustments, items: items),
      ReportsScreen(items: items, movements: state.movements),
    ];

    return Scaffold(
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Items'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Movements'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Purchases'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Adjustments'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
