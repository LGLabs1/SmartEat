import '../models/business_context.dart';
import 'intent_detector.dart';

/// Builds a compact, intent-specific Business Snapshot that is injected into
/// every AI prompt.  Only the data relevant to the detected intent is included.
///
/// Flow:
///   User message → IntentDetector → SmartSnapshotBuilder.build()
///                                          ↓
///                               Snapshot (hidden from user)
///                                          ↓
///                               Appended to AI prompt
///
/// The user NEVER sees the snapshot.  The AI uses it to give accurate,
/// data-backed answers without ever touching Firestore.
class SmartSnapshotBuilder {
  // ── Public entry point ─────────────────────────────────────────────────

  /// Builds and returns the plain-text snapshot for [intent].
  /// Returns an empty string ONLY for [IntentDetector.intentNavigation].
  /// For [IntentDetector.intentGeneral] or unrecognized intents, returns
  /// the Business Overview snapshot so Sage always has live facts.
  static String build(
    BusinessContext ctx,
    String intent, {
    IntentAnalysis? analysis,
  }) {
    if (intent == IntentDetector.intentNavigation) {
      return '';
    }

    try {
      final sb = StringBuffer();

      _writeHeader(sb, ctx, intent, analysis);

      switch (intent) {
        case IntentDetector.intentSales:
          _writeSales(sb, ctx);
        case IntentDetector.intentInventory:
          _writeInventory(sb, ctx);
        case IntentDetector.intentMenu:
          _writeMenu(sb, ctx);
        case IntentDetector.intentFinance:
          _writeFinance(sb, ctx);
        case IntentDetector.intentBusiness:
        case IntentDetector.intentGeneral:
        default:
          _writeBusinessOverview(sb, ctx);
      }

      _writeRecommendations(sb, ctx, intent);
      _writeFooter(sb);

      return sb.toString();
    } catch (e) {
      return 'SMARTEAT BUSINESS SNAPSHOT (partial)\n'
          'Restaurant: ${ctx.eateryName.isNotEmpty ? ctx.eateryName : "Your Restaurant"}\n'
          'Generated: ${ctx.generatedAt}\n'
          'Note: Some KPI details were unavailable (${e.toString()}).\n'
          'Available: net sales today/month context may be limited; use labeled values when shown.\n';
    }
  }

  // ── Header / footer ────────────────────────────────────────────────────

  static void _writeHeader(
    StringBuffer sb,
    BusinessContext ctx,
    String intent,
    IntentAnalysis? analysis,
  ) {
    final name = ctx.eateryName.isNotEmpty ? ctx.eateryName : 'Your Restaurant';
    final now = DateTime.now();
    final ts =
        '${_weekday(now.weekday)}, ${_monthName(now.month)} ${now.day} ${now.year}'
        ' ${_fmtTime(now)}';

    sb.writeln('================================================');
    sb.writeln('SMARTEAT BUSINESS SNAPSHOT');
    sb.writeln('Intent    : ${IntentDetector.intentLabel(intent)}');
    if (analysis != null) {
      sb.writeln('Concepts  : ${analysis.concepts.join(', ')}');
      sb.writeln('Confidence: ${analysis.confidence}');
    }
    sb.writeln('Restaurant: $name');
    sb.writeln('Generated : $ts');
    sb.writeln('================================================');
    sb.writeln();
    sb.writeln('BUSINESS TERM DEFINITIONS');
    sb.writeln('Revenue/sales/takings/turnover = completed-order income.');
    sb.writeln('Orders/transactions/tickets = order counts.');
    sb.writeln(
        'Best seller/popular item = highest item sales in the stated period.');
    sb.writeln(
        'Slow mover/underperforming item = item with low or zero sales.');
    sb.writeln(
        'Low stock/running short = current stock at or below its minimum.');
    sb.writeln(
        'Actual COGS vs Gross Margin (by Menu Costing) are different metrics: use the labels shown. If a profit/COGS/payables metric is not shown, say it is unavailable and do not derive it.');
    sb.writeln();
  }

  static void _writeFooter(StringBuffer sb) {
    sb.writeln('================================================');
  }

  // ── Intent sections ────────────────────────────────────────────────────

  static void _writeSales(StringBuffer sb, BusinessContext ctx) {
    // Revenue
    sb.writeln('REVENUE');
    sb.writeln('Today         : ₱${_fmt(ctx.todayRevenue)} '
        '(${_sign(ctx.dayChangePercent)}% vs yesterday)');
    sb.writeln('Yesterday     : ₱${_fmt(ctx.yesterdayRevenue)}');
    sb.writeln('This Week     : ₱${_fmt(ctx.weekRevenue)}');
    sb.writeln('This Month    : ₱${_fmt(ctx.monthRevenue)} '
        '(${_sign(ctx.monthlyGrowthPercent)}% vs ${ctx.lastMonth.isNotEmpty ? ctx.lastMonth : "last month"})');
    sb.writeln('Avg Order Val : ₱${_fmt(ctx.averageOrderValue)}');
    sb.writeln();

    // Orders
    sb.writeln('ORDERS');
    sb.writeln('Completed Today   : ${ctx.todayOrderCount}');
    sb.writeln('Completed Week    : ${ctx.weekOrderCount}');
    sb.writeln('Completed Month   : ${ctx.monthOrderCount}');
    sb.writeln('Pending Now       : ${ctx.pendingOrderCount}');
    sb.writeln('Cancelled (7 days): ${ctx.cancelledLast7Days} '
        '(${ctx.cancellationRatePercent.toStringAsFixed(1)}% rate)');
    sb.writeln();

    // Best sellers
    sb.writeln('BEST SELLERS');
    sb.writeln("Today's Best  : ${ctx.todayBestSeller} "
        '(${ctx.todayBestSellerQty} sold today)');
    sb.writeln('Overall Best  : ${ctx.overallBestSeller} '
        '(${ctx.overallBestSellerQty} sold this month, '
        '₱${_fmt(ctx.overallBestSellerRevenue)} revenue)');
    if (ctx.topFiveItems.isNotEmpty) {
      final list = ctx.topFiveItems
          .take(5)
          .map((i) => '${(i['name'] ?? 'Item')} (${i['qty']}x)')
          .join(', ');
      sb.writeln('Top 5 (month) : $list');
    }
    sb.writeln();

    // Worst sellers
    if (ctx.worstItems.isNotEmpty) {
      sb.writeln('SLOW MOVERS (last 30 days)');
      for (final item in ctx.worstItems.take(5)) {
        final sold = (item['soldLast30Days'] as num?)?.toInt() ?? 0;
        sb.writeln('  - ${item['name']}: $sold sold');
      }
      sb.writeln('Zero-sales items: ${ctx.zeroSalesItemCount}');
      sb.writeln();
    }

    // Trends & timing
    sb.writeln('TRENDS & TIMING');
    sb.writeln('14-day trend  : ${_capitalize(ctx.trendDirection)}');
    sb.writeln('Best day      : ${ctx.bestDayOfWeek} '
        '(₱${_fmt(ctx.bestDayRevenue)} avg revenue)');
    sb.writeln('Peak hour     : ${ctx.peakHour} '
        '(${ctx.peakHourOrderCount} orders avg)');
    sb.writeln('Slowest hour  : ${ctx.slowestHour}');
    if (ctx.weeklyBreakdown.isNotEmpty) {
      sb.writeln('Weekly pattern:');
      for (final day in ctx.weeklyBreakdown) {
        sb.writeln(
            '  ${(day['day'] ?? '')}: ₱${_fmt(_n(day['revenue']))} '
            '(${(day['orders'] ?? 0)} orders)');
      }
    }
    sb.writeln();

    // Forecast
    if (ctx.salesForecast.isNotEmpty) {
      sb.writeln('SALES FORECAST (next 7 days, ${ctx.forecastLabel})');
      sb.writeln('  Forecast revenue: ₱${_fmt(ctx.forecastRevenue7d)} | est. ingredient cost: ₱${_fmt(ctx.forecastIngredientCost7d)} | est. profit: ₱${_fmt(ctx.forecastProfit7d)}');
      for (final day in ctx.salesForecast.take(7)) {
        final weekend = day['isWeekend'] == true ? ' (weekend)' : '';
        sb.writeln('  ${(day['dayName'] ?? '')} ${(day['date'] ?? '')}: '
            '₱${_fmt(_n(day['predictedRevenue']))} predicted$weekend');
      }
      sb.writeln();
    }
  }

  static void _writeInventory(StringBuffer sb, BusinessContext ctx) {
    // Summary
    sb.writeln('INVENTORY SUMMARY');
    sb.writeln('Total items tracked : ${ctx.totalInventoryItems}');
    sb.writeln(
        'Healthy             : ${ctx.totalInventoryItems - ctx.lowStockCount - ctx.criticalStockCount}');
    sb.writeln('Low stock           : ${ctx.lowStockCount}');
    sb.writeln('Out of stock (zero) : ${ctx.criticalStockCount}');
    sb.writeln('Total value         : ₱${_fmt(ctx.totalInventoryValue)}');
    sb.writeln('Waste (period/cost data): ₱${_fmt(ctx.inventoryWasteCost)} (qty ${_fmt(ctx.inventoryWasteQty)})');
    sb.writeln('Consumption: ${ctx.hasActualInventoryConsumption ? "₱${_fmt(ctx.inventoryConsumptionCost)} (qty ${_fmt(ctx.inventoryConsumptionQty)})" : "N/A (no sale-consumption records)"}');
    sb.writeln();

    sb.writeln();

    // Critical items — out of stock
    final critical =
        ctx.lowStockItems.where((i) => i['isCritical'] == true).toList();
    if (critical.isNotEmpty) {
      sb.writeln('OUT OF STOCK — RESTOCK IMMEDIATELY');
      for (final item in critical) {
        sb.writeln('  ! ${item['name']} — 0 ${(item['unit'] ?? '')} remaining');
      }
      sb.writeln();
    }

    // Low stock items
    final lowOnly =
        ctx.lowStockItems.where((i) => i['isCritical'] != true).toList();
    if (lowOnly.isNotEmpty) {
      sb.writeln('LOW STOCK ITEMS');
      for (final item in lowOnly.take(8)) {
        final current = _n(item['currentStock']).toStringAsFixed(1);
        final min = _n(item['minStock']).toStringAsFixed(1);
        final deficit = _n(item['deficit']).toStringAsFixed(1);
        sb.writeln('  - ${item['name']}: $current ${(item['unit'] ?? '')} '
            '(min: $min, short by $deficit)');
      }
      sb.writeln();
    }

    // Expiring items
    if (ctx.expiringItems.isNotEmpty) {
      sb.writeln('EXPIRING SOON');
      for (final item in ctx.expiringItems.take(5)) {
        final days = (item['daysUntilExpiry'] as num?)?.toInt() ?? 0;
        final stock = _n(item['currentStock']).toStringAsFixed(1);
        final label = days <= 0
            ? 'EXPIRED' : days == 1
                ? 'expires TOMORROW' : 'expires in ${days}d';
        sb.writeln('  - ${item['name']}: $stock ${(item['unit'] ?? '')} — $label '
            '(${(item['expirationDate'] ?? '')})');
      }
      sb.writeln();
    }

    // Suggested restocks
    if (ctx.suggestedRestocks.isNotEmpty) {
      sb.writeln('SUGGESTED RESTOCKS');
      for (final item in ctx.suggestedRestocks.take(6)) {
        final priority = (item['priority'] ?? 'HIGH').toString();
        final qty = _n(item['suggestedOrderQty']).toStringAsFixed(1);
        sb.writeln('  [$priority] ${item['name']}: order $qty ${(item['unit'] ?? '')}');
      }
      sb.writeln();
    }
  }

  static void _writeMenu(StringBuffer sb, BusinessContext ctx) {
    // Overview
    sb.writeln('MENU PROFITABILITY (menu-costing estimates; separate from Actual COGS)');
    sb.writeln('Highest profit: ${ctx.highestProfitItem}');
    for (final i in ctx.menuHighestProfit.take(3)) {
      sb.writeln('  + ${(i['name'] ?? 'Item')}: revenue ₱${_fmt(_n(i['revenue']))} | COGS ₱${_fmt(_n(i['cogs']))} | profit ₱${_fmt(_n(i['profit']))} (${_fmt(_n(i['marginPercent']))}%)');
    }
    sb.writeln('Lowest profit: ${ctx.lowestProfitItem}');
    for (final i in ctx.menuLowestProfit.take(3)) {
      sb.writeln('  - ${(i['name'] ?? 'Item')}: revenue ₱${_fmt(_n(i['revenue']))} | COGS ₱${_fmt(_n(i['cogs']))} | profit ₱${_fmt(_n(i['profit']))} (${_fmt(_n(i['marginPercent']))}%)');
    }
    sb.writeln();
    sb.writeln('MENU OVERVIEW');
    sb.writeln('Total items        : ${ctx.totalMenuItems}');
    sb.writeln(
        'Items with no sales: ${ctx.menuItemsWithNoSales} (last 30 days)');
    sb.writeln('Top category       : ${ctx.topCategory}');
    sb.writeln();

    // Category performance
    if (ctx.categoryBreakdown.isNotEmpty) {
      sb.writeln('CATEGORY PERFORMANCE (last 30 days)');
      for (final cat in ctx.categoryBreakdown.take(6)) {
        sb.writeln(
            '  - ${(cat['category'] ?? 'Category')}: ₱${_fmt(_n(cat['revenue']))} '
            '(${(cat['unitsSold'] ?? 0)} sold)');
      }
      sb.writeln();
    }

    // Best sellers
    sb.writeln('TOP SELLERS');
    sb.writeln("Today's best : ${ctx.todayBestSeller} "
        '(${ctx.todayBestSellerQty} sold today)');
    sb.writeln('Overall best : ${ctx.overallBestSeller} '
        '(${ctx.overallBestSellerQty} sold this month)');
    if (ctx.topFiveItems.isNotEmpty) {
      sb.writeln('Top 5 items  :');
      for (final item in ctx.topFiveItems.take(5)) {
        sb.writeln('  ${item['name']}: ${item['qty']}x sold, '
            '₱${_fmt(_n(item['revenue']))} revenue');
      }
    }
    sb.writeln();

    // Worst sellers / zero-sales
    if (ctx.worstItems.isNotEmpty) {
      sb.writeln('SLOW MOVERS & ZERO SALES (last 30 days)');
      for (final item in ctx.worstItems.take(8)) {
        final sold = (item['soldLast30Days'] as num?)?.toInt() ?? 0;
        final label = sold == 0 ? 'NO SALES' : '$sold sold';
        sb.writeln('  - ${item['name']}: $label');
      }
      sb.writeln();
    }

    // Full menu performance table
    if (ctx.menuPerformance.isNotEmpty) {
      sb.writeln('FULL MENU PERFORMANCE');
      for (final item in ctx.menuPerformance.take(15)) {
        final sold = (item['soldLast30Days'] as num?)?.toInt() ?? 0;
        final rev = _fmt(_n(item['revenueLast30Days']));
        final status = (item['status'] ?? '').toString();
        sb.writeln('  ${item['name']}: $sold sold, ₱$rev revenue [$status]');
      }
      sb.writeln();
    }
  }

  static void _writeFinance(StringBuffer sb, BusinessContext ctx) {
    sb.writeln('FINANCIAL SUMMARY (NET/GROSS labeled)');
    sb.writeln('This Month net      : \u20B1${_fmt(ctx.netSalesMonth > 0 ? ctx.netSalesMonth : ctx.monthRevenue)} | gross: \u20B1${_fmt(ctx.grossSalesMonth)} | discounts: \u20B1${_fmt(ctx.discountsMonth)}');
    sb.writeln('Revenue growth (MoM): ${_sign(ctx.revenueGrowthMonthPercent)}% vs last month');
    sb.writeln('This Week net       : \u20B1${_fmt(ctx.netSalesWeek > 0 ? ctx.netSalesWeek : ctx.weekRevenue)} | gross: \u20B1${_fmt(ctx.grossSalesWeek)} | discounts: \u20B1${_fmt(ctx.discountsWeek)}');
    sb.writeln('Today net           : \u20B1${_fmt(ctx.todayNetSales > 0 ? ctx.todayNetSales : ctx.todayRevenue)} | gross: \u20B1${_fmt(ctx.todayGrossSales)} | discounts: \u20B1${_fmt(ctx.todayDiscounts)}');
    sb.writeln('Avg Order Value     : \u20B1${_fmt(ctx.averageOrderValueMonth > 0 ? ctx.averageOrderValueMonth : ctx.averageOrderValue)}');
    sb.writeln('Avg item selling price: \u20B1${_fmt(ctx.averageItemSellingPriceMonth)}');
    sb.writeln();
    sb.writeln('COGS / PROFIT (use labels)');
    sb.writeln('COGS (${ctx.cogsSourceMonth}): \u20B1${_fmt(ctx.actualCogsMonth)}${ctx.cogsIsEstimatedMonth ? " [estimated]" : " [actual]"}');
    sb.writeln('Gross Margin (by Menu Costing, estimate; separate from Actual COGS): ${_fmt(ctx.grossMarginByMenuCostingPercent)}% | menu-costing COGS est: \u20B1${_fmt(ctx.menuCostingCogsMonth)}');
    sb.writeln('Operating expenses  : \u20B1${_fmt(ctx.operatingExpensesMonth)} (${_sign(ctx.expenseGrowthMonthPercent)}% MoM, heuristic)');
    sb.writeln('Net profit          : \u20B1${_fmt(ctx.netProfitMonth)} | margin: ${_fmt(ctx.netProfitMarginMonth)}%');
    sb.writeln();
    sb.writeln('PAYABLES');
    sb.writeln('Outstanding         : \u20B1${_fmt(ctx.outstandingPayables)} | overdue: \u20B1${_fmt(ctx.overduePayables)}');
    sb.writeln('Bills due           : today ${ctx.payablesDueToday}, this week ${ctx.payablesDueWeek}, this month ${ctx.payablesDueMonth}');
    sb.writeln();
    sb.writeln('ORDERS');
    sb.writeln('Completed This Month: ${ctx.ordersMonth > 0 ? ctx.ordersMonth : ctx.monthOrderCount}');
    sb.writeln('Cancelled (7 days)  : ${ctx.cancelledLast7Days} (${ctx.cancellationRatePercent.toStringAsFixed(1)}% rate)');
    sb.writeln();
    sb.writeln('BUSINESS HEALTH');
    sb.writeln('Health Score: ${ctx.healthScore.toStringAsFixed(0)}/100 '
        '(${ctx.healthLabel})');
    sb.writeln();

    // Inventory value as a cost indicator
    if (ctx.totalInventoryValue > 0) {
      sb.writeln('INVENTORY VALUE');
      sb.writeln('Total stock value: ₱${_fmt(ctx.totalInventoryValue)}');
      if (ctx.criticalStockCount > 0) {
        sb.writeln('Out-of-stock items: ${ctx.criticalStockCount} '
            '(potential lost revenue)');
      }
      sb.writeln();
    }
  }

  static void _writeBusinessOverview(StringBuffer sb, BusinessContext ctx) {
    // Health
    sb.writeln('BUSINESS HEALTH');
    sb.writeln('Score: ${ctx.healthScore.toStringAsFixed(0)}/100 '
        '(${ctx.healthLabel})');
    sb.writeln();

    // Revenue snapshot
    sb.writeln('REVENUE');
    sb.writeln('Today  : ₱${_fmt(ctx.todayRevenue)} '
        '(${_sign(ctx.dayChangePercent)}% vs yesterday)');
    sb.writeln('Week   : ₱${_fmt(ctx.weekRevenue)}');
    sb.writeln('Month  : ₱${_fmt(ctx.monthRevenue)} '
        '(${_sign(ctx.monthlyGrowthPercent)}% vs '
        '${ctx.lastMonth.isNotEmpty ? ctx.lastMonth : "last month"})');
    sb.writeln('Avg Ord: ₱${_fmt(ctx.averageOrderValue)}');
    sb.writeln();

    // Orders
    sb.writeln('ORDERS TODAY');
    sb.writeln('Completed: ${ctx.todayOrderCount}');
    sb.writeln('Pending  : ${ctx.pendingOrderCount}');
    sb.writeln('Cancelled (7d): ${ctx.cancelledLast7Days}');
    sb.writeln();

    // Best seller
    sb.writeln('TOP PERFORMER');
    sb.writeln("Today's best : ${ctx.todayBestSeller} "
        '(${ctx.todayBestSellerQty} sold)');
    sb.writeln('Overall best : ${ctx.overallBestSeller} '
        '(${ctx.overallBestSellerQty} this month)');
    sb.writeln();

    // Inventory alert
    sb.writeln('INVENTORY STATUS');
    sb.writeln('Total tracked: ${ctx.totalInventoryItems} items');
    sb.writeln('Low stock    : ${ctx.lowStockCount}');
    sb.writeln('Out of stock : ${ctx.criticalStockCount}');
    if (ctx.lowStockItems.isNotEmpty) {
      final names =
          ctx.lowStockItems.take(3).map((i) => (i['name'] ?? 'Item') as String).join(', ');
      sb.writeln('Affected     : $names'
          '${ctx.lowStockCount > 3 ? " and ${ctx.lowStockCount - 3} more" : ""}');
    }
    sb.writeln();

    // Trends
    sb.writeln('TRENDS & TIMING');
    sb.writeln('14-day trend: ${_capitalize(ctx.trendDirection)}');
    sb.writeln('Best day    : ${ctx.bestDayOfWeek} '
        '(₱${_fmt(ctx.bestDayRevenue)} avg)');
    sb.writeln('Peak hour   : ${ctx.peakHour}');
    sb.writeln();

    // Next 3-day forecast
    if (ctx.salesForecast.isNotEmpty) {
      sb.writeln('FORECAST (next 3 days)');
      for (final day in ctx.salesForecast.take(3)) {
        sb.writeln('  ${(day['dayName'] ?? '')}: '
            '₱${_fmt(_n(day['predictedRevenue']))} predicted');
      }
      sb.writeln();
    }
  }

  // ── Recommendations ────────────────────────────────────────────────────

  static void _writeRecommendations(
      StringBuffer sb, BusinessContext ctx, String intent) {
    final recs = <String>[];

    // ── Inventory-related (shown for inventory + business) ────────────────
    if (intent == IntentDetector.intentInventory ||
        intent == IntentDetector.intentBusiness) {
      // Out-of-stock — critical
      final critical =
          ctx.lowStockItems.where((i) => i['isCritical'] == true).toList();
      for (final item in critical.take(3)) {
        recs.add(
            '🔴 Restock ${item['name']} immediately — completely out of stock.');
      }

      // Low stock
      for (final item
          in ctx.lowStockItems.where((i) => i['isCritical'] != true).take(3)) {
        final qty = (item['deficit'] as num? ?? 0).toStringAsFixed(1);
        recs.add(
            '🟡 Order ${item['name']}: need at least $qty ${(item['unit'] ?? '')} more.');
      }

      // Expiring
      for (final item in ctx.expiringItems.take(2)) {
        final days = (item['daysUntilExpiry'] as num?)?.toInt() ?? 0;
        if (days <= 0) {
          recs.add(
              '🔴 ${item['name']} has EXPIRED — remove from use immediately.');
        } else if (days <= 2) {
          recs.add(
              '🟠 ${item['name']} expires in ${days}d — use or discount now.');
        } else {
          recs.add(
              '🟡 ${item['name']} expires in ${days}d — prioritise in meals.');
        }
      }
    }

    // ── Sales / menu related ──────────────────────────────────────────────
    if (intent == IntentDetector.intentSales ||
        intent == IntentDetector.intentMenu ||
        intent == IntentDetector.intentBusiness) {
      if (ctx.todayBestSeller != 'None' && ctx.todayBestSellerQty > 0) {
        recs.add('⭐ ${ctx.todayBestSeller} is today\'s top seller — '
            'ensure enough stock to keep up with demand.');
      }

      // Trending positively
      if (ctx.trendDirection == 'improving' && ctx.dayChangePercent >= 10) {
        recs.add('📈 Revenue is up ${ctx.dayChangePercent.toStringAsFixed(0)}% '
            'vs yesterday — great momentum, maintain service speed.');
      }

      // Declining
      if (ctx.trendDirection == 'declining' || ctx.dayChangePercent <= -15) {
        recs.add('📉 Revenue has been declining — review pricing, '
            'promotions, or peak-hour staffing.');
      }

      // Zero-sales items
      if (ctx.zeroSalesItemCount > 0) {
        final names = ctx.worstItems
            .where((i) => (i['soldLast30Days'] as int? ?? 0) == 0)
            .take(2)
            .map((i) => (i['name'] ?? 'Item') as String)
            .join(' and ');
        if (names.isNotEmpty) {
          recs.add('🗑️ $names have not sold in 30 days — consider removing '
              'or running a promotion to clear them.');
        }
      }

      // Best day insight
      if (ctx.bestDayOfWeek != 'N/A') {
        recs.add('📅 ${ctx.bestDayOfWeek} consistently generates the highest '
            'revenue — prepare extra staff and inventory for that day.');
      }

      // High cancellation
      if (ctx.cancellationRatePercent >= 10) {
        recs.add('⚠️ ${ctx.cancellationRatePercent.toStringAsFixed(1)}% '
            'cancellation rate this week — investigate order delays or errors.');
      }
    }

    // ── Finance specific ──────────────────────────────────────────────────
    if (intent == IntentDetector.intentFinance) {
      if (ctx.monthlyGrowthPercent >= 10) {
        recs.add(
            '✅ Revenue grew ${ctx.monthlyGrowthPercent.toStringAsFixed(1)}% '
            'vs last month — good time to invest in promotions or new items.');
      } else if (ctx.monthlyGrowthPercent <= -10) {
        recs.add(
            '⚠️ Revenue dropped ${ctx.monthlyGrowthPercent.abs().toStringAsFixed(1)}% '
            'vs last month — review expenses and identify slow periods.');
      }

      if (ctx.averageOrderValue > 0) {
        recs.add('💡 Average order value is ₱${_fmt(ctx.averageOrderValue)} — '
            'consider bundle deals or add-ons to increase this.');
      }

      if (ctx.healthScore < 60) {
        recs.add(
            '🔴 Business health score is ${ctx.healthScore.toStringAsFixed(0)}/100 '
            '— review both revenue and cost drivers urgently.');
      }
    }

    if (recs.isEmpty) return;

    sb.writeln('RECOMMENDATIONS');
    for (final r in recs) {
      sb.writeln(r);
    }
    sb.writeln();
  }

  // ── Formatting helpers ─────────────────────────────────────────────────

  static String _fmt(double v) => v.toStringAsFixed(2);
  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse("$v") ?? 0.0;

  static String _sign(double v) =>
      v >= 0 ? '+${v.toStringAsFixed(1)}' : v.toStringAsFixed(1);

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _weekday(int wd) {
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d[(wd - 1).clamp(0, 6)];
  }

  static String _monthName(int m) {
    const n = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return n[(m - 1).clamp(0, 11)];
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final hh = h == 0 ? 12 : h > 12 ? h - 12 : h;
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = h < 12 ? 'AM' : 'PM';
    return '$hh:$mm $ap';
  }
}
