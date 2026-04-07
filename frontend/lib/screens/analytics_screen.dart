import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
  Map<String, dynamic>? _summaryStats;
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> _itemPerformance = [];
  List<Map<String, dynamic>> _demandForecast = [];
  List<Map<String, dynamic>> _salesForecast = [];
  Map<String, dynamic>? _recommendations;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _payables = [];
  bool _isLoading = false;

  int _rangeDays = 7;
  DateTimeRange? _customRange;
  String? _selectedMonthYear;
  DateTime? _selectedMonth;
  bool _showKpis = false;

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
      List<dynamic> orders, int days) {
    // Group orders by date and calculate daily totals
    final salesByDate = <String, Map<String, dynamic>>{};
    final now = DateTime.now();

    // Initialize all dates with zero values
    for (var i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
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
      }
      if (orderDate == null) continue;

      final dateStr = DateFormat('yyyy-MM-dd').format(orderDate);
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAnalyticsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      DateTime startDate;
      DateTime endDate = DateTime.now();
      int days = _rangeDays;

      // Handle month-based selections
      if (_rangeDays == -2) {
        // This month
        final now = DateTime.now();
        startDate = DateTime(now.year, now.month, 1);
        days = endDate.difference(startDate).inDays + 1;
      } else if (_rangeDays == -4 && _selectedMonth != null) {
        // Custom selected month/year
        startDate = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
        endDate = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 0);
        days = endDate.difference(startDate).inDays + 1;
      } else {
        startDate = endDate.subtract(Duration(days: _rangeDays - 1));
      }

      final results = await Future.wait([
        ApiService.getSummaryStats(),
        _rangeDays < 0
            ? ApiService.getOrdersByDateRange(
                    startDate: startDate, endDate: endDate)
                .then((r) => _processOrdersToDailySales(
                    r['data'] as List<dynamic>, days))
            : ApiService.getDailySalesAnalytics(days: days),
        ApiService.getItemPerformance(),
        ApiService.getDemandForecast(days: _rangeDays < 0 ? 30 : _rangeDays),
        ApiService.getSalesForecast(days: _rangeDays < 0 ? 30 : _rangeDays),
        ApiService.getRecommendations(),
        ApiService.getExpenses(),
        ApiService.getPayables(),
      ]);

      if (mounted) {
        setState(() {
          _summaryStats = results[0]['data'];
          _dailySales = List<Map<String, dynamic>>.from(
              results[1]['data']['dailySales'] ?? []);
          _itemPerformance = List<Map<String, dynamic>>.from(
              results[2]['data']['items'] ?? []);
          _demandForecast =
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
                            Tab(text: 'Items'),
                            Tab(text: 'Forecast'),
                            Tab(text: 'Insights'),
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
                          // Wide layout: Range selector + KPIs in one row
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Range selector
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 160,
                                  maxWidth: 200,
                                ),
                                child: _buildRangeSelector(context),
                              ),
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
                                  Flexible(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 140,
                                        maxWidth: 200,
                                      ),
                                      child: _buildRangeSelector(context),
                                    ),
                                  ),
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
                        _buildItemsTab(),
                        _buildForecastTab(),
                        _buildRecommendationsTab(),
                        _buildFinanceTab(),
                      ],
                    ),
                  ),
                ],
              ),
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

    // Calculate date ranges for tooltips
    String getRangeTooltip(int days) {
      final start = now.subtract(Duration(days: days - 1));
      return '${DateFormat('M/d').format(start)} - ${DateFormat('M/d').format(now)}';
    }

    final currentMonthStart = DateTime(now.year, now.month, 1);

    final currentMonthTooltip =
        '${DateFormat('M/d').format(currentMonthStart)} - ${DateFormat('M/d').format(now)}';

    String displayValue;
    if (hasCustom) {
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
          initialValue: hasCustom ? -1 : _rangeDays,
          onSelected: (v) async {
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
                Icon(Icons.calendar_today,
                    size: 16, color: Colors.grey.shade600),
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
          itemBuilder: (context) => [
            // Days options
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
            // Month options
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
            // Custom option
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
  }) {
    final isSelected = (_rangeDays == value && value != -1) ||
        (value == -1 && _customRange != null);

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
    String rangeTitle;
    if (_rangeDays == -2) {
      rangeTitle = 'This Month';
    } else if (_rangeDays == -4 && _selectedMonth != null) {
      rangeTitle = DateFormat('MMMM yyyy').format(_selectedMonth!);
    } else if (_customRange != null) {
      rangeTitle =
          '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d').format(_customRange!.end)}';
    } else {
      rangeTitle = 'Last $_rangeDays Days';
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

  Widget _buildItemsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Top Performing Items',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_itemPerformance.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_itemPerformance.length} items',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_itemPerformance.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.restaurant_menu,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No item performance data available',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete some orders to see top performing items',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._itemPerformance
                .take(10)
                .map((item) => _PerformanceItemTile(item: item))
                .toList(),
        ],
      ),
    );
  }

  Widget _buildForecastTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demand Forecast (Next 7 Days)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _demandForecast.isEmpty
                ? const Center(child: Text('No forecast data available'))
                : _buildForecastChart(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sales Forecast (Next 7 Days)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _salesForecast.isEmpty
                ? const Center(child: Text('No forecast data available'))
                : _buildSalesForecastChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsTab() {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with stats
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

          // Items to Promote Section
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

          // Items to Remove Section
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

          // Inventory Optimization Section
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

          const SizedBox(height: 32),
        ],
      ),
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
    // Reverse the data so oldest is on the left, most recent on the right
    final reversedSales = _dailySales.reversed.toList();
    final points = <FlSpot>[];
    final orderBars = <BarChartGroupData>[];

    for (var i = 0; i < reversedSales.length; i++) {
      final d = reversedSales[i];
      final revenue = (d['revenue'] as num?)?.toDouble() ?? 0.0;
      final orders = (d['orders'] as num?)?.toDouble() ?? 0.0;
      points.add(FlSpot(i.toDouble(), revenue));
      orderBars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: orders,
              width: 10,
              borderRadius: BorderRadius.circular(4),
              color: Colors.indigo,
            ),
          ],
        ),
      );
    }

    String labelAt(int index) {
      if (index < 0 || index >= reversedSales.length) return '';
      final raw = reversedSales[index]['date']?.toString() ?? '';
      final parts = raw.split('-');
      if (parts.length == 3) {
        final month = int.tryParse(parts[1]) ?? 0;
        final day = int.tryParse(parts[2]) ?? 0;
        if (month > 0 && day > 0)
          return '${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';
      }
      return raw;
    }

    final maxRevenue = points.isEmpty
        ? 0.0
        : points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final maxOrders = orderBars.isEmpty
        ? 0.0
        : orderBars
            .map((g) => g.barRods.first.toY)
            .reduce((a, b) => a > b ? a : b);

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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Max: ${_currency.format(maxRevenue)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxRevenue <= 0 ? 1 : maxRevenue * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    spots: points,
                    dotData: const FlDotData(show: false),
                    color: Colors.green,
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withOpacity(0.12),
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
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '₱${value.toInt()}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: reversedSales.length <= 7 ? 1 : 2,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= reversedSales.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labelAt(idx),
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
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Orders',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxOrders <= 0 ? 1 : maxOrders * 1.2,
                      barGroups: orderBars,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '${value.toInt()}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: reversedSales.length <= 7 ? 1 : 2,
                            getTitlesWidget: (value, meta) {
                              final idx = value.round();
                              if (idx < 0 || idx >= reversedSales.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  labelAt(idx),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastChart() {
    final points = _demandForecast.take(14).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Predicted Demand',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _demandForecast.isEmpty
                  ? const Center(child: Text('No forecast data'))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: points.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final forecast = points[index];
                        final demandRaw = forecast['predictedDemand'];
                        final demand =
                            ((demandRaw is num) ? demandRaw.toDouble() : 0.0) /
                                50; // Scale down for display
                        final day = (forecast['day'] ?? (index + 1)).toString();

                        return SizedBox(
                          width: 64,
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor:
                                          (demand * 0.9).clamp(0.0, 1.0),
                                      widthFactor: 0.55,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.orange,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Day $day',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                '${(demandRaw is num ? demandRaw : 0)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
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
    final points = _salesForecast.take(14).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Predicted Sales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _salesForecast.isEmpty
                  ? const Center(child: Text('No forecast data'))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: points.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final forecast = points[index];
                        final salesRaw = forecast['predictedSales'];
                        final sales =
                            ((salesRaw is num) ? salesRaw.toDouble() : 0.0) /
                                5000; // Scale down for display
                        final day = (forecast['day'] ?? (index + 1)).toString();

                        return SizedBox(
                          width: 64,
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B0FF)
                                        .withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor:
                                          (sales * 0.9).clamp(0.0, 1.0),
                                      widthFactor: 0.55,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00B0FF),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Day $day',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                salesRaw is num
                                    ? '₱${salesRaw.toStringAsFixed(0)}'
                                    : '₱0',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
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

class _PerformanceItemTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _PerformanceItemTile({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final revenueRaw = item['revenue'];
    final revenue = (revenueRaw is num) ? revenueRaw.toDouble() : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item['name'] ?? ''),
        subtitle: Text('${item['quantitySold']} sold'),
        trailing: Text(
          '₱${revenue.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
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
