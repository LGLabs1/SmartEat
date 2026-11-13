/// A complete snapshot of the eatery's business state.
/// Built once before every AI call - the AI reads this, never Firestore.
class BusinessContext {
  // Restaurant info
  final String eateryId;
  final String eateryName;
  final String generatedAt; // ISO-8601

  // Revenue
  final double todayRevenue;
  final double yesterdayRevenue;
  final double weekRevenue;
  final double monthRevenue;
  final double dayChangePercent; // +/- % vs yesterday
  final double monthlyGrowthPercent;
  final String thisMonth;
  final String lastMonth;
  final double lastMonthRevenue;

  // Orders
  final int todayOrderCount;
  final int weekOrderCount;
  final int monthOrderCount;
  final int pendingOrderCount;
  final double pendingOrderValue;
  final int cancelledLast7Days;
  final double cancellationRatePercent;
  final double averageOrderValue;

  // Sales / items
  final String todayBestSeller;
  final int todayBestSellerQty;
  final String overallBestSeller; // last 30 days
  final int overallBestSellerQty;
  final double overallBestSellerRevenue;
  final List<Map<String, dynamic>> topFiveItems; // last 30 days
  final int todayTotalItemsSold;

  // Worst sellers
  final List<Map<String, dynamic>> worstItems; // sold <=3 in 30 days
  final int zeroSalesItemCount;

  // Menu
  final int totalMenuItems;
  final int menuItemsWithNoSales;
  final List<Map<String, dynamic>> menuPerformance; // top 15 items
  final String topCategory;
  final List<Map<String, dynamic>> categoryBreakdown;

  // Inventory
  final int totalInventoryItems;
  final int lowStockCount;
  final int criticalStockCount;
  final double totalInventoryValue;
  final List<Map<String, dynamic>> lowStockItems;
  final List<Map<String, dynamic>> expiringItems;
  final List<Map<String, dynamic>> suggestedRestocks;

  // Peak hours
  final String peakHour;
  final int peakHourOrderCount;
  final String slowestHour;
  final List<Map<String, dynamic>> hourlyBreakdown;

  // Trends
  final String trendDirection; // 'improving' | 'declining' | 'stable'
  final List<Map<String, dynamic>> dailyTrend; // last 14 days
  final String bestDayOfWeek;
  final double bestDayRevenue;
  final List<Map<String, dynamic>> weeklyBreakdown;
  final List<Map<String, dynamic>> salesForecast; // next 7 days

  // Business health
  final double healthScore; // 0-100
  final String healthLabel; // 'Excellent' | 'Good' | 'Fair' | 'Needs Attention'

  // Customer
  final double returningCustomerRatePercent;
  final int uniqueCustomers;

  // Finance (recent KPI expansion - optional/backward-compatible)
  final double grossSalesMonth;
  final double discountsMonth;
  final double netSalesMonth;
  final double grossSalesWeek;
  final double discountsWeek;
  final double netSalesWeek;
  final double actualCogsMonth;
  final String cogsSourceMonth; // e.g. Actual COGS (sale consumption) / Estimated COGS (recipe/menu costing)
  final bool cogsIsEstimatedMonth;
  final double operatingExpensesMonth;
  final double netProfitMonth;
  final double netProfitMarginMonth; // percent
  final double grossMarginByMenuCostingPercent; // estimate, separate from Actual COGS
  final double menuCostingCogsMonth; // estimate
  final double revenueGrowthMonthPercent;
  final double expenseGrowthMonthPercent;
  final int ordersMonth;
  final double averageOrderValueMonth;
  final double averageItemSellingPriceMonth;
  final double todayGrossSales;
  final double todayDiscounts;
  final double todayNetSales;
  final double yesterdayNetSales;
  final double weekGrossSales;

  // Inventory KPIs (cost/value; consumption may be unavailable)
  final double inventoryWasteCost;
  final double inventoryWasteQty;
  final double inventoryConsumptionCost;
  final double inventoryConsumptionQty;
  final bool hasActualInventoryConsumption;

  // Payables
  final double outstandingPayables;
  final double overduePayables;
  final int payablesDueToday;
  final int payablesDueWeek;
  final int payablesDueMonth;

  // Menu profitability (best-effort menu-costing estimates)
  final List<Map<String, dynamic>> menuHighestProfit; // [{name,revenue,cogs,profit,marginPercent}]
  final List<Map<String, dynamic>> menuLowestProfit;
  final String highestProfitItem;
  final String lowestProfitItem;

  // Forecast (estimates)
  final double forecastRevenue7d;
  final double forecastIngredientCost7d;
  final double forecastProfit7d;
  final String forecastLabel;
  final Map<String, dynamic> dailyPeriodSummary;
  final Map<String, dynamic> weeklyPeriodSummary;
  final Map<String, dynamic> yearlyPeriodSummary;

  const BusinessContext({
    required this.eateryId,
    required this.eateryName,
    required this.generatedAt,
    this.todayRevenue = 0,
    this.yesterdayRevenue = 0,
    this.weekRevenue = 0,
    this.monthRevenue = 0,
    this.dayChangePercent = 0,
    this.monthlyGrowthPercent = 0,
    this.thisMonth = '',
    this.lastMonth = '',
    this.lastMonthRevenue = 0,
    this.todayOrderCount = 0,
    this.weekOrderCount = 0,
    this.monthOrderCount = 0,
    this.pendingOrderCount = 0,
    this.pendingOrderValue = 0,
    this.cancelledLast7Days = 0,
    this.cancellationRatePercent = 0,
    this.averageOrderValue = 0,
    this.todayBestSeller = 'None',
    this.todayBestSellerQty = 0,
    this.overallBestSeller = 'None',
    this.overallBestSellerQty = 0,
    this.overallBestSellerRevenue = 0,
    this.topFiveItems = const [],
    this.todayTotalItemsSold = 0,
    this.worstItems = const [],
    this.zeroSalesItemCount = 0,
    this.totalMenuItems = 0,
    this.menuItemsWithNoSales = 0,
    this.menuPerformance = const [],
    this.topCategory = 'N/A',
    this.categoryBreakdown = const [],
    this.totalInventoryItems = 0,
    this.lowStockCount = 0,
    this.criticalStockCount = 0,
    this.totalInventoryValue = 0,
    this.lowStockItems = const [],
    this.expiringItems = const [],
    this.suggestedRestocks = const [],
    this.peakHour = 'N/A',
    this.peakHourOrderCount = 0,
    this.slowestHour = 'N/A',
    this.hourlyBreakdown = const [],
    this.trendDirection = 'unknown',
    this.dailyTrend = const [],
    this.bestDayOfWeek = 'N/A',
    this.bestDayRevenue = 0,
    this.weeklyBreakdown = const [],
    this.salesForecast = const [],
    this.healthScore = 0,
    this.healthLabel = 'Unknown',
    this.returningCustomerRatePercent = 0,
    this.uniqueCustomers = 0,
    this.grossSalesMonth = 0,
    this.discountsMonth = 0,
    this.netSalesMonth = 0,
    this.grossSalesWeek = 0,
    this.discountsWeek = 0,
    this.netSalesWeek = 0,
    this.actualCogsMonth = 0,
    this.cogsSourceMonth = 'Unavailable',
    this.cogsIsEstimatedMonth = true,
    this.operatingExpensesMonth = 0,
    this.netProfitMonth = 0,
    this.netProfitMarginMonth = 0,
    this.grossMarginByMenuCostingPercent = 0,
    this.menuCostingCogsMonth = 0,
    this.revenueGrowthMonthPercent = 0,
    this.expenseGrowthMonthPercent = 0,
    this.ordersMonth = 0,
    this.averageOrderValueMonth = 0,
    this.averageItemSellingPriceMonth = 0,
    this.todayGrossSales = 0,
    this.todayDiscounts = 0,
    this.todayNetSales = 0,
    this.yesterdayNetSales = 0,
    this.weekGrossSales = 0,
    this.inventoryWasteCost = 0,
    this.inventoryWasteQty = 0,
    this.inventoryConsumptionCost = 0,
    this.inventoryConsumptionQty = 0,
    this.hasActualInventoryConsumption = false,
    this.outstandingPayables = 0,
    this.overduePayables = 0,
    this.payablesDueToday = 0,
    this.payablesDueWeek = 0,
    this.payablesDueMonth = 0,
    this.menuHighestProfit = const [],
    this.menuLowestProfit = const [],
    this.highestProfitItem = 'N/A',
    this.lowestProfitItem = 'N/A',
    this.forecastRevenue7d = 0,
    this.forecastIngredientCost7d = 0,
    this.forecastProfit7d = 0,
    this.forecastLabel = 'Estimated (menu-costing/forecast)',
    this.dailyPeriodSummary = const {},
    this.weeklyPeriodSummary = const {},
    this.yearlyPeriodSummary = const {},
  });

  String toPromptString() {
    final sb = StringBuffer();
    sb.writeln('=== SMARTEAT BUSINESS INTELLIGENCE SNAPSHOT ===');
    sb.writeln('Restaurant  : $eateryName');
    sb.writeln('Generated   : $generatedAt');
    sb.writeln('Health Score: $healthScore/100 ($healthLabel)');
    sb.writeln();
    sb.writeln('REVENUE (NET unless labeled)');
    sb.writeln('Today net    : \u20B1${_fmt(todayNetSales > 0 ? todayNetSales : todayRevenue)} (${_sign(dayChangePercent)}% vs yesterday net)');
    sb.writeln('Today gross  : \u20B1${_fmt(todayGrossSales)} | discounts: \u20B1${_fmt(todayDiscounts)}');
    sb.writeln('Yesterday net: \u20B1${_fmt(yesterdayNetSales > 0 ? yesterdayNetSales : yesterdayRevenue)}');
    sb.writeln('This Week net: \u20B1${_fmt(netSalesWeek > 0 ? netSalesWeek : weekRevenue)} | gross: \u20B1${_fmt(grossSalesWeek)} | discounts: \u20B1${_fmt(discountsWeek)}');
    sb.writeln('$thisMonth (MTD) net: \u20B1${_fmt(netSalesMonth > 0 ? netSalesMonth : monthRevenue)} | gross: \u20B1${_fmt(grossSalesMonth)} | discounts: \u20B1${_fmt(discountsMonth)} (${_sign(revenueGrowthMonthPercent != 0 ? revenueGrowthMonthPercent : monthlyGrowthPercent)}% vs $lastMonth)');
    sb.writeln('Avg order value: \u20B1${_fmt(averageOrderValueMonth > 0 ? averageOrderValueMonth : averageOrderValue)} | Avg item selling price: \u20B1${_fmt(averageItemSellingPriceMonth)}');
    sb.writeln();
    sb.writeln('PROFITABILITY (labeled)');
    sb.writeln('COGS ($cogsSourceMonth): \u20B1${_fmt(actualCogsMonth)}${cogsIsEstimatedMonth ? " [estimated]" : " [actual]"}');
    sb.writeln('Gross Margin (by Menu Costing, estimate; separate from Actual COGS): ${_fmt(grossMarginByMenuCostingPercent)}% | menu-costing COGS estimate: \u20B1${_fmt(menuCostingCogsMonth)}');
    sb.writeln('Operating expenses (heuristic): \u20B1${_fmt(operatingExpensesMonth)} (${_sign(expenseGrowthMonthPercent)}% MoM)');
    sb.writeln('Net profit: \u20B1${_fmt(netProfitMonth)} | Net profit margin: ${_fmt(netProfitMarginMonth)}%');
    sb.writeln();
    sb.writeln('ORDERS');
    sb.writeln('Today        : $todayOrderCount completed');
    sb.writeln('This Week    : $weekOrderCount completed');
    sb.writeln('This Month   : ${ordersMonth > 0 ? ordersMonth : monthOrderCount} completed');
    sb.writeln('Pending Now  : $pendingOrderCount (\u20B1${_fmt(pendingOrderValue)} value)');
    sb.writeln('Cancelled (7d): $cancelledLast7Days (${cancellationRatePercent}% rate)');
    sb.writeln();
    sb.writeln('MENU PROFITABILITY (menu-costing estimates)');
    sb.writeln('Highest profit: $highestProfitItem');
    if (menuHighestProfit.isNotEmpty) {
      sb.writeln('Top profit items: ${menuHighestProfit.take(3).map((i) => "${i['name']} profit \u20B1${_fmt(_n(i['profit']))} (${_fmt(_n(i['marginPercent']))}%)").join(' | ')}');
    }
    sb.writeln('Lowest profit: $lowestProfitItem');
    if (menuLowestProfit.isNotEmpty) {
      sb.writeln('Low profit items: ${menuLowestProfit.take(3).map((i) => "${i['name']} profit \u20B1${_fmt(_n(i['profit']))} (${_fmt(_n(i['marginPercent']))}%)").join(' | ')}');
    }
    sb.writeln();
    sb.writeln('BEST SELLERS');
    sb.writeln('Today        : $todayBestSeller ($todayBestSellerQty sold)');
    sb.writeln('Last 30 days : $overallBestSeller ($overallBestSellerQty sold, \u20B1${_fmt(overallBestSellerRevenue)} revenue)');
    if (topFiveItems.isNotEmpty) {
      sb.writeln('Top 5 items  : ${topFiveItems.map((i) => "${i['name']} (${i['qty']})").join(', ')}');
    }
    sb.writeln();
    sb.writeln('INVENTORY KPIs');
    sb.writeln('Tracked value: \u20B1${_fmt(totalInventoryValue)} | low: $lowStockCount | critical: $criticalStockCount');
    sb.writeln('Waste: \u20B1${_fmt(inventoryWasteCost)} (qty ${_fmt(inventoryWasteQty)})');
    sb.writeln('Consumption: ${hasActualInventoryConsumption ? "\u20B1${_fmt(inventoryConsumptionCost)} (qty ${_fmt(inventoryConsumptionQty)})" : "N/A (no sale-consumption records)"}');
    if (lowStockItems.isNotEmpty) {
      sb.writeln('Low stock    : ${lowStockItems.take(5).map((i) => "${i['name']} (${_fmt(_n(i['currentStock']))}/${_fmt(_n(i['minStock']))} ${i['unit']})").join(', ')}');
    }
    sb.writeln();
    sb.writeln('PAYABLES');
    sb.writeln('Outstanding: \u20B1${_fmt(outstandingPayables)} | overdue: \u20B1${_fmt(overduePayables)}');
    sb.writeln('Bills due - today: $payablesDueToday, this week: $payablesDueWeek, this month: $payablesDueMonth');
    sb.writeln();
    sb.writeln('FORECAST ($forecastLabel)');
    sb.writeln('7-day revenue: \u20B1${_fmt(forecastRevenue7d)} | est. ingredient cost: \u20B1${_fmt(forecastIngredientCost7d)} | est. profit: \u20B1${_fmt(forecastProfit7d)}');
    if (salesForecast.isNotEmpty) {
      for (final day in salesForecast.take(7)) {
        sb.writeln('${day['dayName']} ${day['date']}: \u20B1${_fmt(_n(day['predictedRevenue']))} predicted${day['isWeekend'] == true ? ' (weekend)' : ''}');
      }
    }
    if (dailyPeriodSummary.isNotEmpty) sb.writeln('Daily summary: net \u20B1${_fmt(_n(dailyPeriodSummary['revenue']))}, orders ${dailyPeriodSummary['orders'] ?? 0}');
    if (weeklyPeriodSummary.isNotEmpty) sb.writeln('Weekly summary: net \u20B1${_fmt(_n(weeklyPeriodSummary['revenue']))}, orders ${weeklyPeriodSummary['orders'] ?? 0}');
    if (yearlyPeriodSummary.isNotEmpty) sb.writeln('Yearly/YTD summary: net \u20B1${_fmt(_n(yearlyPeriodSummary['revenue']))}, orders ${yearlyPeriodSummary['orders'] ?? 0}');
    sb.writeln();
    sb.writeln('TIMING & TRENDS');
    sb.writeln('Peak hour    : $peakHour ($peakHourOrderCount orders avg)');
    sb.writeln('14-day trend : $trendDirection');
    sb.writeln('=================================================');
    return sb.toString();
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static String _sign(double v) => v >= 0 ? '+${v.toStringAsFixed(1)}' : v.toStringAsFixed(1);
}
