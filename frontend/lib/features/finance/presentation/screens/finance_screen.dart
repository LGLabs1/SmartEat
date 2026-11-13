import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../screens/inventory_screen.dart';
import '../../../../screens/staff_management_screen.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_provider.dart';
import '../../../../theme.dart';
import '../../../../widgets/skeleton_loaders.dart';
import '../../data/finance_export_service.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import '../widgets/expense_detail_sheet.dart';
import '../widgets/expense_form_dialog.dart';
import '../widgets/expenses_tab.dart';
import '../widgets/finance_budgets_dialog.dart';
import '../widgets/overview_tab.dart';
import '../widgets/payable_detail_sheet.dart';
import '../widgets/payable_form_dialog.dart';
import '../widgets/payable_payment_dialog.dart';
import '../widgets/payables_tab.dart';
import '../widgets/payroll_tab.dart';
import '../widgets/reports_tab.dart';

/// Finance module shell. Owns the firestore-backed finance data, filters and
/// settings; delegates presentation to per-tab widgets under features/finance.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onNavigate,
  }) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<int>? onNavigate;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  /// Currently selected finance section. Sections are rendered at the bottom
  /// (like the Inventory page) via a fixed BottomNavigationBar.
  int _index = 0;

  /// Section back stack. The last entry is the current section; earlier
  /// entries are where the in-screen back action returns to. This lets
  /// KPI/detail jumps (e.g. Overview -> Payables) be undone without leaving
  /// Finance.
  final List<int> _tabHistory = [0];

  bool _isLoading = true;
  String? _error;

  bool _isAdmin = false;
  String? _lastRoleUid;

  List<Map<String, dynamic>> _expenses = const [];
  List<Map<String, dynamic>> _payables = const [];

  // Filters
  String _expenseSourceFilter = 'all';
  String? _expenseCategoryFilter;
  DateTimeRange? _expenseDateRange;
  String _searchQuery = '';
  String _payablesSegment = 'upcoming';

  String? _eateryId;
  String _currencySymbol = '₱';
  Map<String, double> _budgets = {};

  // Menu-costing profitability (separate from Actual COGS / stock movements).
  List<Map<String, dynamic>> _itemPerformance = const [];
  List<Map<String, dynamic>> _dailySales = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _inventoryItems = const [];
  List<Map<String, dynamic>> _stockMovements = const [];
  List<Map<String, dynamic>> _damagedItems = const [];
  List<Map<String, dynamic>> _salesForecast = const [];

  VoidCallback? _globalSearchListener;

  // Memoized payroll streams so tab rebuilds don't re-subscribe.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _staffUsersStream;
  String _staffUsersStreamKey = '';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _staffProfilesStream;
  String _staffProfilesStreamKey = '';

  FinanceFormat get _fmt => FinanceFormat(_currencySymbol);

  static const List<String> _expenseCategories = [
    'Ingredients',
    'Utilities',
    'Rent',
    'Salaries',
    'Equipment',
    'Maintenance',
    'Marketing',
    'Supplies',
    'Transportation',
    'Taxes',
    'Insurance',
    'Other',
  ];

  static const List<String> _paymentMethods = [
    'Cash',
    'Bank Transfer',
    'Card',
    'Mobile Money',
    'Other',
  ];

  static const List<String> _billCategories = [
    'Rent',
    'Electricity',
    'Water',
    'Internet',
    'Phone',
    'Gas',
    'Insurance',
    'Taxes',
    'Supplier Payment',
    'Salaries',
    'Maintenance',
    'Equipment Lease',
    'Marketing',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();

    final notifier = widget.globalSearchQuery;
    if (notifier != null) {
      _searchQuery = notifier.value;
      _globalSearchListener = () {
        if (!mounted) return;
        setState(() => _searchQuery = notifier.value);
      };
      notifier.addListener(_globalSearchListener!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRole();
      _loadBusinessSettings();
      _loadBudgets();
    });
  }

  @override
  void dispose() {
    final notifier = widget.globalSearchQuery;
    final listener = _globalSearchListener;
    if (notifier != null && listener != null) {
      notifier.removeListener(listener);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Section navigation with back-stack support
  // ---------------------------------------------------------------------------

  /// Switch to [section] recording the current one so Back can return here.
  void _goToFinanceTab(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _tabHistory.add(index);
    });
  }

  /// Selects [index] directly (from the bottom bar), recording the previous
  /// section so Back unwinds it.
  void _selectSection(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _tabHistory.add(index);
    });
  }

  /// Returns to the previous section if there is one. Returns false when
  /// already on the first section so the caller can hand off to the outer
  /// handler.
  bool _popFinanceTab() {
    if (_tabHistory.length <= 1) return false;
    _tabHistory.removeLast();
    setState(() => _index = _tabHistory.last);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<String?> _getEateryId() async {
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      return (profile?['eateryId'] ?? '').toString().trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRole() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_lastRoleUid == uid) return;
    _lastRoleUid = uid;
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      if (!mounted) return;
      setState(() => _isAdmin = _isAdminFromProfile(profile));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAdmin = false);
    }
  }

  bool _isAdminFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final dynamic isAdminRaw = profile['isAdmin'];
    final bool isAdminFlag = isAdminRaw == true ||
        isAdminRaw == 1 ||
        (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
    return isAdminFlag || role == 'admin';
  }

  Future<void> _loadBusinessSettings() async {
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(uid)
          .get();
      final symbol = (doc.data()?['currencySymbol'] ?? '').toString().trim();
      if (!mounted || symbol.isEmpty) return;
      setState(() => _currencySymbol = symbol);
    } catch (_) {
      // Ignore settings load failures.
    }
  }

  Future<void> _loadBudgets() async {
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(uid)
          .get();
      final raw = doc.data()?[FinanceBudgetStore.key];
      if (!mounted) return;
      setState(() => _budgets = FinanceBudgetStore.parse(raw));
    } catch (_) {
      // Ignore budget load failures.
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      dynamic safe(Future<dynamic> f, String label, [dynamic fallback = const <String, dynamic>{'data': <dynamic>[]}]) async {
        try { return await f; } catch (e) { debugPrint('load failed: $label $e'); return fallback; }
      }
      final results = await Future.wait<dynamic>([
        safe(ApiService.getExpenses(), 'getExpenses'),
        safe(ApiService.getPayables(), 'getPayables'),
        safe(_getEateryId(), 'getEateryId', null),
        safe(ApiService.getItemPerformance(), 'getItemPerformance', const <String, dynamic>{'data': <String, dynamic>{}}),
        safe(ApiService.getDailySalesAnalytics(days: 62), 'getDailySalesAnalytics', const <String, dynamic>{'data': <String, dynamic>{}}),
        safe(ApiService.getAllOrders(), 'getAllOrders'),
        safe(ApiService.getInventoryItems(), 'getInventoryItems'),
        safe(ApiService.getStockMovements(), 'getStockMovements'),
        safe(ApiService.getDamagedItems(), 'getDamagedItems'),
        safe(ApiService.getSalesForecast(days: 30), 'getSalesForecast'),
      ]);

      List<Map<String, dynamic>> asList(dynamic raw, [List<String> path = const []]) {
        try {
          if (raw is List) return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          if (raw is! Map) return const [];
          for (final key in path) {
            final v = raw[key];
            if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          final data = raw['data'];
          if (data is List) return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          if (data is Map) {
            for (final key in path) {
              final v = data[key];
              if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            }
          }
        } catch (_) {}
        return const [];
      }

      final expenses = asList(results[0]);
      final payables = asList(results[1]);
      final eateryId = (results[2] ?? '').toString().trim();
      final itemPerformance = () {
        final r = asList(results[3], const ['items']);
        if (r.isNotEmpty) return r;
        if (results[3] is Map) {
          final m = results[3] as Map; final d = m['data'];
          if (d is Map && d['items'] is List) return (d['items'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
          if (d is List) return d.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
          if (m['items'] is List) return (m['items'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
        }
        return r;
      }();
      final dailySales = () {
        final r = asList(results[4], const ['dailySales']);
        if (r.isNotEmpty) return r;
        if (results[4] is Map) {
          final m = results[4] as Map; final d = m['data'];
          if (d is Map && d['dailySales'] is List) return (d['dailySales'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
          if (d is List) return d.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
          if (m['dailySales'] is List) return (m['dailySales'] as List).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
        }
        return r;
      }();
      final orders = asList(results[5]);
      final inventoryItems = asList(results[6]);
      final stockMovements = asList(results[7]);
      final damagedItems = asList(results[8]);
      final salesForecast = () {
        final r = asList(results[9], const ['forecast']);
        if (r.isNotEmpty) return r;
        return asList(results[9]);
      }();

      if (!mounted) return;
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _payables = payables;
        _eateryId = eateryId.isEmpty ? null : eateryId;
        _itemPerformance = itemPerformance;
        _dailySales = dailySales;
        _orders = orders;
        _inventoryItems = inventoryItems;
        _stockMovements = stockMovements;
        _damagedItems = damagedItems;
        _salesForecast = salesForecast;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Optimistic local mutations
  // ---------------------------------------------------------------------------

  void _addExpenseToLocal(Map<String, dynamic> expense) {
    setState(() => _expenses = [expense, ..._expenses]);
  }

  void _removeExpenseFromLocal(String id) {
    setState(() => _expenses = _expenses.where((e) => e['id'] != id).toList());
  }

  void _addPayableToLocal(Map<String, dynamic> payable) {
    setState(() => _payables = [payable, ..._payables]);
  }

  void _updatePayableInLocal(String id, Map<String, dynamic> updates) {
    setState(() {
      _payables = _payables.map((p) {
        if (p['id'] == id) return {...p, ...updates};
        return p;
      }).toList();
    });
  }

  void _removePayableFromLocal(String id) {
    setState(() => _payables = _payables.where((p) => p['id'] != id).toList());
  }

  // ---------------------------------------------------------------------------
  // Payroll streams
  // ---------------------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _staffUsersFor(String eateryId) {
    if (_staffUsersStream == null || _staffUsersStreamKey != eateryId) {
      _staffUsersStreamKey = eateryId;
      _staffUsersStream = FirebaseFirestore.instance
          .collection('users')
          .where('eateryId', isEqualTo: eateryId)
          .snapshots();
    }
    return _staffUsersStream!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _staffProfilesFor(
      String eateryId) {
    if (_staffProfilesStream == null || _staffProfilesStreamKey != eateryId) {
      _staffProfilesStreamKey = eateryId;
      _staffProfilesStream = FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('staff_profiles')
          .snapshots();
    }
    return _staffProfilesStream!;
  }

  // ---------------------------------------------------------------------------
  // Expense actions
  // ---------------------------------------------------------------------------

  Future<void> _addExpense() async {
    if (!_isAdmin) return;
    final draft = await ExpenseFormDialog.show(
      context,
      currencySymbol: _currencySymbol,
      categories: _expenseCategories,
      paymentMethods: _paymentMethods,
    );
    if (draft == null) return;

    try {
      final result = await ApiService.createExpense(
        name: draft.name,
        category: draft.category,
        amount: draft.amount,
        date: draft.date,
        notes: draft.notes,
        supplierName: draft.supplierName,
        paymentMethod: draft.paymentMethod,
        paymentStatus: 'paid',
      );
      final newExpense = result['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      if (newExpense != null) _addExpenseToLocal(newExpense);
      _snack('Expense added');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to add expense: $e');
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final id = (expense['id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (expense['name'] ?? 'this expense').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteExpense(id);
      if (!mounted) return;
      _removeExpenseFromLocal(id);
      _snack('Expense deleted');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete expense: $e');
    }
  }

  void _openExpense(Map<String, dynamic> expense) {
    final linked = FinanceMetrics.isLinkedPurchase(expense);
    final bill = FinanceMetrics.isPayablePayment(expense);
    ExpenseDetailSheet.show(
      context,
      expense: expense,
      fmt: _fmt,
      isAdmin: _isAdmin,
      onDelete: (linked || bill)
          ? null
          : () => _deleteExpense(expense),
      onViewPurchase: linked
          ? () {
              Navigator.of(context).maybePop();
              _openInventory();
            }
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Payable actions
  // ---------------------------------------------------------------------------

  Future<void> _addPayable() async {
    if (!_isAdmin) return;
    final draft = await PayableFormDialog.show(
      context,
      currencySymbol: _currencySymbol,
      billCategories: _billCategories,
    );
    if (draft == null) return;
    await _persistPayable(draft, existingId: null);
  }

  Future<void> _editPayable(Map<String, dynamic> payable) async {
    if (!_isAdmin) return;
    final draft = await PayableFormDialog.show(
      context,
      currencySymbol: _currencySymbol,
      billCategories: _billCategories,
      initial: payable,
    );
    if (draft == null) return;
    await _persistPayable(
      draft,
      existingId: (payable['id'] ?? '').toString(),
    );
  }

  Future<void> _persistPayable(
    PayableDraft draft, {
    required String? existingId,
  }) async {
    final isEdit = existingId != null && existingId.isNotEmpty;
    try {
      if (isEdit) {
        await ApiService.updatePayable(
          existingId,
          name: draft.name,
          amount: draft.amount,
          frequency: draft.frequency,
          dueDate: draft.dueDate,
          notes: draft.notes,
          vendor: draft.vendor,
          dueDay: draft.dueDay,
          dueDays: draft.dueDays,
          dueMonth: draft.dueMonth,
          isVariable: draft.isVariable,
          estimateAmount: draft.estimateAmount,
        );
        if (!mounted) return;
        _updatePayableInLocal(existingId, {
          'name': draft.name,
          'amount': draft.amount,
          'frequency': draft.frequency,
          'dueDate': draft.dueDate?.toIso8601String(),
          'notes': draft.notes,
          'vendor': draft.vendor,
          'isVariable': draft.isVariable,
          'estimateAmount': draft.estimateAmount,
        });
        _snack('Bill updated');
      } else {
        final result = await ApiService.createPayable(
          name: draft.name,
          amount: draft.amount,
          frequency: draft.frequency,
          dueDate: draft.dueDate,
          notes: draft.notes,
          vendor: draft.vendor,
          dueDay: draft.dueDay,
          dueDays: draft.dueDays,
          dueMonth: draft.dueMonth,
          isVariable: draft.isVariable,
          estimateAmount: draft.estimateAmount,
        );
        final newPayable = result['data'] as Map<String, dynamic>?;
        final payableId = (newPayable?['id'] ?? '').toString();
        if (draft.reminderEnabled &&
            payableId.isNotEmpty &&
            _eateryId != null) {
          try {
            await FirebaseFirestore.instance
                .collection('eateries')
                .doc(_eateryId)
                .collection('payables')
                .doc(payableId)
                .update({
              'reminderEnabled': true,
              'reminderDaysBefore': draft.reminderDaysBefore ?? 3,
              'reminderTime': draft.reminderTime,
            });
          } catch (_) {
            // Reminder update failed but payable was created.
          }
        }
        if (!mounted) return;
        if (newPayable != null) _addPayableToLocal(newPayable);
        _snack('Payable added');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to ${isEdit ? 'update' : 'add'} payable: $e');
    }
  }

  Future<void> _togglePayablePaid(Map<String, dynamic> payable) async {
    final id = (payable['id'] ?? '').toString();
    if (id.isEmpty) return;
    final isPaid = FinanceMetrics.isPaid(payable);

    if (isPaid) {
      await _unpayPayable(payable, id);
      return;
    }

    // Determine the amount: fixed bills use their stored amount; variable
    // bills (utilities) prompt for the actual amount this cycle.
    double amount;
    if (FinanceMetrics.isVariablePayable(payable)) {
      final entered = await PayablePaymentDialog.show(
        context,
        payable: payable,
        currencySymbol: _currencySymbol,
      );
      if (entered == null || !mounted) return;
      amount = entered;
    } else {
      amount = FinanceMetrics.amountOf(payable);
      if (amount <= 0) {
        _snack('This bill has no amount set. Add an amount or mark it variable.');
        return;
      }
    }

    try {
      final result = await ApiService.recordPayablePayment(
        payable: payable,
        amount: amount,
        category: 'Bills',
      );
      if (!mounted) return;
      final newExpense = result['data'] as Map<String, dynamic>?;
      // Drop any previously mirrored expense for this bill before adding the
      // fresh one so the ledger stays single-sourced.
      final prior = _findExpenseByLinkedPayable(id);
      if (prior != null) _removeExpenseFromLocal((prior['id'] ?? '').toString());
      if (newExpense != null) _addExpenseToLocal(newExpense);

      final history = [
        ...((payable['amountHistory'] is List)
            ? (payable['amountHistory'] as List)
            : const []),
        {'amount': amount, 'date': DateTime.now().toIso8601String()},
      ];
      if (history.length > 12) {
        history.removeRange(0, history.length - 12);
      }
      _updatePayableInLocal(id, {
        'status': 'paid',
        'lastAmount': amount,
        'amountHistory': history,
        'averageAmount': _averageOf(history),
      });
      _snack('Bill marked paid');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to mark bill paid: $e');
    }
  }

  /// Reverts a paid bill: removes the mirrored expense and flips status back.
  Future<void> _unpayPayable(Map<String, dynamic> payable, String id) async {
    try {
      await ApiService.removePayablePaymentExpense(id);
      await ApiService.updatePayableStatus(id, status: 'unpaid');
      if (!mounted) return;
      final prior = _findExpenseByLinkedPayable(id);
      if (prior != null) _removeExpenseFromLocal((prior['id'] ?? '').toString());
      _updatePayableInLocal(id, {'status': 'unpaid'});
      _snack('Bill marked unpaid');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to update payable: $e');
    }
  }

  Map<String, dynamic>? _findExpenseByLinkedPayable(String payableId) {
    for (final e in _expenses) {
      if ((e['linkedPayableId'] ?? '').toString() == payableId) return e;
    }
    return null;
  }

  Map<String, dynamic>? _payableById(String id) {
    for (final p in _payables) {
      if ((p['id'] ?? '').toString() == id) return p;
    }
    return null;
  }

  /// Un-pays the bill that produced [expense], removing the mirrored entry.
  /// Used from the Expenses tab so bill rows stay consistent with payables.
  Future<void> _unpayBillFromExpense(Map<String, dynamic> expense) async {
    final payableId = (expense['linkedPayableId'] ?? '').toString();
    final payable = payableId.isEmpty ? null : _payableById(payableId);
    if (payable == null) {
      // Orphaned mirror (bill gone): fall back to deleting the expense.
      await _deleteExpense(expense);
      return;
    }
    await _unpayPayable(payable, payableId);
  }

  double _averageOf(List<dynamic> history) {
    var total = 0.0;
    var count = 0;
    for (final item in history) {
      if (item is Map) {
        final v = item['amount'];
        if (v is num && v > 0) {
          total += v.toDouble();
          count++;
        }
      }
    }
    if (count == 0) return 0;
    return double.parse((total / count).toStringAsFixed(2));
  }

  Future<void> _deletePayable(Map<String, dynamic> payable) async {
    final id = (payable['id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (payable['name'] ?? 'this payable').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete payable?'),
        content: Text('Delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deletePayable(id);
      if (!mounted) return;
      _removePayableFromLocal(id);
      _snack('Payable deleted');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete payable: $e');
    }
  }

  void _openPayable(Map<String, dynamic> payable) {
    PayableDetailSheet.show(
      context,
      payable: payable,
      fmt: _fmt,
      isAdmin: _isAdmin,
      onEdit: () => _editPayable(payable),
      onDelete: () => _deletePayable(payable),
      onTogglePaid: () => _togglePayablePaid(payable),
    );
  }

  // ---------------------------------------------------------------------------
  // Budgets & export
  // ---------------------------------------------------------------------------

  Future<void> _editBudgets() async {
    final result = await FinanceBudgetsDialog.show(
      context,
      categories: _expenseCategories,
      budgets: _budgets,
      currencySymbol: _currencySymbol,
    );
    if (result == null) return;
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(uid)
          .set(
        {FinanceBudgetStore.key: result},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _budgets = result);
      _snack('Budgets saved');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to save budgets: $e');
    }
  }

  Future<void> _exportExpenses() async {
    await _exportCsv(
      'expenses',
      FinanceExportService.buildExpensesCsv(_expenses, _fmt),
    );
  }

  Future<void> _exportPayables() async {
    await _exportCsv(
      'payables',
      FinanceExportService.buildPayablesCsv(_payables, _fmt),
    );
  }

  Future<void> _exportCsv(String name, String contents) async {
    try {
      final path = await FinanceExportService.writeCsv(name, contents);
      if (!mounted) return;
      _snack('Exported to $path');
    } catch (e) {
      if (!mounted) return;
      _snack('Export failed: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens Inventory as a pushed route so its own back button returns to
  /// Finance. Falls back to the outer tab handler only when embedded.
  void _openInventory() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const InventoryScreen(showAppBar: true),
      ),
    );
  }

  /// Opens Staff Management as a pushed route so back returns to Finance.
  void _openStaff() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const StaffManagementScreen(showAppBar: true),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Handles a back press/gesture: unwinds the inner tab stack first, then
  /// lets the shell handle it. Return true when the event was consumed.
  bool _handleBack() {
    if (_popFinanceTab()) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final canUnwind = _tabHistory.length > 1;
    return PopScope(
      canPop: !canUnwind,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                leading: widget.onOpenDrawer != null
                    ? IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: 'Menu',
                        onPressed: widget.onOpenDrawer,
                      )
                    : (canUnwind
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Back',
                            onPressed: () => _handleBack(),
                          )
                        : (Navigator.of(context).canPop()
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              )
                            : null)),
                title: const Text('Finance'),
                actions: [
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              )
            : null,
        body: _buildBody(),
        bottomNavigationBar: _isLoading || _error != null
            ? null
            : BottomNavigationBar(
                currentIndex: _index,
                onTap: _selectSection,
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    label: 'Overview',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Expenses',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.payment_outlined),
                    label: 'Payables',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.analytics_outlined),
                    label: 'Reports',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.groups_outlined),
                    label: 'Payroll',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonDashboard();
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppTheme.error),
              const SizedBox(height: 12),
              Text(
                'Failed to load finance data:\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    // Sections are swapped in place (like the Inventory page) rather than
    // kept alive in a PageView, so switching tabs is a cheap rebuild.
    switch (_index) {
      case 1:
        return FinanceExpensesTab(
          expenses: _expenses,
          isAdmin: _isAdmin,
          fmt: _fmt,
          sourceFilter: _expenseSourceFilter,
          categoryFilter: _expenseCategoryFilter,
          dateRange: _expenseDateRange,
          searchQuery: _searchQuery,
          onSourceFilterChanged: (v) =>
              setState(() => _expenseSourceFilter = v),
          onCategoryFilterChanged: (v) =>
              setState(() => _expenseCategoryFilter = v),
          onDateRangeChanged: (v) => setState(() => _expenseDateRange = v),
          onSearchChanged: (v) => setState(() => _searchQuery = v),
          onAdd: _addExpense,
          onOpen: _openExpense,
          onDelete: _deleteExpense,
          onViewPurchase: (e) => _openInventory(),
          onUnpayBill: _unpayBillFromExpense,
        );
      case 2:
        return FinancePayablesTab(
          payables: _payables,
          isAdmin: _isAdmin,
          fmt: _fmt,
          segment: _payablesSegment,
          onSegmentChanged: (v) => setState(() => _payablesSegment = v),
          onAdd: _addPayable,
          onOpen: _openPayable,
          onExport: _exportPayables,
        );
      case 3:
        return FinanceReportsTab(
          expenses: _expenses,
          payables: _payables,
          orders: _orders,
          itemPerformance: _itemPerformance,
          stockMovements: _stockMovements,
          inventoryItems: _inventoryItems,
          damagedItems: _damagedItems,
          salesForecast: _salesForecast,
          fmt: _fmt,
          budgets: _budgets,
          onEditBudgets: _editBudgets,
          onExport: (_) => _exportExpenses(),
        );
      case 4:
        return FinancePayrollTab(
          eateryId: _eateryId,
          fmt: _fmt,
          staffUsersStream: _staffUsersFor,
          staffProfilesStream: _staffProfilesFor,
          onNavigateToStaff: _openStaff,
        );
      default:
        return FinanceOverviewTab(
          expenses: _expenses,
          payables: _payables,
          orders: _orders,
          itemPerformance: _itemPerformance,
          dailySales: _dailySales,
          stockMovements: _stockMovements,
          inventoryItems: _inventoryItems,
          damagedItems: _damagedItems,
          salesForecast: _salesForecast,
          isAdmin: _isAdmin,
          isLoading: _isLoading,
          fmt: _fmt,
          onOpenExpenses: () => _goToFinanceTab(1),
          onOpenPayables: () => _goToFinanceTab(2),
          onAddExpense: _addExpense,
          onAddPayable: _addPayable,
          onOpenExpense: _openExpense,
          onOpenPayable: _openPayable,
          onExport: () => _exportExpenses(),
        );
    }
  }
}
