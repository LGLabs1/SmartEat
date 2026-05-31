import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({Key? key, this.showAppBar = true, this.onOpenDrawer})
      : super(key: key);

  final bool showAppBar;
  final VoidCallback? onOpenDrawer;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _KpiMiniCard extends StatelessWidget {
  const _KpiMiniCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactKpiItem extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isNarrow;

  const _CompactKpiItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isNarrow,
  });

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      // Ultra-compact for narrow screens - icon + text horizontal
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Standard compact for wider screens
    return Container(
      width: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late VoidCallback _tabListener;
  Map<String, dynamic>? _summaryStats;
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> _itemPerformance = [];
  List<Map<String, dynamic>> _topSellingItems = [];
  List<Map<String, dynamic>> _ordersForecast = [];
  List<Map<String, dynamic>> _salesForecast = [];
  Map<String, dynamic>? _recommendations;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _payables = [];
  bool _isLoading = false;

  int _rangeDays = 7;
  int _selectedRangeDays = 14;
  DateTimeRange? _customRange;
  String? _selectedMonthYear;
  DateTime? _selectedMonth;
  bool _showKpis = false;

  // Year/Month slicers (new)
  int? _selectedYear; // null = All
  int? _selectedMonthNumber; // null = All (1-12 when selected)

  // Cached availability (derived from orders, not from currently displayed chart data)
  List<int> _availableYears = [];
  final Map<int, List<int>> _availableMonthsByYear = {};

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  bool _looksLikeNetworkIssue(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('unavailable') &&
            (s.contains('unable to resolve host') ||
                s.contains('firestore.googleapis.com')) ||
        s.contains('failed to fetch');
  }

  Map<String, dynamic> _processOrdersToDailySales(
      List<dynamic> orders, int days, DateTime startDate) {
    // Group orders by date and calculate daily totals
    final salesByDate = <String, Map<String, dynamic>>{};

    // Initialize all dates with zero values starting from startDate (UTC normalized)
    for (var i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final utcDate = DateTime.utc(date.year, date.month, date.day);
      final dateStr = DateFormat('yyyy-MM-dd').format(utcDate);
      salesByDate[dateStr] = {
        'date': dateStr,
        'revenue': 0.0,
        'orders': 0,
      };
    }

    // Aggregate order data
    for (final order in orders) {
      if (order is! Map) continue;
      final createdAt = order['createdAt'];
      if (createdAt == null) continue;

      DateTime? orderDate;
      if (createdAt is String) {
        orderDate = DateTime.tryParse(createdAt);
      } else if (createdAt is Timestamp) {
        orderDate = createdAt.toDate();
      } else if (createdAt is DateTime) {
        orderDate = createdAt;
      } else if (createdAt is int) {
        // Timestamp in milliseconds
        orderDate = DateTime.fromMillisecondsSinceEpoch(createdAt);
      }
      if (orderDate == null) continue;

      // Normalize to UTC date only (ignore time component)
      final utcDate =
          DateTime.utc(orderDate.year, orderDate.month, orderDate.day);
      final dateStr = DateFormat('yyyy-MM-dd').format(utcDate);

      if (!salesByDate.containsKey(dateStr)) continue;

      final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final status = (order['status'] ?? '').toString().toLowerCase();

      // Only count completed orders
      if (status == 'completed') {
        salesByDate[dateStr]!['revenue'] =
            (salesByDate[dateStr]!['revenue'] as double) + total;
        salesByDate[dateStr]!['orders'] =
            (salesByDate[dateStr]!['orders'] as int) + 1;
      }
    }

    // Convert to list and sort by date
    final dailySales = salesByDate.values.toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    return {'dailySales': dailySales};
  }

  List<Map<String, dynamic>> _computeTopSellingItems(List<dynamic> orders) {
    final itemCounts = <String, int>{};

    for (final order in orders) {
      if (order is! Map) continue;
      final items = order['items'] as List<dynamic>? ?? const [];
      for (final item in items) {
        if (item is! Map) continue;
        final name = (item['name'] ?? 'Unknown').toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        itemCounts[name] = (itemCounts[name] ?? 0) + qty;
      }
    }

    final sorted = itemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .map((e) => {'name': e.key, 'count': e.value})
        .take(10)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabListener = () {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    };
    _tabController.addListener(_tabListener);
    // Initialize year/month slicers to All (show all data)
    _selectedYear = null; // All years
    _selectedMonthNumber = null; // All months
    _loadAvailability();
    _loadAnalyticsData();
  }

  Future<void> _loadAvailability() async {
    try {
      final now = DateTime.now();
      final res = await ApiService.getOrdersByDateRange(
        startDate: DateTime(2000, 1, 1),
        endDate: now,
      );

      final orders = res['data'] as List<dynamic>? ?? const [];
      final yearsSet = <int>{};
      final monthsByYear = <int, Set<int>>{};

      DateTime? parseCreatedAt(dynamic createdAt) {
        if (createdAt is Timestamp) return createdAt.toDate();
        if (createdAt is DateTime) return createdAt;
        if (createdAt is int)
          return DateTime.fromMillisecondsSinceEpoch(createdAt);
        if (createdAt is String) return DateTime.tryParse(createdAt);
        return null;
      }

      for (final order in orders) {
        if (order is! Map) continue;
        final status = (order['status'] ?? '').toString().toLowerCase();
        if (status != 'completed') continue;

        final created = parseCreatedAt(order['createdAt']);
        if (created == null) continue;

        yearsSet.add(created.year);
        (monthsByYear[created.year] ??= <int>{}).add(created.month);
      }

      final years = yearsSet.toList()..sort((a, b) => b.compareTo(a));
      final normalizedMonthsByYear = <int, List<int>>{};
      for (final entry in monthsByYear.entries) {
        final months = entry.value.toList()..sort();
        normalizedMonthsByYear[entry.key] = months;
      }

      if (!mounted) return;
      setState(() {
        _availableYears = years;
        _availableMonthsByYear
          ..clear()
          ..addAll(normalizedMonthsByYear);
      });
    } catch (_) {
      // ignore availability errors; slicers will fall back to current chart data
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_tabListener);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      DateTime startDate;
      DateTime endDate = DateTime.now();
      int days = _rangeDays;

      // Handle Year/Month slicer selections
      if (_selectedYear != null && _selectedMonthNumber != null) {
        // Specific year and month selected
        startDate = DateTime(_selectedYear!, _selectedMonthNumber!, 1);
        endDate = DateTime(
            _selectedYear!, _selectedMonthNumber! + 1, 0, 23, 59, 59, 999);
        days = endDate.difference(startDate).inDays + 1;
      } else if (_selectedYear != null && _selectedMonthNumber == null) {
        // Specific year, all months
        startDate = DateTime(_selectedYear!, 1, 1);
        endDate = DateTime(_selectedYear!, 12, 31, 23, 59, 59, 999);
        days = 365;
      } else if (_selectedYear == null && _selectedMonthNumber != null) {
        // All years, specific month (use current year as fallback)
        final now = DateTime.now();
        startDate = DateTime(now.year, _selectedMonthNumber!, 1);
        endDate =
            DateTime(now.year, _selectedMonthNumber! + 1, 0, 23, 59, 59, 999);
        days = endDate.difference(startDate).inDays + 1;
      } else {
        // All years, all months - get all historical data
        final earliest = _getEarliestDate(endDate);
        startDate = earliest;
        days = endDate.difference(startDate).inDays + 1;
      }

      final ordersForRangeFuture = ApiService.getOrdersByDateRange(
        startDate: startDate,
        endDate: endDate,
      );

      final results = await Future.wait([
        ApiService.getSummaryStats(),
        (_selectedYear != null || _selectedMonthNumber != null)
            ? ApiService.getOrdersByDateRange(
                    startDate: startDate, endDate: endDate)
                .then((r) {
                final salesData = _processOrdersToDailySales(
                    r['data'] as List<dynamic>, days, startDate);
                return {'data': salesData};
              })
            : ApiService.getDailySalesAnalytics(days: days),
        ApiService.getItemPerformance(),
        ApiService.getOrdersForecast(days: _selectedRangeDays),
        ApiService.getSalesForecast(days: _selectedRangeDays),
        ApiService.getRecommendations(),
        ApiService.getExpenses(),
        ApiService.getPayables(),
        ordersForRangeFuture,
      ]);

      if (mounted) {
        final ordersForRange =
            (results[8]['data'] as List<dynamic>? ?? const []);
        setState(() {
          _summaryStats = results[0]['data'];
          _dailySales = List<Map<String, dynamic>>.from(
              results[1]['data']['dailySales'] ?? []);
          _itemPerformance =
              List<Map<String, dynamic>>.from(results[2]['data']['items'] ?? [])
                ..sort((a, b) {
                  final ar = a['revenue'];
                  final br = b['revenue'];
                  final av = (ar is num) ? ar.toDouble() : 0.0;
                  final bv = (br is num) ? br.toDouble() : 0.0;
                  return bv.compareTo(av);
                });
          _topSellingItems = _computeTopSellingItems(ordersForRange);
          _ordersForecast =
              List<Map<String, dynamic>>.from(results[3]['data'] ?? []);
          _salesForecast =
              List<Map<String, dynamic>>.from(results[4]['data'] ?? []);
          _recommendations = results[5]['data'];
          _expenses = List<Map<String, dynamic>>.from(results[6]['data'] ?? []);
          _payables = List<Map<String, dynamic>>.from(results[7]['data'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final message = _looksLikeNetworkIssue(e)
            ? 'Network issue. Check your internet / DNS (Private DNS), then try again.'
            : 'Error loading analytics: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              centerTitle: true,
              leading: widget.onOpenDrawer != null
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                      onPressed: widget.onOpenDrawer,
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
              title: const Text('Analytics Dashboard'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadAnalyticsData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SizedBox(
                        height: 40,
                        child: TabBar(
                          controller: _tabController,
                          labelColor: Theme.of(context).colorScheme.primary,
                          unselectedLabelColor: Colors.grey.shade700,
                          indicatorColor: Theme.of(context).colorScheme.primary,
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          indicatorSize: TabBarIndicatorSize.tab,
                          tabs: const [
                            Tab(text: 'Sales'),
                            Tab(text: 'Insights'),
                            Tab(text: 'Forecast'),
                            Tab(text: 'Finance'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 800;

                        if (isWide) {
                          // Wide layout: Year/Month slicers + KPIs in one row
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Year/Month slicers
                              _buildYearMonthSlicers(),
                              const SizedBox(width: 10),
                              // KPI button
                              OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _showKpis = !_showKpis),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  minimumSize: const Size(0, 34),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  _showKpis
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                ),
                                label: const Text('KPIs'),
                              ),
                              const SizedBox(width: 10),
                              // KPI cards (compact inline version)
                              if (_showKpis)
                                Expanded(
                                  child: _buildCompactKpiRow(),
                                ),
                            ],
                          );
                        } else {
                          // Narrow layout: stacked vertically with smaller cards
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _buildYearMonthSlicers(),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        setState(() => _showKpis = !_showKpis),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      minimumSize: const Size(0, 34),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: Icon(
                                      _showKpis
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 18,
                                    ),
                                    label: const Text('KPIs'),
                                  ),
                                ],
                              ),
                              if (_showKpis) ...[
                                const SizedBox(height: 8),
                                _buildCompactKpiRow(),
                              ],
                            ],
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSalesTab(),
                        _buildItemsInsightsTab(),
                        _buildForecastTab(),
                        _buildFinanceTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildItemsInsightsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildItemsContent(),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildRecommendationsContent(),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCompactKpiRow() {
    if (_summaryStats == null) return const SizedBox.shrink();

    final today = _summaryStats!['today'] ?? {};
    final week = _summaryStats!['week'] ?? {};
    final month = _summaryStats!['month'] ?? {};
    final menuItems = _summaryStats!['menuItems'] ?? 0;

    // Calculate finance KPIs
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);

    final currentMonthExpenses = _expenses.where((e) {
      final dateStr = e['date']?.toString() ?? e['createdAt']?.toString();
      if (dateStr == null) return false;
      final date = DateTime.tryParse(dateStr);
      if (date == null) return false;
      return date.year == currentMonthStart.year &&
          date.month == currentMonthStart.month;
    }).toList();

    final totalExpenses = currentMonthExpenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );

    final duePayables = _payables.where((p) {
      final status = (p['status'] ?? 'unpaid').toString().toLowerCase();
      return status != 'paid';
    }).toList();

    final totalPayables = duePayables.fold<double>(
      0,
      (sum, p) =>
          sum + ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final kpiItems = [
          _CompactKpiItem(
            title: 'Today',
            value:
                _currency.format((today['revenue'] as num?)?.toDouble() ?? 0.0),
            subtitle: '${today['orders'] ?? 0} orders',
            icon: Icons.today,
            color: Colors.blue,
            isNarrow: isNarrow,
          ),
          _CompactKpiItem(
            title: 'Week',
            value:
                _currency.format((week['revenue'] as num?)?.toDouble() ?? 0.0),
            subtitle: '${week['orders'] ?? 0} orders',
            icon: Icons.date_range,
            color: Colors.green,
            isNarrow: isNarrow,
          ),
          _CompactKpiItem(
            title: 'Month',
            value:
                _currency.format((month['revenue'] as num?)?.toDouble() ?? 0.0),
            subtitle: '${month['orders'] ?? 0} orders',
            icon: Icons.calendar_month,
            color: Colors.orange,
            isNarrow: isNarrow,
          ),
          _CompactKpiItem(
            title: 'Menu',
            value: menuItems.toString(),
            subtitle: 'items',
            icon: Icons.restaurant_menu,
            color: const Color(0xFF00B0FF),
            isNarrow: isNarrow,
          ),
          _CompactKpiItem(
            title: 'Expenses',
            value: _currency.format(totalExpenses),
            subtitle: '${currentMonthExpenses.length} trans.',
            icon: Icons.account_balance_wallet,
            color: Colors.red.shade400,
            isNarrow: isNarrow,
          ),
          _CompactKpiItem(
            title: 'Payables',
            value: _currency.format(totalPayables),
            subtitle: '${duePayables.length} pending',
            icon: Icons.payment,
            color: Colors.orange.shade400,
            isNarrow: isNarrow,
          ),
        ];

        if (isNarrow) {
          // Wrap to 2 rows of 3 cards each on narrow screens
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: kpiItems[0]),
                  const SizedBox(width: 6),
                  Expanded(child: kpiItems[1]),
                  const SizedBox(width: 6),
                  Expanded(child: kpiItems[2]),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: kpiItems[3]),
                  const SizedBox(width: 6),
                  Expanded(child: kpiItems[4]),
                  const SizedBox(width: 6),
                  Expanded(child: kpiItems[5]),
                ],
              ),
            ],
          );
        }

        // Horizontal scroll for wider screens with all 6 KPIs
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < kpiItems.length; i++) ...[
                kpiItems[i],
                if (i < kpiItems.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    final now = DateTime.now();
    final hasCustom = _customRange != null;
    final isForecastTab = _tabController.index == 2;

    // Calculate date ranges for tooltips (only for non-forecast tabs)
    String getRangeTooltip(int days) {
      final start = now.subtract(Duration(days: days - 1));
      return '${DateFormat('M/d').format(start)} - ${DateFormat('M/d').format(now)}';
    }

    final currentMonthStart = DateTime(now.year, now.month, 1);
    final currentMonthTooltip =
        '${DateFormat('M/d').format(currentMonthStart)} - ${DateFormat('M/d').format(now)}';

    String displayValue;
    if (isForecastTab) {
      // Forecast tab shows "Next X days"
      displayValue = 'Next $_selectedRangeDays days';
    } else if (hasCustom) {
      displayValue =
          '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d').format(_customRange!.end)}';
    } else if (_rangeDays == -2) {
      displayValue = 'This Month';
    } else if (_rangeDays == -4) {
      displayValue = _selectedMonthYear ?? 'Pick Month';
    } else {
      displayValue = 'Last $_rangeDays days';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Material(
        color: Colors.transparent,
        child: PopupMenuButton<int>(
          key: ValueKey('range_selector_${_tabController.index}'),
          initialValue: isForecastTab
              ? _selectedRangeDays
              : (hasCustom ? -1 : _rangeDays),
          onSelected: (v) async {
            // Handle Forecast tab (Next X days)
            if (isForecastTab) {
              setState(() {
                _selectedRangeDays = v;
              });
              await _loadAnalyticsData();
              return;
            }

            // Handle other tabs (Last X days, Month, Custom)
            if (v == -1) {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: now,
                initialDateRange: _customRange ??
                    DateTimeRange(
                      start: now.subtract(const Duration(days: 7)),
                      end: now,
                    ),
              );
              if (picked == null) return;
              final days = picked.end.difference(picked.start).inDays + 1;
              setState(() {
                _customRange = picked;
                _rangeDays = days <= 0 ? 7 : days;
                _selectedMonth = null;
                _selectedMonthYear = null;
              });
              await _loadAnalyticsData();
              return;
            }

            if (v == -4) {
              // Show month/year picker
              final selected = await _showMonthYearPicker(context);
              if (selected == null) return;
              setState(() {
                _selectedMonth = selected;
                _selectedMonthYear = DateFormat('MMM yyyy').format(selected);
                _rangeDays = -4;
                _customRange = null;
              });
              await _loadAnalyticsData();
              return;
            }

            setState(() {
              _customRange = null;
              _selectedMonth = null;
              _selectedMonthYear = null;
              _rangeDays = v;
            });
            await _loadAnalyticsData();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForecastTab ? Icons.arrow_forward : Icons.calendar_today,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_drop_down,
                    size: 18, color: Colors.grey.shade600),
              ],
            ),
          ),
          itemBuilder: (context) => isForecastTab
              ? [
                  // Forecast tab: Next X days options only
                  _buildMenuItem(
                    value: 7,
                    label: 'Next 7 days',
                    tooltip: 'Show forecast for next 7 days',
                    icon: Icons.view_week,
                    isForecastTab: true,
                  ),
                  _buildMenuItem(
                    value: 14,
                    label: 'Next 2 weeks',
                    tooltip: 'Show forecast for next 14 days',
                    icon: Icons.calendar_view_week,
                    isForecastTab: true,
                  ),
                  _buildMenuItem(
                    value: 21,
                    label: 'Next 3 weeks',
                    tooltip: 'Show forecast for next 21 days',
                    icon: Icons.date_range,
                    isForecastTab: true,
                  ),
                  _buildMenuItem(
                    value: 30,
                    label: 'Next 30 days',
                    tooltip: 'Show forecast for next 30 days',
                    icon: Icons.calendar_view_month,
                    isForecastTab: true,
                  ),
                  _buildMenuItem(
                    value: 90,
                    label: 'Next 90 days',
                    tooltip: 'Show forecast for next 90 days',
                    icon: Icons.date_range,
                    isForecastTab: true,
                  ),
                ]
              : [
                  // Other tabs: Last X days, Month, Custom
                  _buildMenuItem(
                    value: 7,
                    label: 'Last 7 days',
                    tooltip: getRangeTooltip(7),
                    icon: Icons.view_week,
                  ),
                  _buildMenuItem(
                    value: 30,
                    label: 'Last 30 days',
                    tooltip: getRangeTooltip(30),
                    icon: Icons.calendar_view_month,
                  ),
                  _buildMenuItem(
                    value: 90,
                    label: 'Last 90 days',
                    tooltip: getRangeTooltip(90),
                    icon: Icons.date_range,
                  ),
                  const PopupMenuDivider(),
                  _buildMenuItem(
                    value: -2,
                    label: 'This Month',
                    tooltip: currentMonthTooltip,
                    icon: Icons.calendar_month,
                  ),
                  _buildMenuItem(
                    value: -4,
                    label: 'Pick Month/Year',
                    tooltip: 'Select any month and year',
                    icon: Icons.calendar_month_outlined,
                  ),
                  const PopupMenuDivider(),
                  _buildMenuItem(
                    value: -1,
                    label: 'Custom Range',
                    tooltip: 'Pick your own date range',
                    icon: Icons.edit_calendar,
                  ),
                ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _buildMenuItem({
    required int value,
    required String label,
    required String tooltip,
    required IconData icon,
    bool isForecastTab = false,
  }) {
    final isSelected = isForecastTab
        ? (_selectedRangeDays == value)
        : ((_rangeDays == value && value != -1) ||
            (value == -1 && _customRange != null));

    return PopupMenuItem<int>(
      value: value,
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade800,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _showMonthYearPicker(BuildContext context) async {
    final now = DateTime.now();
    final earliestDate = _getEarliestDate(now);
    int selectedMonth = now.month;
    int selectedYear = now.year;
    final availableYears = _generateYears(earliestDate.year, now.year);

    return showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableMonths =
              _getAvailableMonths(selectedYear, earliestDate, now);
          selectedMonth = availableMonths.contains(selectedMonth)
              ? selectedMonth
              : availableMonths.first;

          return AlertDialog(
            title: const Text('Select Month & Year'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDropdownRow('Year:', selectedYear, availableYears,
                      (v) => setDialogState(() => selectedYear = v)),
                  const SizedBox(height: 16),
                  _buildDropdownRow('Month:', selectedMonth, availableMonths,
                      (v) => setDialogState(() => selectedMonth = v),
                      labelBuilder: (m) =>
                          DateFormat('MMMM').format(DateTime(2024, m, 1))),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                    context, DateTime(selectedYear, selectedMonth, 1)),
                child: const Text('Select'),
              ),
            ],
          );
        },
      ),
    );
  }

  DateTime _getEarliestDate(DateTime fallback) {
    if (_dailySales.isEmpty)
      return fallback.subtract(const Duration(days: 365));
    try {
      final dates = _dailySales
          .map((s) => DateTime.tryParse(s['date']?.toString() ?? ''))
          .where((d) => d != null)
          .cast<DateTime>()
          .toList();
      return dates.isEmpty
          ? fallback
          : dates.reduce((a, b) => a.isBefore(b) ? a : b);
    } catch (_) {
      return fallback.subtract(const Duration(days: 365));
    }
  }

  List<int> _generateYears(int start, int end) =>
      List.generate(end - start + 1, (i) => start + i).reversed.toList();

  List<int> _getAvailableMonths(int year, DateTime earliest, DateTime now) =>
      List.generate(12, (i) => i + 1).where((m) {
        if (year == earliest.year && m < earliest.month) return false;
        if (year == now.year && m > now.month) return false;
        return true;
      }).toList();

  Widget _buildDropdownRow<T>(
          String label, T value, List<T> items, ValueChanged<T> onChanged,
          {String Function(T)? labelBuilder}) =>
      Row(
        children: [
          SizedBox(
              width: 50,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: items
                  .map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(labelBuilder?.call(i) ?? i.toString()),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      );

  // Get available years from order data
  List<int> _getAvailableYears() {
    if (_dailySales.isEmpty) {
      final now = DateTime.now();
      return [now.year];
    }
    final years = _dailySales
        .map((s) {
          final dateStr = s['date']?.toString() ?? '';
          final date = DateTime.tryParse(dateStr);
          return date?.year;
        })
        .where((y) => y != null)
        .cast<int>()
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a)); // Descending
    return years.isEmpty ? [DateTime.now().year] : years;
  }

  List<int> _getAvailableYearsFromData() {
    if (_availableYears.isNotEmpty) return _availableYears;
    if (_dailySales.isEmpty) return [DateTime.now().year];
    final years = _dailySales
        .map((s) => DateTime.tryParse(s['date']?.toString() ?? '')?.year)
        .where((y) => y != null)
        .cast<int>()
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a));
    return years.isEmpty ? [DateTime.now().year] : years;
  }

  List<int> _getAvailableMonthsForYear(int year) {
    final months = _availableMonthsByYear[year];
    if (months != null && months.isNotEmpty) return months;

    // fallback to current chart data (better than showing all 12 months)
    final fallback = _dailySales
        .map((s) => DateTime.tryParse(s['date']?.toString() ?? ''))
        .where((d) => d != null && d!.year == year)
        .map((d) => d!.month)
        .toSet()
        .toList()
      ..sort();
    return fallback;
  }

  List<int> _getAvailableMonthsForAllYears() {
    if (_availableMonthsByYear.isNotEmpty) {
      final set = <int>{};
      for (final months in _availableMonthsByYear.values) {
        set.addAll(months);
      }
      final all = set.toList()..sort();
      return all;
    }

    final fallback = _dailySales
        .map((s) => DateTime.tryParse(s['date']?.toString() ?? ''))
        .where((d) => d != null)
        .map((d) => d!.month)
        .toSet()
        .toList()
      ..sort();
    return fallback;
  }

  // Build Year/Month slicers
  Widget _buildYearMonthSlicers() {
    final availableYears = _getAvailableYearsFromData();
    final availableMonths = _selectedYear != null
        ? _getAvailableMonthsForYear(_selectedYear!)
        : _getAvailableMonthsForAllYears();

    // Validate and fix selected year if needed (silently)
    if (_selectedYear != null && !availableYears.contains(_selectedYear)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedYear = availableYears.first);
        }
      });
    }
    // Note: We don't reset _selectedMonthNumber here to preserve user selection
    // The dropdown will show the selected value even if not in current data

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Year slicer
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Year',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _selectedYear,
                  isDense: true,
                  icon: Icon(Icons.arrow_drop_down,
                      size: 18, color: Colors.grey.shade600),
                  items: [
                    // All option
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All'),
                    ),
                    ...availableYears.map((year) => DropdownMenuItem<int?>(
                          value: year,
                          child: Text(year.toString()),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedYear = value;
                      // Reset month when year changes to All
                      if (value == null) {
                        _selectedMonthNumber = null;
                      }
                    });
                    _loadAnalyticsData();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Month slicer
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Month',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _selectedMonthNumber,
                  isDense: true,
                  icon: Icon(Icons.arrow_drop_down,
                      size: 18, color: Colors.grey.shade600),
                  items: [
                    // All option
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All'),
                    ),
                    ...availableMonths.map((month) => DropdownMenuItem<int?>(
                          value: month,
                          child: Text(DateFormat('MMMM')
                              .format(DateTime(2024, month, 1))),
                        )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedMonthNumber = value;
                    });
                    _loadAnalyticsData();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Reset button
        if (_selectedYear != null || _selectedMonthNumber != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: 'Clear filters',
            onPressed: () {
              setState(() {
                _selectedYear = null;
                _selectedMonthNumber = null;
              });
              _loadAnalyticsData();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    if (_summaryStats == null) return const SizedBox();

    final today = _summaryStats!['today'] ?? {};
    final week = _summaryStats!['week'] ?? {};
    final month = _summaryStats!['month'] ?? {};

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;
          final cards = <Widget>[
            _SummaryCard(
              title: 'Today',
              revenue: today['revenue']?.toDouble() ?? 0.0,
              orders: today['orders'] ?? 0,
              color: Colors.blue,
            ),
            _SummaryCard(
              title: 'This Week',
              revenue: week['revenue']?.toDouble() ?? 0.0,
              orders: week['orders'] ?? 0,
              color: Colors.green,
            ),
            _SummaryCard(
              title: 'This Month',
              revenue: month['revenue']?.toDouble() ?? 0.0,
              orders: month['orders'] ?? 0,
              color: Colors.orange,
            ),
            _InfoCard(
              title: 'Menu Items',
              value: '${_summaryStats!['menuItems'] ?? 0}',
              icon: Icons.restaurant_menu,
              color: const Color(0xFF00B0FF),
            ),
          ];

          if (isNarrow) {
            return Column(
              children: [
                for (final c in cards) ...[
                  c,
                  const SizedBox(height: 12),
                ]
              ],
            );
          }

          return GridView.count(
            crossAxisCount: constraints.maxWidth >= 980 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth >= 980 ? 1.45 : 1.7,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _buildSalesTab() {
    // Build title based on Year/Month slicers
    String rangeTitle;
    if (_selectedYear != null && _selectedMonthNumber != null) {
      // Specific year and month
      rangeTitle =
          '${DateFormat('MMMM').format(DateTime(2024, _selectedMonthNumber!, 1))} ${_selectedYear}';
    } else if (_selectedYear != null && _selectedMonthNumber == null) {
      // Specific year, all months
      rangeTitle = 'Year ${_selectedYear}';
    } else if (_selectedYear == null && _selectedMonthNumber != null) {
      // All years, specific month
      rangeTitle =
          '${DateFormat('MMMM').format(DateTime(2024, _selectedMonthNumber!, 1))} (All Years)';
    } else {
      // All years, all months
      rangeTitle = 'All Time';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Sales ($rangeTitle)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 520,
            child: _dailySales.isEmpty
                ? const Center(child: Text('No sales data available'))
                : _buildSalesChart(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sales Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._dailySales.reversed
              .map((sale) => _SalesItemTile(sale: sale))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildItemsContent() {
    final hasAnyData =
        _topSellingItems.isNotEmpty || _itemPerformance.isNotEmpty;
    final totalItems = _itemPerformance.length;
    final totalRevenue = _itemPerformance.fold<double>(0, (sum, item) {
      final rev = item['revenue'];
      return sum + ((rev is num) ? rev.toDouble() : 0.0);
    });
    final totalUnitsSold = _topSellingItems.fold<int>(0, (sum, item) {
      final raw = item['count'];
      return sum + ((raw is num) ? raw.toInt() : 0);
    });
    final topSellingItem =
        _topSellingItems.isNotEmpty ? _topSellingItems.first : null;
    final topName = (topSellingItem?['name'] ?? 'Unknown').toString();
    final topCountRaw = topSellingItem?['count'];
    final topCount = (topCountRaw is num) ? topCountRaw.toInt() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.restaurant_menu,
                  color: Colors.green.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Performing Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Top selling items by quantity in the selected range',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (hasAnyData)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: _ItemSummaryCard(
                    title: 'Total Revenue',
                    value: _currency.format(totalRevenue),
                    subtitle: '$totalItems items',
                    icon: Icons.payments,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ItemSummaryCard(
                    title: 'Units Sold',
                    value: '$totalUnitsSold',
                    subtitle: 'Total quantity',
                    icon: Icons.shopping_cart,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (!hasAnyData)
          Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.restaurant_menu,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  'No item performance data available',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Complete some orders to see top performing items',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              if (topSellingItem != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.amber.shade50,
                        Colors.orange.shade50,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.emoji_events,
                            color: Colors.amber.shade700, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Top Performer',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade700,
                              ),
                            ),
                            Text(
                              topName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$topCount sold',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Rank',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Item',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600),
                      ),
                    ),
                    Text(
                      'Sold',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              ..._topSellingItems.asMap().entries.take(10).map((entry) {
                final index = entry.key;
                final item = entry.value;
                final name = (item['name'] ?? '').toString();
                final countRaw = item['count'];
                final count = (countRaw is num) ? countRaw.toInt() : 0;

                final rankColors = [
                  Colors.amber.shade400,
                  Colors.grey.shade400,
                  Colors.orange.shade300,
                  Colors.blue.shade300,
                  Colors.green.shade300,
                ];
                final rankColor = rankColors[
                    index < rankColors.length ? index : rankColors.length - 1];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: rankColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: rankColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count sold',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
      ],
    );
  }

  Widget _buildForecastTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Orders & Sales Forecast',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Side-by-side forecast cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Orders Forecast Card
              Expanded(
                child: _buildForecastGridCard(
                  title: 'Predicted Orders',
                  subtitle: 'Next $_selectedRangeDays days',
                  icon: Icons.trending_up,
                  iconColor: Colors.orange,
                  data: _ordersForecast,
                  valueKey: 'predictedOrders',
                  unit: 'orders',
                ),
              ),
              const SizedBox(width: 16),
              // Sales Forecast Card
              Expanded(
                child: _buildForecastGridCard(
                  title: 'Predicted Sales',
                  subtitle: 'Next $_selectedRangeDays days revenue',
                  icon: Icons.attach_money,
                  iconColor: const Color(0xFF00B0FF),
                  data: _salesForecast,
                  valueKey: 'predictedRevenue',
                  unit: '₱',
                  isCurrency: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForecastGridCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<Map<String, dynamic>> data,
    required String valueKey,
    required String unit,
    bool isCurrency = false,
  }) {
    if (data.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'No data available',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final points = data.take(_selectedRangeDays).toList();
    final now = DateTime.now();

    // Calculate max for scaling
    final maxValue = points.isEmpty
        ? 0.0
        : points.map((p) {
            final raw = p[valueKey];
            return (raw is num) ? raw.toDouble() : 0.0;
          }).reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Grid Layout - 7 days per row
            ..._buildForecastRows(
                points, maxValue, valueKey, iconColor, isCurrency),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildForecastRows(
    List<Map<String, dynamic>> points,
    double maxValue,
    String valueKey,
    Color color,
    bool isCurrency,
  ) {
    final rows = <Widget>[];
    final now = DateTime.now();

    // Split into chunks of 7 days
    for (int i = 0; i < points.length; i += 7) {
      final end = (i + 7 < points.length) ? i + 7 : points.length;
      final rowPoints = points.sublist(i, end);

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // Day cells - each takes equal space
              ...rowPoints.asMap().entries.map((entry) {
                final index = i + entry.key;
                final forecast = entry.value;
                final valueRaw = forecast[valueKey];
                final value = (valueRaw is num) ? valueRaw.toDouble() : 0.0;
                final scaleFactor = maxValue > 0 ? value / maxValue : 0.0;
                final date = now.add(Duration(days: index + 1));
                final dayName = DateFormat('EEE').format(date);
                final dayNum = DateFormat('d').format(date);
                final isWeekend = date.weekday == 6 || date.weekday == 7;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        // Value bar
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: isWeekend
                                ? color.withOpacity(0.15)
                                : color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor:
                                  (scaleFactor * 0.85 + 0.05).clamp(0.05, 1.0),
                              widthFactor: 0.7,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      color.withOpacity(0.7),
                                      color,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Day name
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isWeekend ? color : Colors.grey.shade700,
                          ),
                        ),
                        // Day number
                        Text(
                          dayNum,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        // Value
                        Text(
                          isCurrency
                              ? '₱${NumberFormat.compact().format(value)}'
                              : value.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              // Fill remaining space in last row to keep day widths consistent
              if (rowPoints.length < 7)
                Expanded(
                  flex: 7 - rowPoints.length,
                  child: const SizedBox(),
                ),
            ],
          ),
        ),
      );
    }

    return rows;
  }

  Widget _buildRecommendationsContent() {
    if (_recommendations == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No recommendations available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for AI-powered insights',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    final promoteItems = _recommendations!['promoteItems'] ?? [];
    final removeItems = _recommendations!['removeItems'] ?? [];
    final optimizeInventory = _recommendations!['optimizeInventory'] ?? [];
    final totalRecommendations =
        promoteItems.length + removeItems.length + optimizeInventory.length;

    if (totalRecommendations == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Colors.green.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No recommendations at this time',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Recommendations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalRecommendations actionable insights based on your data',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (promoteItems.isNotEmpty) ...[
          _buildRecommendationSectionHeader(
            icon: Icons.trending_up,
            title: 'Items to Promote',
            subtitle: '${promoteItems.length} items with promotion potential',
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          ...promoteItems
              .map((item) => _RecommendationTile(
                    title: item['name'],
                    subtitle: item['reason'],
                    action: '${item['expectedIncrease']}',
                    color: Colors.green,
                    icon: Icons.campaign,
                    actionLabel: 'Expected increase',
                  ))
              .toList(),
          const SizedBox(height: 24),
        ],
        if (removeItems.isNotEmpty) ...[
          _buildRecommendationSectionHeader(
            icon: Icons.delete_outline,
            title: 'Items to Remove',
            subtitle: '${removeItems.length} underperforming items',
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          ...removeItems
              .map((item) => _RecommendationTile(
                    title: item['name'],
                    subtitle: item['reason'],
                    action: '${item['wasteReduction']}',
                    color: Colors.red,
                    icon: Icons.remove_circle_outline,
                    actionLabel: 'Waste reduction',
                  ))
              .toList(),
          const SizedBox(height: 24),
        ],
        if (optimizeInventory.isNotEmpty) ...[
          _buildRecommendationSectionHeader(
            icon: Icons.inventory_2_outlined,
            title: 'Inventory Optimization',
            subtitle: '${optimizeInventory.length} items need attention',
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          ...optimizeInventory
              .map((item) => _RecommendationTile(
                    title: item['ingredient'],
                    subtitle: item['reason'],
                    action: item['action'],
                    color: Colors.orange,
                    icon: Icons.warning_amber_outlined,
                    actionLabel: 'Action needed',
                  ))
              .toList(),
        ],
      ],
    );
  }

  Widget _buildRecommendationSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalesChart() {
    // Helper to parse dates in various formats
    DateTime? parseDate(dynamic dateValue) {
      if (dateValue == null) return null;
      if (dateValue is DateTime) return dateValue;
      final str = dateValue.toString();
      // Try standard ISO format first
      final iso = DateTime.tryParse(str);
      if (iso != null) return iso;
      // Try format like "2026-4-22" (no leading zeros)
      final parts = str.split('-');
      if (parts.length == 3) {
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (year != null && month != null && day != null) {
          return DateTime(year, month, day);
        }
      }
      return null;
    }

    // Sort data by date - earliest first (left to right)
    final sortedSales = List<Map<String, dynamic>>.from(_dailySales)
      ..sort((a, b) {
        final dateA = parseDate(a['date']) ?? DateTime(2000);
        final dateB = parseDate(b['date']) ?? DateTime(2000);
        return dateA.compareTo(dateB);
      });

    if (sortedSales.isEmpty) {
      return const Center(child: Text('No sales data available'));
    }

    // Get date range from actual data
    final firstDate = parseDate(sortedSales.first['date']) ?? DateTime.now();
    final lastDate = parseDate(sortedSales.last['date']) ?? DateTime.now();
    final totalDays = lastDate.difference(firstDate).inDays + 1;

    // Determine number of labels to show based on range
    final int labelCount = totalDays <= 7 ? totalDays : 10;
    final int intervalDays =
        labelCount <= 1 ? 1 : ((totalDays - 1) / (labelCount - 1)).ceil();

    // Build chronological date labels at equal intervals
    final dateLabels = <double, String>{};
    for (var i = 0; i < labelCount; i++) {
      final dayOffset = (i * intervalDays).clamp(0, totalDays - 1);
      final labelDate = firstDate.add(Duration(days: dayOffset));
      dateLabels[dayOffset.toDouble()] =
          '${labelDate.month.toString().padLeft(2, '0')}/${labelDate.day.toString().padLeft(2, '0')}';
    }

    // Create data points with x = days from start
    final points = <FlSpot>[];
    final orderBars = <BarChartGroupData>[];

    for (var i = 0; i < sortedSales.length; i++) {
      final d = sortedSales[i];
      final date = parseDate(d['date']);
      if (date == null) continue;

      final daysFromStart = date.difference(firstDate).inDays.toDouble();
      final revenue = (d['revenue'] as num?)?.toDouble() ?? 0.0;
      final orders = (d['orders'] as num?)?.toDouble() ?? 0.0;

      points.add(FlSpot(daysFromStart, revenue));
      orderBars.add(
        BarChartGroupData(
          x: daysFromStart.toInt(),
          barRods: [
            BarChartRodData(
              toY: orders,
              width: 6,
              borderRadius: BorderRadius.circular(3),
              color: Colors.indigo,
            ),
          ],
        ),
      );
    }

    final maxRevenue = points.isEmpty
        ? 0.0
        : points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final maxOrders = orderBars.isEmpty
        ? 0.0
        : orderBars
            .map((g) => g.barRods.first.toY)
            .reduce((a, b) => a > b ? a : b);

    String labelAt(double value) {
      // Find the closest label
      final closest = dateLabels.entries.reduce(
          (a, b) => (a.key - value).abs() < (b.key - value).abs() ? a : b);
      // Only show if within half interval distance
      if ((closest.key - value).abs() > intervalDays / 2) return '';
      return closest.value;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Revenue',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'Max: ${_currency.format(maxRevenue)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (totalDays - 1).toDouble(),
                minY: 0,
                maxY: maxRevenue <= 0 ? 1 : maxRevenue * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: intervalDays.toDouble(),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (maxRevenue > 0)
                      HorizontalLine(
                        y: maxRevenue,
                        color: Colors.green.shade400,
                        strokeWidth: 2,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          labelResolver: (line) =>
                              'Peak: ${_currency.format(line.y)}',
                        ),
                      ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipBorder: BorderSide(color: Colors.grey.shade300),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final date =
                            firstDate.add(Duration(days: spot.x.toInt()));
                        final dateStr =
                            '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
                        return LineTooltipItem(
                          '$dateStr\n₱${spot.y.toStringAsFixed(0)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: false,
                    spots: points,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: Colors.green,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    color: Colors.green,
                    barWidth: 2,
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withValues(alpha: 0.1),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: maxRevenue > 0 ? maxRevenue / 4 : null,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            value >= 1000
                                ? '₱${(value / 1000).toStringAsFixed(0)}k'
                                : '₱${value.toInt()}',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: intervalDays.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final label = labelAt(value);
                        if (label.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Orders',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      'Max: ${maxOrders.toInt()}',
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxOrders <= 0 ? 1 : maxOrders * 1.2,
                      barGroups: orderBars,
                      barTouchData: BarTouchData(
                        enabled: true,
                        handleBuiltInTouches: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipRoundedRadius: 8,
                          tooltipPadding: const EdgeInsets.all(8),
                          tooltipBorder:
                              BorderSide(color: Colors.grey.shade300),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final date = firstDate.add(Duration(days: group.x));
                            final dateStr =
                                '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
                            return BarTooltipItem(
                              '$dateStr\n${rod.toY.toInt()} orders',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.shade200,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: maxOrders > 0 ? maxOrders / 4 : null,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  '${value.toInt()}',
                                  style: TextStyle(
                                      fontSize: 9, color: Colors.grey.shade600),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final day = value.toInt();
                              if (day < 0 || day >= totalDays) {
                                return const SizedBox.shrink();
                              }

                              // Show full label only every 5 days to avoid overlap.
                              // For other days, show a small dot marker.
                              final showLabel = day % 5 == 0;
                              final label =
                                  '${firstDate.add(Duration(days: day)).month.toString().padLeft(2, '0')}/${firstDate.add(Duration(days: day)).day.toString().padLeft(2, '0')}';
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  showLabel ? label : '.',
                                  style: TextStyle(
                                    fontSize: showLabel ? 9 : 10,
                                    color: showLabel
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastChart() {
    final points = _ordersForecast.take(_selectedRangeDays).toList();
    final now = DateTime.now();

    // Calculate actual dates for each forecast point
    List<DateTime> getForecastDates() {
      return List.generate(
          points.length, (index) => now.add(Duration(days: index)));
    }

    final dates = getForecastDates();

    // Calculate max for scaling
    final maxOrders = points.isEmpty
        ? 0.0
        : points.map((p) {
            final raw = p['predictedOrders'];
            return (raw is num) ? raw.toDouble() : 0.0;
          }).reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.trending_up,
                      color: Colors.orange.shade700, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Predicted Orders',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Next $_selectedRangeDays days forecast',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (maxOrders > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Peak: ${maxOrders.toStringAsFixed(0)} orders',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _ordersForecast.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.insights,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No forecast data available',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: points.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final forecast = points[index];
                        final ordersRaw = forecast['predictedOrders'];
                        final orders =
                            (ordersRaw is num) ? ordersRaw.toDouble() : 0.0;
                        final scaleFactor =
                            maxOrders > 0 ? orders / maxOrders : 0.0;
                        final date = dates[index];
                        final dayName = DateFormat('EEE').format(date);
                        final dayNum = DateFormat('d').format(date);
                        final isWeekend =
                            date.weekday == 6 || date.weekday == 7;

                        return SizedBox(
                          width: 56,
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isWeekend
                                        ? Colors.orange.shade100
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: (scaleFactor * 0.85 + 0.05)
                                          .clamp(0.05, 1.0),
                                      widthFactor: 0.7,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.orange.shade400,
                                              Colors.orange.shade700,
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                dayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isWeekend
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                dayNum,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              Text(
                                orders.toStringAsFixed(0),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesForecastChart() {
    final points = _salesForecast.take(_selectedRangeDays).toList();
    final now = DateTime.now();

    // Calculate actual dates for each forecast point
    List<DateTime> getForecastDates() {
      return List.generate(
          points.length, (index) => now.add(Duration(days: index)));
    }

    final dates = getForecastDates();

    // Calculate max for scaling
    final maxSales = points.isEmpty
        ? 0.0
        : points.map((p) {
            final raw = p['predictedRevenue'] ?? p['predictedSales'];
            return (raw is num) ? raw.toDouble() : 0.0;
          }).reduce((a, b) => a > b ? a : b);

    // Calculate total forecast
    final totalForecast = points.fold<double>(0, (sum, p) {
      final raw = p['predictedRevenue'] ?? p['predictedSales'];
      return sum + ((raw is num) ? raw.toDouble() : 0.0);
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B0FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.attach_money,
                      color: Color(0xFF00B0FF), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Predicted Sales',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Next $_selectedRangeDays days revenue forecast',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (totalForecast > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B0FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Total: ₱${NumberFormat.compact().format(totalForecast)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00B0FF),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _salesForecast.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bar_chart,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No sales forecast data available',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: points.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final forecast = points[index];
                        final salesRaw = forecast['predictedRevenue'] ??
                            forecast['predictedSales'];
                        final sales =
                            (salesRaw is num) ? salesRaw.toDouble() : 0.0;
                        final scaleFactor =
                            maxSales > 0 ? sales / maxSales : 0.0;
                        final date = dates[index];
                        final dayName = DateFormat('EEE').format(date);
                        final dayNum = DateFormat('d').format(date);
                        final isWeekend =
                            date.weekday == 6 || date.weekday == 7;

                        return SizedBox(
                          width: 60,
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isWeekend
                                        ? const Color(0xFF00B0FF)
                                            .withOpacity(0.15)
                                        : const Color(0xFF00B0FF)
                                            .withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: (scaleFactor * 0.85 + 0.05)
                                          .clamp(0.05, 1.0),
                                      widthFactor: 0.7,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFF4FC3F7),
                                              Color(0xFF00B0FF),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                dayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isWeekend
                                      ? const Color(0xFF00B0FF)
                                      : Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                dayNum,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              Text(
                                '₱${NumberFormat.compact().format(sales)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF00B0FF),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceTab() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final prevMonth = DateTime(now.year, now.month - 1, 1);

    // Calculate current month expenses
    final currentMonthExpenses = _expenses.where((e) {
      final dateStr = e['date']?.toString() ?? e['createdAt']?.toString();
      if (dateStr == null) return false;
      final date = DateTime.tryParse(dateStr);
      if (date == null) return false;
      return date.year == currentMonth.year && date.month == currentMonth.month;
    }).toList();

    // Calculate previous month expenses
    final prevMonthExpenses = _expenses.where((e) {
      final dateStr = e['date']?.toString() ?? e['createdAt']?.toString();
      if (dateStr == null) return false;
      final date = DateTime.tryParse(dateStr);
      if (date == null) return false;
      return date.year == prevMonth.year && date.month == prevMonth.month;
    }).toList();

    final currentTotal = currentMonthExpenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );

    final prevTotal = prevMonthExpenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );

    // Calculate change percentage
    final changePercent =
        prevTotal > 0 ? ((currentTotal - prevTotal) / prevTotal) * 100 : 0.0;

    // Calculate due payables
    final duePayables = _payables.where((p) {
      final status = (p['status'] ?? 'unpaid').toString().toLowerCase();
      return status != 'paid';
    }).toList();

    final totalPayables = duePayables.fold<double>(
      0,
      (sum, p) =>
          sum + ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
    );

    // Category breakdown for current month
    final categoryMap = <String, double>{};
    for (final e in currentMonthExpenses) {
      final category = (e['category'] ?? 'Other').toString();
      final amount =
          (e['amount'] is num) ? (e['amount'] as num).toDouble() : 0.0;
      categoryMap[category] = (categoryMap[category] ?? 0) + amount;
    }

    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Text(
            'Financial Overview - ${_getMonthName(currentMonth)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: _FinanceCard(
                  title: 'Monthly Expenses',
                  value: _currency.format(currentTotal),
                  subtitle: changePercent != 0
                      ? '${changePercent > 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}% vs last month'
                      : 'No change vs last month',
                  icon: Icons.account_balance_wallet,
                  color: Colors.red.shade400,
                  trend: changePercent > 0
                      ? Icons.trending_up
                      : changePercent < 0
                          ? Icons.trending_down
                          : Icons.trending_flat,
                  trendColor: changePercent > 0
                      ? Colors.red
                      : changePercent < 0
                          ? Colors.green
                          : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FinanceCard(
                  title: 'Due Payables',
                  value: _currency.format(totalPayables),
                  subtitle: '${duePayables.length} pending',
                  icon: Icons.payment,
                  color: Colors.orange.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Category breakdown
          const Text(
            'Expenses by Category',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (sortedCategories.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.pie_chart_outline,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No expenses recorded this month',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            ...sortedCategories.map((entry) {
              final percent =
                  currentTotal > 0 ? (entry.value / currentTotal * 100) : 0.0;
              return _CategoryBar(
                category: entry.key,
                amount: entry.value,
                percent: percent,
                color: _getCategoryColor(entry.key),
                currency: _currency,
              );
            }),

          const SizedBox(height: 24),

          // Transaction stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    label: 'Transactions',
                    value: '${currentMonthExpenses.length}',
                    icon: Icons.receipt,
                  ),
                  _StatItem(
                    label: 'Avg/Transaction',
                    value: currentMonthExpenses.isNotEmpty
                        ? _currency
                            .format(currentTotal / currentMonthExpenses.length)
                        : '₱0.00',
                    icon: Icons.calculate,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Color _getCategoryColor(String category) {
    final colors = {
      'Ingredients': Colors.orange,
      'Utilities': Colors.yellow.shade700,
      'Rent': Colors.blue,
      'Salaries': Colors.green,
      'Equipment': Colors.purple,
      'Maintenance': Colors.brown,
      'Marketing': Colors.pink,
      'Supplies': Colors.teal,
      'Transportation': Colors.indigo,
      'Taxes': Colors.red,
      'Insurance': Colors.cyan,
      'Other': Colors.grey,
    };
    return colors[category] ?? Colors.blue;
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double revenue;
  final int orders;
  final Color color;

  const _SummaryCard({
    Key? key,
    required this.title,
    required this.revenue,
    required this.orders,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₱${revenue.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$orders orders',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesItemTile extends StatelessWidget {
  final Map<String, dynamic> sale;

  const _SalesItemTile({Key? key, required this.sale}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final revenueRaw = sale['revenue'];
    final revenue = (revenueRaw is num) ? revenueRaw.toDouble() : 0.0;
    return ListTile(
      title: Text(sale['date'] ?? ''),
      subtitle: Text('${sale['orders']} orders'),
      trailing: Text(
        '₱${revenue.toStringAsFixed(2)}',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
    );
  }
}

class _ItemSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ItemSummaryCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String action;
  final Color color;
  final IconData icon;
  final String actionLabel;

  const _RecommendationTile({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.color,
    required this.icon,
    required this.actionLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$actionLabel: $action',
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegend({
    Key? key,
    required this.color,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _FinanceCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final IconData? trend;
  final Color? trendColor;

  const _FinanceCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.trend,
    this.trendColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (trend != null) ...[
                  const Spacer(),
                  Icon(trend, color: trendColor, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: trendColor ?? Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String category;
  final double amount;
  final double percent;
  final Color color;
  final NumberFormat currency;

  const _CategoryBar({
    Key? key,
    required this.category,
    required this.amount,
    required this.percent,
    required this.color,
    required this.currency,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${percent.toStringAsFixed(1)}% • ${currency.format(amount)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
