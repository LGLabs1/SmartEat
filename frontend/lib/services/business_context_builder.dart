import 'package:flutter/foundation.dart';
import '../features/finance/data/business_kpis.dart';
import '../models/business_context.dart';
import 'analytics_service.dart';
import 'api_service.dart';
import 'firebase_service.dart';

/// Assembles a [BusinessContext] by running KPI functions in parallel.
/// Call [build] once before every AI request - never let the AI touch Firestore.
///
/// OPTIMIZATION: results are cached for [_cacheTtl] and concurrent callers
/// share a single in-flight build.
class BusinessContextBuilder {
  static const Duration _cacheTtl = Duration(minutes: 5);

  static BusinessContext? _cached;
  static DateTime? _cachedAt;
  static Future<BusinessContext>? _inFlight;

  static Future<BusinessContext> build() {
    final cached = _cached;
    if (cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _buildInternal();
    _inFlight = future;
    future.then((ctx) {
      _cached = ctx;
      _cachedAt = DateTime.now();
    }).whenComplete(() {
      _inFlight = null;
    });
    return future;
  }

  static void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  static Future<BusinessContext> _buildInternal() async {
    try {
      final eateryId = await FirebaseService.getCurrentEateryId();
      if (eateryId == null || eateryId.isEmpty) {
        return _empty('', 'Unknown Restaurant');
      }

      final now = DateTime.now();
      final monthStart = BusinessKpis.startOfMonth(now);
      final monthEnd = BusinessKpis.endOfDay(DateTime(now.year, now.month + 1, 0));
      final yearStart = BusinessKpis.startOfYear(now);
      final weekStart = BusinessKpis.startOfWeek(now);
      final todayStart = BusinessKpis.startOfDay(now);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final yesterdayEnd = todayStart.subtract(const Duration(milliseconds: 1));
      final rangeStart = now.subtract(const Duration(days: 400));
      final rangeEnd = BusinessKpis.endOfDay(now);

      final results = await Future.wait([
        _safe(AnalyticsService.getRevenueSummary(eateryId)),          // 0
        _safe(AnalyticsService.getSalesSummary(eateryId)),            // 1
        _safe(AnalyticsService.getOverallBestSeller(eateryId)),       // 2
        _safe(AnalyticsService.getTodayBestSeller(eateryId)),         // 3
        _safe(AnalyticsService.getWorstSellingItems(eateryId)),       // 4
        _safe(AnalyticsService.getInventorySummary(eateryId)),        // 5
        _safe(AnalyticsService.getLowStockItems(eateryId)),           // 6
        _safe(AnalyticsService.getExpiringIngredients(eateryId)),     // 7
        _safe(AnalyticsService.getSuggestedRestocks(eateryId)),       // 8
        _safe(AnalyticsService.getPeakHours(eateryId)),               // 9
        _safe(AnalyticsService.getSalesTrend(eateryId)),              // 10
        _safe(AnalyticsService.getWeeklyTrend(eateryId)),             // 11
        _safe(AnalyticsService.getMonthlyGrowth(eateryId)),           // 12
        _safe(AnalyticsService.getAverageOrderValue(eateryId)),       // 13
        _safe(AnalyticsService.getPendingOrders(eateryId)),           // 14
        _safe(AnalyticsService.getCancelledOrders(eateryId)),         // 15
        _safe(AnalyticsService.getMenuPerformance(eateryId)),         // 16
        _safe(AnalyticsService.getCategoryPerformance(eateryId)),     // 17
        _safe(AnalyticsService.getReturningCustomerRate(eateryId)),   // 18
        _safe(AnalyticsService.getBusinessHealthScore(eateryId)),     // 19
        _safe(AnalyticsService.getSalesForecast(eateryId)),           // 20
        _safe(_resolveEateryName(eateryId)),                          // 21
        _safeApi(ApiService.getOrdersByDateRange(startDate: rangeStart, endDate: rangeEnd)), // 22
        _safeApi(ApiService.getExpenses()),                           // 23
        _safeApi(ApiService.getPayables()),                           // 24
        _safeApi(ApiService.getItemPerformance()),                    // 25
        _safeApi(ApiService.getInventoryItems()),                     // 26
        _safeApi(ApiService.getDamagedItems()),                       // 27
        _safeApi(ApiService.getStockMovements()),                     // 28
        _safeApi(ApiService.getOrdersForecast(days: 7)),              // 29
      ]);

      final rev      = results[0];
      final sales    = results[1];
      final overall  = results[2];
      final today    = results[3];
      final worst    = results[4];
      final invSum   = results[5];
      final lowStock = results[6];
      final expiring = results[7];
      final restock  = results[8];
      final peak     = results[9];
      final trend    = results[10];
      final weekly   = results[11];
      final monthly  = results[12];
      final aov      = results[13];
      final pending  = results[14];
      final cancelled = results[15];
      final menuPerf = results[16];
      final catPerf  = results[17];
      final customer = results[18];
      final health   = results[19];
      final forecast = results[20];
      final eateryName = (results[21]['name'] as String?) ?? 'Your Restaurant';
      final orders = _asList(results[22]);
      final expenses = _asList(results[23]);
      final payables = _asList(results[24]);
      final itemPerformance = _asList(results[25]['data'] ?? results[25]);
      final inventoryItems = _asList(results[26]);
      final damagedItems = _asList(results[27]);
      final stockMovements = _asList(results[28]);
      final forecastData = _asList(results[29]['forecast'] ?? results[29]);
      final salesForecast = (forecastData.isNotEmpty ? forecastData : _list(forecast['forecast'])).map((e)=>Map<String,dynamic>.from(e)).toList();

      final todayKpi = BusinessKpis.summarizeOrders(orders, start: todayStart, end: rangeEnd);
      final yesterdayKpi = BusinessKpis.summarizeOrders(orders, start: yesterdayStart, end: yesterdayEnd);
      final weekKpi = BusinessKpis.summarizeOrders(orders, start: weekStart, end: rangeEnd);
      final monthKpi = BusinessKpis.summarizeOrders(orders, start: monthStart, end: monthEnd);
      final yearKpi = BusinessKpis.summarizeOrders(orders, start: yearStart, end: rangeEnd);
      final revenueGrowth = BusinessKpis.monthOverMonthRevenue(orders, now);
      final expenseGrowth = BusinessKpis.expenseGrowth(
        expenses,
        currentStart: monthStart,
        currentEnd: monthEnd,
        previousStart: DateTime(now.year, now.month - 1, 1),
        previousEnd: DateTime(now.year, now.month, 0, 23, 59, 59, 999),
      );
      final operatingExpenses = BusinessKpis.operatingExpenses(expenses, start: monthStart, end: monthEnd);
      final menuRows = BusinessKpis.menuProfitRows(itemPerformance);
      final menuRowsMaps = menuRows.map((r) => <String, dynamic>{
            'name': (r.item['name'] ?? r.item['menuItemName'] ?? r.item['title'] ?? 'Item').toString(),
            'revenue': r.revenue,
            'cogs': r.estimatedCogs,
            'profit': r.profit,
            'marginPercent': r.marginPercent,
            'quantity': r.quantity,
            'hasCosting': r.hasCosting,
          }).toList();
      final profitable = menuRowsMaps.where((r) => r['hasCosting'] == true).toList()
        ..sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));
      final highestProfit = profitable.isNotEmpty ? profitable.take(3).toList() : const <Map<String, dynamic>>[];
      final lowestProfit = profitable.length > 1 ? profitable.reversed.take(3).toList().reversed.toList() : const <Map<String, dynamic>>[];
      final menuCogs = menuRows.where((r) => r.hasCosting).fold<double>(0, (s, r) => s + r.estimatedCogs);
      final menuMargin = monthKpi.netSales > 0 ? ((monthKpi.netSales - menuCogs) / monthKpi.netSales) * 100 : 0.0;
      final cogs = BusinessKpis.resolveCogs(
        stockMovements: stockMovements,
        itemPerformance: itemPerformance,
        start: monthStart,
        end: monthEnd,
      );
      final netProfit = monthKpi.netSales - cogs.amount - operatingExpenses;
      final netMargin = monthKpi.netSales > 0 ? (netProfit / monthKpi.netSales) * 100 : 0.0;
      final inventoryKpi = BusinessKpis.inventoryKpi(
        inventoryItems: inventoryItems,
        damagedItems: damagedItems,
        stockMovements: stockMovements,
        start: monthStart,
        end: monthEnd,
      );
      final payablesKpi = BusinessKpis.payablesKpi(payables, now: now);
      final forecastKpi = BusinessKpis.forecastKpi(
        salesForecast: salesForecast,
        menuProfitRowsData: menuRowsMaps,
      );

      final List<Map<String, dynamic>> menuItems =
          ((menuPerf['items'] as List?)?.cast<Map<String, dynamic>>() ?? [])
              .take(15)
              .toList();

      return BusinessContext(
        eateryId: eateryId,
        eateryName: eateryName,
        generatedAt: DateTime.now().toIso8601String(),

        todayRevenue: _d(rev['todayRevenue']),
        yesterdayRevenue: _d(rev['yesterdayRevenue']),
        weekRevenue: _d(rev['weekRevenue']),
        monthRevenue: _d(rev['monthRevenue']),
        dayChangePercent: _d(rev['dayChangePercent']),
        todayOrderCount: _i(rev['todayOrderCount']),
        weekOrderCount: _i(rev['weekOrderCount']),
        monthOrderCount: _i(rev['monthOrderCount']),

        monthlyGrowthPercent: _d(monthly['monthlyGrowthPercent']),
        thisMonth: (monthly['thisMonth'] as String?) ?? '',
        lastMonth: (monthly['lastMonth'] as String?) ?? '',
        lastMonthRevenue: _d(monthly['lastMonthRevenue']),

        pendingOrderCount: _i(pending['count']),
        pendingOrderValue: _d(pending['totalPendingValue']),
        cancelledLast7Days: _i(cancelled['cancelledLast7Days']),
        cancellationRatePercent: _d(cancelled['cancellationRatePercent']),
        averageOrderValue: _d(aov['averageOrderValue']),

        todayBestSeller: (today['bestSeller'] as String?) ?? 'None',
        todayBestSellerQty: _i(today['quantity']),
        overallBestSeller: (overall['bestSeller'] as String?) ?? 'None',
        overallBestSellerQty: _i(overall['quantity']),
        overallBestSellerRevenue: _d(overall['revenue']),
        topFiveItems: _list(overall['topFive']),
        todayTotalItemsSold: _i(sales['todayTotalItemsSold']),

        worstItems: _list(worst['worstItems']),
        zeroSalesItemCount: _i(worst['zeroSalesCount']),

        totalMenuItems: _i(menuPerf['totalMenuItems']),
        menuItemsWithNoSales: _i(menuPerf['itemsWithNoSales']),
        menuPerformance: menuItems,
        topCategory: (catPerf['topCategory'] as String?) ?? 'N/A',
        categoryBreakdown: _list(catPerf['categoryBreakdown']),

        totalInventoryItems: _i(invSum['totalItems']),
        lowStockCount: _i(invSum['lowStockCount']),
        criticalStockCount: _i(invSum['criticalCount']),
        totalInventoryValue: _d(invSum['totalInventoryValue']),
        lowStockItems: _list(lowStock['lowStockItems']),
        expiringItems: _list(expiring['expiringItems']),
        suggestedRestocks: _list(restock['suggestions']),

        peakHour: (peak['peakHour'] as String?) ?? 'N/A',
        peakHourOrderCount: _i(peak['peakHourOrderCount']),
        slowestHour: (peak['slowestHour'] as String?) ?? 'N/A',
        hourlyBreakdown: _list(peak['hourlyBreakdown']),

        trendDirection: (trend['trendDirection'] as String?) ?? 'unknown',
        dailyTrend: _list(trend['dailyTrend']),
        bestDayOfWeek: (weekly['bestDay'] as String?) ?? 'N/A',
        bestDayRevenue: _d(weekly['bestDayRevenue']),
        weeklyBreakdown: _list(weekly['weeklyBreakdown']),
        salesForecast: salesForecast.cast<Map<String, dynamic>>(),

        healthScore: _d(health['score']),
        healthLabel: (health['label'] as String?) ?? 'Unknown',

        returningCustomerRatePercent: _d(customer['returningCustomerRatePercent']),
        uniqueCustomers: _i(customer['uniqueCustomers']),

        grossSalesMonth: monthKpi.grossSales,
        discountsMonth: monthKpi.discounts,
        netSalesMonth: monthKpi.netSales,
        grossSalesWeek: weekKpi.grossSales,
        discountsWeek: weekKpi.discounts,
        netSalesWeek: weekKpi.netSales,
        actualCogsMonth: cogs.amount,
        cogsSourceMonth: cogs.sourceLabel,
        cogsIsEstimatedMonth: cogs.isEstimated,
        operatingExpensesMonth: operatingExpenses,
        netProfitMonth: netProfit,
        netProfitMarginMonth: netMargin,
        grossMarginByMenuCostingPercent: menuMargin,
        menuCostingCogsMonth: menuCogs,
        revenueGrowthMonthPercent: (revenueGrowth.percent ?? _d(monthly['monthlyGrowthPercent'])).toDouble(),
        expenseGrowthMonthPercent: (expenseGrowth.percent ?? 0).toDouble(),
        ordersMonth: monthKpi.ordersCount,
        averageOrderValueMonth: monthKpi.averageOrderValue,
        averageItemSellingPriceMonth: monthKpi.averageSellingPricePerItem,
        todayGrossSales: todayKpi.grossSales,
        todayDiscounts: todayKpi.discounts,
        todayNetSales: todayKpi.netSales,
        yesterdayNetSales: yesterdayKpi.netSales,
        weekGrossSales: weekKpi.grossSales,

        inventoryWasteCost: inventoryKpi.wasteCost,
        inventoryWasteQty: inventoryKpi.wasteQty,
        inventoryConsumptionCost: inventoryKpi.consumptionCost,
        inventoryConsumptionQty: inventoryKpi.consumptionQty,
        hasActualInventoryConsumption: inventoryKpi.hasActualConsumption,

        outstandingPayables: payablesKpi.outstanding,
        overduePayables: payablesKpi.overdue,
        payablesDueToday: payablesKpi.dueToday,
        payablesDueWeek: payablesKpi.dueThisWeek,
        payablesDueMonth: payablesKpi.dueThisMonth,

        menuHighestProfit: highestProfit,
        menuLowestProfit: lowestProfit,
        highestProfitItem: highestProfit.isNotEmpty ? highestProfit.first['name'].toString() : 'N/A',
        lowestProfitItem: lowestProfit.isNotEmpty ? lowestProfit.first['name'].toString() : 'N/A',

        forecastRevenue7d: forecastKpi.forecastRevenue,
        forecastIngredientCost7d: forecastKpi.forecastIngredientCost,
        forecastProfit7d: forecastKpi.forecastProfit,
        forecastLabel: forecastKpi.isEstimated ? 'Estimated (forecast + menu-costing ratio)' : 'Forecast',
        dailyPeriodSummary: {
          'label': 'Daily (today)',
          'revenue': todayKpi.netSales,
          'grossSales': todayKpi.grossSales,
          'discounts': todayKpi.discounts,
          'orders': todayKpi.ordersCount,
          'aov': todayKpi.averageOrderValue,
        },
        weeklyPeriodSummary: {
          'label': 'Weekly (this week)',
          'revenue': weekKpi.netSales,
          'grossSales': weekKpi.grossSales,
          'discounts': weekKpi.discounts,
          'orders': weekKpi.ordersCount,
          'aov': weekKpi.averageOrderValue,
        },
        yearlyPeriodSummary: {
          'label': 'Yearly/YTD',
          'revenue': yearKpi.netSales,
          'grossSales': yearKpi.grossSales,
          'discounts': yearKpi.discounts,
          'orders': yearKpi.ordersCount,
          'aov': yearKpi.averageOrderValue,
        },
      );
    } catch (e) {
      debugPrint('BusinessContextBuilder.build error: $e');
      return _empty('', 'Unknown Restaurant');
    }
  }

  static Future<Map<String, dynamic>> _safe(
      Future<Map<String, dynamic>> f) async {
    try {
      return await f;
    } catch (e) {
      debugPrint('BusinessContextBuilder partial failure: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> _safeApi(
      Future<Map<String, dynamic>> f) async {
    try {
      return await f;
    } catch (e) {
      debugPrint('BusinessContextBuilder API partial failure: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> _resolveEateryName(
      String eateryId) async {
    try {
      final doc = await FirebaseService.getEatery(eateryId);
      return {'name': (doc?['name'] ?? '').toString()};
    } catch (_) {
      return {'name': ''};
    }
  }

  static double _d(dynamic v) =>
      v == null ? 0.0 : (v as num).toDouble();

  static int _i(dynamic v) =>
      v == null ? 0 : (v as num).toInt();

  static List<Map<String, dynamic>> _list(dynamic v) {
    if (v is List) {
      return v.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  static List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (v is Map && v['data'] is List) return _asList(v['data']);
    if (v is Map && v['items'] is List) return _asList(v['items']);
    return const [];
  }

  static BusinessContext _empty(String eateryId, String name) {
    return BusinessContext(
      eateryId: eateryId,
      eateryName: name,
      generatedAt: DateTime.now().toIso8601String(),
    );
  }
}
