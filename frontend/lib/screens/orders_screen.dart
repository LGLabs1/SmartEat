import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/pos_settings_service.dart';
import '../services/sound_service.dart';
import '../widgets/dashboard/empty_state.dart';
import '../widgets/dashboard/kpi_card.dart';
import '../widgets/dashboard/section_card.dart';
import '../widgets/payment_method_dialog.dart';
// Shares the incomplete-order row with the admin dashboard. It lives in
// dashboard_screen.dart rather than a widget file because it is already
// public there, and a widget-to-widget import would be the larger change.
import 'dashboard_screen.dart' show IncompleteOrderRow;

/// Today's orders, shared by the admin and staff dashboards.
///
/// Both roles see today's orders with the same actions (complete, add-items
/// edit, void). Only admins additionally get the **History** view — past days
/// are a management concern, and staff already have the Orders tab on the POS
/// side of their dashboard for the current day.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({Key? key, this.isAdmin = false}) : super(key: key);

  /// Admins only: enables the Today/History view switch.
  final bool isAdmin;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Stream<List<Map<String, dynamic>>>? _ordersStream;
  _StatusFilter _statusFilter = _StatusFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // History view — admins only.
  bool _showingHistory = false;
  bool _loadingHistory = false;
  String? _historyError;
  List<Map<String, dynamic>> _history = const [];
  _HistoryRange _historyRange = _HistoryRange.sevenDays;

  // Incomplete orders (opened on an earlier day, never completed) — admins
  // only. Moved here from the admin home dashboard so every order workflow
  // lives on one page.
  bool _loadingIncomplete = false;
  String? _incompleteError;
  List<Map<String, dynamic>> _incomplete = const [];
  String _completingOrderId = '';
  bool _completingAll = false;

  @override
  void initState() {
    super.initState();
    _initOrdersStream();
    if (widget.isAdmin) _loadIncomplete();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIncomplete() async {
    if (mounted) {
      setState(() {
        _loadingIncomplete = true;
        _incompleteError = null;
      });
    }
    try {
      final orders = await FirebaseService.getIncompleteOrders();
      if (!mounted) return;
      setState(() {
        _incomplete = orders;
        _loadingIncomplete = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _incompleteError = e.toString();
        _loadingIncomplete = false;
      });
    }
  }

  Future<void> _completeIncomplete(String orderId) async {
    if (orderId.isEmpty) return;
    setState(() => _completingOrderId = orderId);
    try {
      await ApiService.completeOrder(orderId);
      await SoundService.playOrderCompleted();
      if (!mounted) return;
      await _loadIncomplete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order completed. Stocks updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete order: $e')),
      );
    } finally {
      if (mounted) setState(() => _completingOrderId = '');
    }
  }

  Future<void> _completeAllIncomplete() async {
    if (_incomplete.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete All Incomplete Orders'),
        content: Text(
          'Are you sure you want to complete all ${_incomplete.length} incomplete orders?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completingAll = true);
    int completed = 0;
    int failed = 0;
    for (final order in _incomplete) {
      final id = (order['id'] ?? '').toString();
      if (id.isEmpty) continue;
      try {
        await ApiService.completeOrder(id);
        completed++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _completingAll = false);
    await _loadIncomplete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Completed $completed incomplete orders'
          '${failed > 0 ? ', $failed failed' : ''}. Stocks updated.',
        ),
      ),
    );
  }

  /// Mints a fresh today-orders stream.
  ///
  /// [FirebaseService.getTodayOrdersStream] returns a single-subscription
  /// stream, so it can only ever be listened to once. Leaving the Today view
  /// tears down the StreamBuilder's subscription, and re-entering would try to
  /// listen to that same exhausted stream and throw "Stream has already been
  /// listened to". Clearing the field first and always creating a new stream
  /// sidesteps that entirely.
  Future<void> _initOrdersStream() async {
    if (mounted) setState(() => _ordersStream = null);
    final stream = await FirebaseService.getTodayOrdersStream();
    if (!mounted) return;
    setState(() => _ordersStream = stream);
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final orders = await FirebaseService.getOrderHistory();
      if (!mounted) return;
      setState(() {
        _history = orders;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString();
        _loadingHistory = false;
      });
    }
  }

  void _setView({required bool history}) {
    if (_showingHistory == history) return;
    setState(() => _showingHistory = history);

    if (history) {
      // Loaded lazily — staff never triggers this, and admins only pay for it
      // the first time they open History.
      if (_history.isEmpty &&
          !_loadingHistory &&
          _historyError == null) {
        _loadHistory();
      }
      return;
    }

    // Returning to Today rebuilds the StreamBuilder. It needs a stream it has
    // not already consumed, because getTodayOrdersStream() hands back a
    // single-subscription stream and the previous one was cancelled when the
    // History view replaced it. Re-listening to that one throws
    // "Stream has already been listened to", so always mint a fresh one.
    _initOrdersStream();
  }

  @override
  Widget build(BuildContext context) {
    if (_showingHistory) {
      return RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
children: [
              _buildViewSwitch(),
              const SizedBox(height: 16),
              _buildIncompleteSection(),
              const SizedBox(height: 16),
              if (_loadingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_historyError != null)
                _buildHistoryError()
              else ...[
                _buildHistoryRangeBar(),
                const SizedBox(height: 16),
                _buildHistoryKpiRow(),
                const SizedBox(height: 16),
                _buildHistoryList(),
              ],
            ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <Map<String, dynamic>>[];

        return RefreshIndicator(
          onRefresh: _initOrdersStream,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (widget.isAdmin) _buildViewSwitch(),
              if (widget.isAdmin) const SizedBox(height: 16),
              _buildKpiRow(orders),
              const SizedBox(height: 16),
              _buildFilterBar(orders),
              const SizedBox(height: 16),
              _buildOrdersList(orders),
              // Incomplete orders live here rather than on the admin home
              // dashboard, so all order work is on one page.
              if (widget.isAdmin) ...[
                const SizedBox(height: 16),
                _buildIncompleteSection(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewSwitch() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          label: Text('Today'),
          icon: Icon(Icons.today, size: 18),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('History'),
          icon: Icon(Icons.history, size: 18),
        ),
      ],
      selected: {_showingHistory},
      onSelectionChanged: (selection) =>
          _setView(history: selection.first),
    );
  }

  Widget _buildHistoryError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load history',
            subtitle: _historyError,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildIncompleteSection() {
    if (_loadingIncomplete && _incomplete.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_incompleteError != null && _incomplete.isEmpty) {
      return SectionCard(
        title: 'Incomplete Orders',
        icon: Icons.pending_actions_outlined,
        iconColor: Colors.red,
        child: Column(
          children: [
            EmptyState(
              icon: Icons.cloud_off,
              title: 'Could not load incomplete orders',
              subtitle: _incompleteError,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadIncomplete,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SectionCard(
      title: 'Incomplete Orders',
      icon: Icons.pending_actions_outlined,
      iconColor: Colors.red,
      badge: _incomplete.isEmpty ? null : '${_incomplete.length}',
      action: (_incomplete.isEmpty || _completingAll)
          ? (_completingAll
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null)
          : TextButton.icon(
              onPressed: _completeAllIncomplete,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Complete All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
      child: _incomplete.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No incomplete orders',
              subtitle:
                  'Orders opened on an earlier day that are still pending will appear here.',
            )
          : Column(
              children: [
                Text(
                  'Orders from previous days that still need completion:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final order in _incomplete)
                  IncompleteOrderRow(
                    orderId: (order['id'] ?? '').toString(),
                    total:
                        (order['totalAmount'] as num?)?.toDouble() ?? 0.0,
                    dateText: _relativeDayText(_createdAtOf(order)),
                    isCompleting: _completingOrderId == (order['id'] ?? ''),
                    onTap: () => _showOrderDetails(order),
                    onComplete: () =>
                        _completeIncomplete((order['id'] ?? '').toString()),
                  ),
              ],
            ),
    );
  }

  static String _relativeDayText(DateTime? createdAt) {
    if (createdAt == null) return 'Unknown date';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(createdAt.year, createdAt.month, createdAt.day))
        .inDays;
    if (days <= 0) return 'Today';
    return days == 1 ? 'Yesterday' : '$days days ago';
  }

  Widget _buildHistoryRangeBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search by order number or item',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final range in _HistoryRange.values)
              ChoiceChip(
                label: Text(range.label),
                selected: _historyRange == range,
                onSelected: (_) => setState(() => _historyRange = range),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _StatusFilter.values)
              ChoiceChip(
                label: Text(
                  '${filter.label} (${_filteredHistory().where((o) => filter.matches(_statusKeyOf(o))).length})',
                ),
                selected: _statusFilter == filter,
                onSelected: (_) => setState(() => _statusFilter = filter),
              ),
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filteredHistory() {
    final cutoff = _historyRange.cutoff();
    final query = _searchQuery.trim().toLowerCase();
    return _history
        .where((o) {
          final created = _createdAtOf(o);
          if (created != null && cutoff != null && created.isAfter(cutoff)) {
            return false;
          }
          return _statusFilter.matches(_statusKeyOf(o)) &&
              _matchesQuery(o, query);
        })
        .toList();
  }

  Widget _buildHistoryKpiRow() {
    final visible = _filteredHistory();
    final completed = visible
        .where((o) => _statusKeyOf(o) == 'completed')
        .toList();
    final revenue = completed.fold<double>(
      0,
      (sum, o) => sum + ((o['totalAmount'] as num?)?.toDouble() ?? 0.0),
    );
    final scheme = Theme.of(context).colorScheme;

    final cards = <Widget>[
      KpiCard(
        title: 'Orders',
        value: '${visible.length}',
        icon: Icons.receipt_long_outlined,
        color: scheme.tertiary,
        description: 'Orders in the current view/filter (includes all statuses shown).',
      ),
      KpiCard(
        title: 'Completed',
        value: '${completed.length}',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF16A34A),
        description: 'Orders marked completed in the current view.',
      ),
      KpiCard(
        title: 'Items Sold',
        value: '${_totalItems(visible)}',
        icon: Icons.shopping_bag_outlined,
        color: scheme.secondary,
        description: 'Total item quantity from orders in the current view.',
      ),
      KpiCard(
        title: 'Revenue',
        value: '₱${revenue.toStringAsFixed(0)}',
        icon: Icons.attach_money,
        color: const Color(0xFF1E88E5),
        description: 'Total from completed orders in the current view (stored order totals; not a net/gross sales split).',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  int _totalItems(List<Map<String, dynamic>> orders) {
    var total = 0;
    for (final order in orders) {
      final items = order['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final qty = item['quantity'];
            total += qty is num ? qty.toInt() : 1;
          }
        }
      }
    }
    return total;
  }

  Widget _buildHistoryList() {
    final visible = _filteredHistory();

    return SectionCard(
      title: 'Completed Orders History',
      icon: Icons.history,
      badge: '${visible.length}',
      child: _history.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No past orders',
              subtitle: 'Completed orders from previous days will appear here.',
            )
          : visible.isEmpty
              ? const EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No matching orders',
                  subtitle: 'Try a different range, status or search term.',
                )
              : Column(
                  children: [
                    for (final order in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OrderRow(
                          order: order,
                          showDate: true,
                          onTap: () => _showOrderDetails(order),
                        ),
                      ),
                  ],
                ),
    );
  }

  // ── Summary tiles ────────────────────────────────────────────────────────
  Widget _buildKpiRow(List<Map<String, dynamic>> orders) {
    final scheme = Theme.of(context).colorScheme;
    final completed = orders.where((o) => _statusKeyOf(o) == 'completed').toList();
    final pending =
        orders.where((o) => _statusKeyOf(o) == 'pending').length;
    final revenue = completed.fold<double>(
      0,
      (sum, o) => sum + ((o['totalAmount'] as num?)?.toDouble() ?? 0.0),
    );

    final cards = <Widget>[
      KpiCard(
        title: 'Total Orders',
        value: '${orders.length}',
        icon: Icons.receipt_long_outlined,
        color: scheme.tertiary,
        description: 'All orders in the current view/filter.',
      ),
      KpiCard(
        title: 'Pending',
        value: '$pending',
        icon: Icons.schedule,
        color: scheme.secondary,
        description: 'Orders not completed/cancelled in the current view.',
      ),
      KpiCard(
        title: 'Completed',
        value: '${completed.length}',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF16A34A),
        description: 'Orders marked completed in the current view.',
      ),
      KpiCard(
        title: 'Revenue',
        value: '₱${revenue.toStringAsFixed(0)}',
        icon: Icons.attach_money,
        color: const Color(0xFF1E88E5),
        description: 'Total from completed orders in the current view (stored order totals; not a net/gross sales split).',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width =
            (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  // ── Filter + search ──────────────────────────────────────────────────────
  Widget _buildFilterBar(List<Map<String, dynamic>> orders) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search by order number or item',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _StatusFilter.values)
              ChoiceChip(
                label: Text(
                  '${filter.label} (${orders.where((o) => filter.matches(_statusKeyOf(o))).length})',
                ),
                selected: _statusFilter == filter,
                onSelected: (_) => setState(() => _statusFilter = filter),
              ),
          ],
        ),
      ],
    );
  }

  // ── List ─────────────────────────────────────────────────────────────────
  Widget _buildOrdersList(List<Map<String, dynamic>> orders) {
    final query = _searchQuery.trim().toLowerCase();
    final visible = orders
        .where((o) => _statusFilter.matches(_statusKeyOf(o)))
        .where((o) => _matchesQuery(o, query))
        .toList();

    return SectionCard(
      title: "Today's Orders",
      icon: Icons.receipt_long_outlined,
      badge: '${visible.length}',
      child: orders.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet today',
              subtitle: 'Orders placed today will appear here.',
            )
          : visible.isEmpty
              ? const EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No matching orders',
                  subtitle: 'Try a different status or search term.',
                )
              : Column(
                  children: [
                    for (final order in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OrderRow(
                          order: order,
                          onTap: () => _showOrderDetails(order),
                        ),
                      ),
                  ],
                ),
    );
  }

  bool _matchesQuery(Map<String, dynamic> order, String query) {
    if (query.isEmpty) return true;
    if ((order['id'] ?? '').toString().toLowerCase().contains(query)) {
      return true;
    }
    final items = order['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map &&
            (item['name'] ?? '').toString().toLowerCase().contains(query)) {
          return true;
        }
      }
    }
    return false;
  }

  // ── Order details ────────────────────────────────────────────────────────
  void _showOrderDetails(Map<String, dynamic> order) {
    final id = (order['id'] ?? '').toString();
    final items = order['items'] as List<dynamic>? ?? [];
    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final status = (order['status'] ?? 'unknown').toString();
    final createdAt = order['createdAt'];
    final isPending = status.trim().toLowerCase() == 'pending';

    // Payment details, when captured at checkout. Orders created before the
    // payment feature have a paymentMethod ('cash' was hardcoded) but no
    // further payment fields.
    final paymentMethod = (order['paymentMethod'] ?? '').toString().trim();
    final paymentStatus = (order['paymentStatus'] ?? '').toString().trim();
    final referenceNumber = (order['referenceNumber'] ?? '').toString().trim();
    final amountReceived = (order['amountReceived'] as num?)?.toDouble();
    final changeDue = (order['change'] as num?)?.toDouble();
    final hasPaymentDetails = !isPending &&
        paymentMethod.isNotEmpty &&
        (paymentStatus.isNotEmpty ||
            referenceNumber.isNotEmpty ||
            amountReceived != null);
    final paymentStatusLabel = paymentStatus.isEmpty
        ? ''
        : ' — ${paymentStatus[0].toUpperCase()}${paymentStatus.substring(1)}';

    String? formattedDate;
    if (createdAt != null) {
      if (createdAt is Timestamp) {
        formattedDate = _formatDateTime(createdAt.toDate());
      } else if (createdAt is DateTime) {
        formattedDate = _formatDateTime(createdAt);
      }
    }

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(id.isEmpty
              ? 'Order Details'
              : 'Order #${id.substring(0, id.length > 8 ? 8 : id.length)}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: ${status.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Total: ₱${total.toStringAsFixed(2)}'),
                if (hasPaymentDetails) ...[
                  const SizedBox(height: 4),
                  Text(
                      'Payment: ${paymentMethodLabel(paymentMethod)}$paymentStatusLabel'),
                  if (referenceNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Reference #: $referenceNumber'),
                  ],
                  if (amountReceived != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        'Amount Received: ₱${amountReceived.toStringAsFixed(2)}'),
                  ],
                  if (changeDue != null) ...[
                    const SizedBox(height: 4),
                    Text('Change: ₱${changeDue.toStringAsFixed(2)}'),
                  ],
                ],
                if (formattedDate != null) ...[
                  const SizedBox(height: 4),
                  Text('Created: $formattedDate'),
                ],
                const SizedBox(height: 16),
                const Text('Items:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final name = (item is Map
                      ? (item['name'] ?? 'Unknown').toString()
                      : 'Unknown');
                  final qty = (item is Map ? (item['quantity'] ?? 1) : 1);
                  final price = (item is Map
                      ? (item['price'] as num?)?.toDouble() ?? 0.0
                      : 0.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('$qty x $name'),
                        const Spacer(),
                        Text('₱${(price * qty).toStringAsFixed(2)}'),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            if (isPending) ...[
              // Complete button
              FilledButton.icon(
                onPressed: () async {
                  // Collect payment details before completing. Whether to
                  // offer a receipt is an eatery-level setting.
                  var askForReceipt = false;
                  try {
                    askForReceipt =
                        (await PosSettingsService.load()).askForReceipt;
                  } catch (_) {
                    // Setting unavailable — skip the receipt offer.
                  }
                  if (!mounted) return;
                  final details = await showPaymentDetailsDialog(
                    dialogContext,
                    totalAmount: total,
                    askForReceipt: askForReceipt,
                  );
                  if (details == null) return; // cancelled

                  try {
                    await ApiService.completeOrder(
                      id,
                      paymentMethod: details.method,
                      amountReceived: details.amountReceived,
                      change: details.change,
                      referenceNumber: details.referenceNumber,
                      paymentStatus: details.paymentStatus,
                    );
                    await SoundService.playOrderCompleted();
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    final receiptNote = details.wantsReceipt
                        ? ' Receipt printing will be available once a '
                            'printer is connected.'
                        : '';
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                          content:
                              Text('Order completed successfully.$receiptNote')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Failed to complete order: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Complete'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
              // Edit button
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showEditOrderDialog(order);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue),
              ),
              // Void button
              FilledButton.icon(
                onPressed: () async {
                  final controller = TextEditingController();
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Void Order'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Reason (optional)',
                          hintText: 'Enter reason for voiding',
                        ),
                        maxLines: 2,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Void'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) {
                    controller.dispose();
                    return;
                  }
                  try {
                    await ApiService.voidOrder(id, reason: controller.text);
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Order voided successfully.')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to void order: $e')),
                    );
                  } finally {
                    controller.dispose();
                  }
                },
                icon: const Icon(Icons.cancel),
                label: const Text('Void'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final year = dateTime.year;
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year at $hour:$minute $period';
  }

  Future<void> _showEditOrderDialog(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;

    // Get current items
    final itemsRaw = order['items'] as List<dynamic>? ?? [];
    final currentItems = List<Map<String, dynamic>>.from(
      itemsRaw.where((item) => item is Map).cast<Map<String, dynamic>>(),
    );

    // Load available menu items
    List<Map<String, dynamic>> menuItems = [];
    try {
      final response = await ApiService.getMenuItems();
      if (response['data'] != null) {
        final items = response['data'] as List<dynamic>;
        menuItems = items
            .where((item) => item is Map)
            .cast<Map<String, dynamic>>()
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load menu: $e')),
        );
      }
      return;
    }

    // Track items to add
    final List<Map<String, dynamic>> itemsToAdd = [];
    double additionalTotal = 0.0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current items section
                    const Text(
                      'Current Items',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: currentItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          return Row(
                            children: [
                              Expanded(child: Text('$qty x $name')),
                              Text('₱${(price * qty).toStringAsFixed(2)}'),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 24),

                    // Add items section
                    const Text(
                      'Add Items',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: menuItems.length,
                        itemBuilder: (context, index) {
                          final item = menuItems[index];
                          final name = (item['name'] ?? 'Unknown').toString();
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          final itemId = (item['id'] ?? '').toString();

                          // Find if this item is already in itemsToAdd
                          final existingIndex = itemsToAdd.indexWhere(
                            (i) =>
                                (i['menuId'] ?? i['id'] ?? '').toString() ==
                                itemId,
                          );
                          final existingQty = existingIndex >= 0
                              ? (itemsToAdd[existingIndex]['quantity'] as num?)
                                      ?.toInt() ??
                                  0
                              : 0;

                          return ListTile(
                            dense: true,
                            title: Text(name),
                            subtitle: Text('₱${price.toStringAsFixed(2)}'),
                            trailing: existingQty > 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                          ['quantity']
                                                      as num?)
                                                      ?.toInt() ??
                                                  1;
                                              if (currentQty <= 1) {
                                                itemsToAdd
                                                    .removeAt(existingIndex);
                                              } else {
                                                itemsToAdd[existingIndex]
                                                        ['quantity'] =
                                                    currentQty - 1;
                                              }
                                              additionalTotal -= price;
                                            }
                                          });
                                        },
                                      ),
                                      Text('$existingQty'),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                          ['quantity']
                                                      as num?)
                                                      ?.toInt() ??
                                                  1;
                                              itemsToAdd[existingIndex]
                                                      ['quantity'] = currentQty + 1;
                                            } else {
                                              itemsToAdd.add({
                                                'menuId': itemId,
                                                'name': name,
                                                'price': price,
                                                'quantity': 1,
                                              });
                                            }
                                            additionalTotal += price;
                                          });
                                        },
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    onPressed: () {
                                      setLocalState(() {
                                        itemsToAdd.add({
                                          'menuId': itemId,
                                          'name': name,
                                          'price': price,
                                          'quantity': 1,
                                        });
                                        additionalTotal += price;
                                      });
                                    },
                                  ),
                          );
                        },
                      ),
                    ),

                    // Additional total
                    if (itemsToAdd.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Additional Amount:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₱${additionalTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                if (itemsToAdd.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.save),
                    label: const Text('Add Items'),
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == true && itemsToAdd.isNotEmpty && mounted) {
      try {
        await ApiService.addItemsToOrder(orderId, itemsToAdd);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Items added to order successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _statusKeyOf(Map<String, dynamic> order) =>
    (order['status'] ?? '').toString().trim().toLowerCase();

/// Status buckets offered as filter chips. `voided` also matches `rejected`
/// because both are terminal, non-revenue states in the orders collection.
enum _StatusFilter {
  all('All'),
  pending('Pending'),
  completed('Completed'),
  voided('Voided');

  const _StatusFilter(this.label);

  final String label;

  bool matches(String statusKey) {
    switch (this) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.pending:
        return statusKey == 'pending';
      case _StatusFilter.completed:
        return statusKey == 'completed';
      case _StatusFilter.voided:
        return statusKey == 'voided' || statusKey == 'rejected';
    }
  }
}

class _StatusStyle {
  final Color color;
  final Color background;
  final IconData icon;

  const _StatusStyle(this.color, this.background, this.icon);
}

_StatusStyle _statusStyleFor(BuildContext context, String statusKey) {
  final scheme = Theme.of(context).colorScheme;
  switch (statusKey) {
    case 'completed':
      return _StatusStyle(
        scheme.secondary,
        scheme.secondary.withValues(alpha: 0.1),
        Icons.check_circle,
      );
    case 'pending':
      return _StatusStyle(
        scheme.secondary,
        scheme.secondary.withValues(alpha: 0.1),
        Icons.schedule,
      );
    case 'rejected':
    case 'voided':
      return _StatusStyle(
        scheme.error,
        scheme.error.withValues(alpha: 0.1),
        Icons.cancel,
      );
    default:
      return _StatusStyle(
        scheme.onSurfaceVariant,
        scheme.onSurfaceVariant.withValues(alpha: 0.1),
        Icons.help_outline,
      );
  }
}

DateTime? _createdAtOf(Map<String, dynamic> order) {
  final createdAt = order['createdAt'];
  if (createdAt is Timestamp) return createdAt.toDate();
  if (createdAt is DateTime) return createdAt;
  return DateTime.tryParse(createdAt?.toString() ?? '');
}

/// Rolling windows for the History filter. `null` cutoff means "no limit".
enum _HistoryRange {
  sevenDays('Last 7 days', 7),
  thirtyDays('Last 30 days', 30),
  ninetyDays('Last 90 days', 90),
  allTime('All time', null);

  const _HistoryRange(this.label, this.days);

  final String label;
  final int? days;

  DateTime? cutoff() {
    final d = days;
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
  }
}

/// One order row: status glyph, order number, item count, total and status pill.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.onTap,
    this.showDate = false,
  });

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  /// History rows carry a date instead of the bare item count.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = (order['id'] ?? '').toString();
    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final status = (order['status'] ?? '').toString().trim();
    final itemsRaw = order['items'];
    final items = itemsRaw is List ? itemsRaw : const [];
    final style = _statusStyleFor(context, status.toLowerCase());
    final createdAt = _createdAtOf(order);
    final subtitle = showDate && createdAt != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt)
        : '${items.length} item${items.length != 1 ? 's' : ''}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    id.isEmpty
                        ? 'Order'
                        : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.isEmpty ? 'Unknown' : status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: style.color,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
