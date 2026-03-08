import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
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
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 11,
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

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _summaryStats;
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> _itemPerformance = [];
  List<Map<String, dynamic>> _demandForecast = [];
  List<Map<String, dynamic>> _salesForecast = [];
  Map<String, dynamic>? _recommendations;
  bool _isLoading = false;

  int _rangeDays = 7;
  DateTimeRange? _customRange;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final results = await Future.wait([
        ApiService.getSummaryStats(),
        ApiService.getDailySalesAnalytics(days: _rangeDays),
        ApiService.getItemPerformance(),
        ApiService.getDemandForecast(days: _rangeDays),
        ApiService.getSalesForecast(days: _rangeDays),
        ApiService.getRecommendations(),
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
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalyticsData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 180,
                              maxWidth: 280,
                            ),
                            child: _buildRangeSelector(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _showKpis = !_showKpis),
                          icon: Icon(
                            _showKpis ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          label: const Text('KPIs'),
                        ),
                      ],
                    ),
                  ),
                  if (_showKpis)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _buildSummaryStrip(),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: Theme.of(context).colorScheme.primary,
                        unselectedLabelColor: Colors.grey.shade700,
                        indicatorColor: Theme.of(context).colorScheme.primary,
                        tabs: const [
                          Tab(text: 'Sales'),
                          Tab(text: 'Items'),
                          Tab(text: 'Forecast'),
                          Tab(text: 'Insights'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSalesTab(),
                        _buildItemsTab(),
                        _buildForecastTab(),
                        _buildRecommendationsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryStrip() {
    if (_summaryStats == null) return const SizedBox.shrink();

    final today = _summaryStats!['today'] ?? {};
    final week = _summaryStats!['week'] ?? {};
    final month = _summaryStats!['month'] ?? {};
    final menuItems = _summaryStats!['menuItems'] ?? 0;

    final tiles = <Widget>[
      _KpiMiniCard(
        title: 'Today',
        value: _currency.format((today['revenue'] as num?)?.toDouble() ?? 0.0),
        subtitle: '${today['orders'] ?? 0} orders',
        icon: Icons.today,
        color: Colors.blue,
      ),
      _KpiMiniCard(
        title: 'Week',
        value: _currency.format((week['revenue'] as num?)?.toDouble() ?? 0.0),
        subtitle: '${week['orders'] ?? 0} orders',
        icon: Icons.date_range,
        color: Colors.green,
      ),
      _KpiMiniCard(
        title: 'Month',
        value: _currency.format((month['revenue'] as num?)?.toDouble() ?? 0.0),
        subtitle: '${month['orders'] ?? 0} orders',
        icon: Icons.calendar_month,
        color: Colors.orange,
      ),
      _KpiMiniCard(
        title: 'Menu',
        value: menuItems.toString(),
        subtitle: 'items',
        icon: Icons.restaurant_menu,
        color: const Color(0xFF00B0FF),
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => tiles[i],
      ),
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    final hasCustom = _customRange != null;
    final hint = hasCustom
        ? '${DateFormat('MMM d').format(_customRange!.start)} – ${DateFormat('MMM d').format(_customRange!.end)}'
        : 'Select range';

    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: 7, child: Text('Last 7 days')),
      const DropdownMenuItem(value: 30, child: Text('Last 30 days')),
      const DropdownMenuItem(value: 90, child: Text('Last 90 days')),
      const DropdownMenuItem(value: -1, child: Text('Custom range')),
      if (hasCustom && !{7, 30, 90}.contains(_rangeDays))
        DropdownMenuItem(
          value: _rangeDays,
          child: Text(hint),
        ),
    ];

    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _rangeDays,
          isExpanded: true,
          iconSize: 18,
          itemHeight: 48,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
          items: items,
          onChanged: (v) async {
            if (v == null) return;
            if (v == -1) {
              final now = DateTime.now();
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
              });
              await _loadAnalyticsData();
              return;
            }

            setState(() {
              _customRange = null;
              _rangeDays = v;
            });
            await _loadAnalyticsData();
          },
        ),
      ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Sales (Last $_rangeDays Days)',
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
          ..._dailySales.map((sale) => _SalesItemTile(sale: sale)).toList(),
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
          const Text(
            'Top Performing Items',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
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
    if (_recommendations == null)
      return const Center(child: Text('No recommendations available'));

    final promoteItems = _recommendations!['promoteItems'] ?? [];
    final removeItems = _recommendations!['removeItems'] ?? [];
    final optimizeInventory = _recommendations!['optimizeInventory'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Recommendations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (promoteItems.isNotEmpty) ...[
            const Text(
              'Items to Promote',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green),
            ),
            const SizedBox(height: 8),
            ...promoteItems
                .map((item) => _RecommendationTile(
                      title: item['name'],
                      subtitle: item['reason'],
                      action: 'Expected increase: ${item['expectedIncrease']}',
                      color: Colors.green,
                    ))
                .toList(),
            const SizedBox(height: 16),
          ],
          if (removeItems.isNotEmpty) ...[
            const Text(
              'Items to Remove',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            ...removeItems
                .map((item) => _RecommendationTile(
                      title: item['name'],
                      subtitle: item['reason'],
                      action: 'Waste reduction: ${item['wasteReduction']}',
                      color: Colors.red,
                    ))
                .toList(),
            const SizedBox(height: 16),
          ],
          if (optimizeInventory.isNotEmpty) ...[
            const Text(
              'Inventory Optimization',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
            const SizedBox(height: 8),
            ...optimizeInventory
                .map((item) => _RecommendationTile(
                      title: item['ingredient'],
                      subtitle: item['reason'],
                      action: item['action'],
                      color: Colors.orange,
                    ))
                .toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildSalesChart() {
    final points = <FlSpot>[];
    final orderBars = <BarChartGroupData>[];

    for (var i = 0; i < _dailySales.length; i++) {
      final d = _dailySales[i];
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
      if (index < 0 || index >= _dailySales.length) return '';
      final raw = _dailySales[index]['date']?.toString() ?? '';
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
                  'Revenue & Orders',
                  style: TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Revenue max: ${_currency.format(maxRevenue)}',
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
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _dailySales.length <= 7 ? 1 : 2,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= _dailySales.length) {
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
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: _dailySales.length <= 7 ? 1 : 2,
                            getTitlesWidget: (value, meta) {
                              final idx = value.round();
                              if (idx < 0 || idx >= _dailySales.length) {
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

  const _RecommendationTile({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                action,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
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
