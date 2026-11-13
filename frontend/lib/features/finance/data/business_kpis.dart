import 'finance_format.dart';
import 'finance_metrics.dart';

class OrderFinanceFacts {
  const OrderFinanceFacts({
    required this.order,
    required this.date,
    required this.status,
    required this.completed,
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.items,
  });

  final Map<String, dynamic> order;
  final DateTime? date;
  final String status;
  final bool completed;
  final double grossSales;
  final double discounts;
  final double netSales;
  final List<Map<String, dynamic>> items;
}

class PeriodKpi {
  const PeriodKpi({
    required this.revenue,
    required this.grossSales,
    required this.discounts,
    required this.orders,
    required this.itemsSold,
  });

  final double revenue;
  final double grossSales;
  final double discounts;
  final double orders;
  final double itemsSold;

  double get averageOrderValue => orders > 0 ? revenue / orders : 0;
  double get averageSellingPricePerItem => itemsSold > 0 ? revenue / itemsSold : 0;
  double get averageDiscountPerOrder => orders > 0 ? discounts / orders : 0;
  double get netSales => revenue;
  int get ordersCount => orders.round();
}

class GrowthKpi {
  const GrowthKpi({
    required this.current,
    required this.previous,
  });

  final double current;
  final double previous;

  double? get percent {
    if (previous == 0) return current == 0 ? 0 : null;
    return ((current - previous) / previous) * 100;
  }
}

class InventoryKpi {
  const InventoryKpi({
    required this.inventoryValue,
    required this.wasteCost,
    required this.wasteQty,
    required this.consumptionQty,
    required this.consumptionCost,
    required this.hasActualConsumption,
  });

  final double inventoryValue;
  final double wasteCost;
  final double wasteQty;
  final double consumptionQty;
  final double consumptionCost;
  final bool hasActualConsumption;
}

class PayablesKpi {
  const PayablesKpi({
    required this.outstanding,
    required this.overdue,
    required this.dueToday,
    required this.dueThisWeek,
    required this.dueThisMonth,
    required this.estimatedVariable,
  });

  final double outstanding;
  final double overdue;
  final int dueToday;
  final int dueThisWeek;
  final int dueThisMonth;
  final double estimatedVariable;
}

class MenuProfitRow {
  const MenuProfitRow({
    required this.item,
    required this.revenue,
    required this.estimatedCogs,
    required this.profit,
    required this.quantity,
    required this.hasCosting,
  });

  final Map<String, dynamic> item;
  final double revenue;
  final double estimatedCogs;
  final double profit;
  final double quantity;
  final bool hasCosting;

  double get marginPercent => revenue > 0 ? (profit / revenue) * 100 : 0;
  double get profitPerItem => quantity > 0 ? profit / quantity : 0;
  double get cogsPerItem => quantity > 0 ? estimatedCogs / quantity : 0;
  double get revenuePerItem => quantity > 0 ? revenue / quantity : 0;
}

class CogsKpi {
  const CogsKpi({
    required this.amount,
    required this.sourceLabel,
    required this.isEstimated,
  });

  final double amount;
  final String sourceLabel;
  final bool isEstimated;
}

class ForecastKpi {
  const ForecastKpi({
    required this.forecastRevenue,
    required this.forecastIngredientCost,
    required this.forecastProfit,
    required this.isEstimated,
  });

  final double forecastRevenue;
  final double forecastIngredientCost;
  final double forecastProfit;
  final bool isEstimated;
}

class BusinessKpis {
  BusinessKpis._();

  static const Set<String> _operatingExpenseCategories = {
    'utilities',
    'rent',
    'salaries',
    'equipment',
    'maintenance',
    'marketing',
    'supplies',
    'transportation',
    'taxes',
    'insurance',
    'other',
    'bills',
  };

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  static DateTime? _asDate(dynamic v) => FinanceFormat.asDate(v);

  static DateTime? orderDate(Map<String, dynamic> order) {
    return _asDate(order['completedAt']) ??
        _asDate(order['createdAt']) ??
        _asDate(order['updatedAt']);
  }

  static String orderStatus(Map<String, dynamic> order) =>
      (order['status'] ?? '').toString().trim().toLowerCase();

  static bool isCompletedOrder(Map<String, dynamic> order) =>
      orderStatus(order) == 'completed';

  static OrderFinanceFacts orderFacts(Map<String, dynamic> order) {
    final itemsRaw = order['items'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];
    final subtotal = _num(order['subtotal'] ?? order['grossAmount'] ?? order['grossTotal']);
    final computedSubtotal = items.fold<double>(0, (sum, item) {
      final line = _num(item['subtotal']);
      if (line > 0) return sum + line;
      return sum + _num(item['price']) * _num(item['quantity']);
    });
    final grossSales = subtotal > 0 ? subtotal : computedSubtotal;
    final explicitDiscount =
        _num(order['discountAmount'] ?? order['discountTotal'] ?? order['discount'] ?? order['discounts']);
    final total = _num(order['totalAmount'] ?? order['netAmount'] ?? order['netTotal'] ?? order['amount']);
    final inferredDiscount = (grossSales > 0 && total > 0 && grossSales > total)
        ? (grossSales - total)
        : 0.0;
    final discounts = explicitDiscount > 0 ? explicitDiscount : inferredDiscount;
    final netSales = total > 0
        ? total
        : (grossSales - discounts).clamp(0, double.infinity).toDouble();
    return OrderFinanceFacts(
      order: order,
      date: orderDate(order),
      status: orderStatus(order),
      completed: isCompletedOrder(order),
      grossSales: grossSales > 0 ? grossSales : netSales,
      discounts: discounts < 0 ? 0 : discounts,
      netSales: netSales,
      items: items,
    );
  }

  static Iterable<OrderFinanceFacts> completedOrderFacts(
    List<Map<String, dynamic>> orders, {
    DateTime? start,
    DateTime? end,
  }) sync* {
    for (final order in orders) {
      final facts = orderFacts(order);
      if (!facts.completed) continue;
      final date = facts.date;
      if (start != null && (date == null || date.isBefore(start))) continue;
      if (end != null && (date == null || date.isAfter(end))) continue;
      yield facts;
    }
  }

  static PeriodKpi summarizeOrders(
    List<Map<String, dynamic>> orders, {
    DateTime? start,
    DateTime? end,
  }) {
    double revenue = 0, grossSales = 0, discounts = 0, itemsSold = 0, orderCount = 0;
    for (final facts in completedOrderFacts(orders, start: start, end: end)) {
      orderCount++;
      revenue += facts.netSales;
      grossSales += facts.grossSales;
      discounts += facts.discounts;
      for (final item in facts.items) {
        itemsSold += _num(item['quantity']);
      }
    }
    return PeriodKpi(
      revenue: revenue,
      grossSales: grossSales,
      discounts: discounts,
      orders: orderCount,
      itemsSold: itemsSold,
    );
  }

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime startOfWeek(DateTime d) {
    final day = startOfDay(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime startOfYear(DateTime d) => DateTime(d.year, 1, 1);
  static DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static GrowthKpi revenueGrowth(
    List<Map<String, dynamic>> orders, {
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) {
    final current = summarizeOrders(orders, start: currentStart, end: currentEnd).revenue;
    final previous = summarizeOrders(orders, start: previousStart, end: previousEnd).revenue;
    return GrowthKpi(current: current, previous: previous);
  }

  static GrowthKpi monthOverMonthRevenue(List<Map<String, dynamic>> orders, DateTime month) {
    final start = startOfMonth(month);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999);
    final prev = DateTime(month.year, month.month - 1, 1);
    final prevEnd = DateTime(prev.year, prev.month + 1, 0, 23, 59, 59, 999);
    return revenueGrowth(orders, currentStart: start, currentEnd: end, previousStart: prev, previousEnd: prevEnd);
  }

  static bool isOperatingExpense(Map<String, dynamic> expense) {
    if (FinanceMetrics.isPayablePayment(expense)) return true;
    final source = FinanceMetrics.source(expense);
    if (source == FinanceMetrics.inventorySource) return false;
    final category = (expense['category'] ?? '').toString().trim().toLowerCase();
    if (category.isEmpty) return true;
    return _operatingExpenseCategories.contains(category);
  }

  static double operatingExpenses(
    List<Map<String, dynamic>> expenses, {
    DateTime? start,
    DateTime? end,
  }) {
    return expenses.where((e) {
      if (!isOperatingExpense(e)) return false;
      final d = FinanceMetrics.expenseDate(e);
      if (d == null) return false;
      if (start != null && d.isBefore(start)) return false;
      if (end != null && d.isAfter(end)) return false;
      return true;
    }).fold<double>(0, (sum, e) => sum + FinanceMetrics.amountOf(e));
  }

  static GrowthKpi expenseGrowth(
    List<Map<String, dynamic>> expenses, {
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) {
    final current = operatingExpenses(expenses, start: currentStart, end: currentEnd);
    final previous = operatingExpenses(expenses, start: previousStart, end: previousEnd);
    return GrowthKpi(current: current, previous: previous);
  }

  static InventoryKpi inventoryKpi({
    required List<Map<String, dynamic>> inventoryItems,
    required List<Map<String, dynamic>> damagedItems,
    required List<Map<String, dynamic>> stockMovements,
    DateTime? start,
    DateTime? end,
  }) {
    double inventoryValue = 0;
    for (final item in inventoryItems) {
      final stock = _num(item['currentStock']);
      final lastPurchase = _num(item['lastPurchaseCost']);
      final unitCost = _num(item['unitCost']);
      final avg = _num(item['avgCost']);
      final cost = lastPurchase > 0 ? lastPurchase : (avg > 0 ? avg : unitCost);
      inventoryValue += stock * cost;
    }

    double wasteCost = 0, wasteQty = 0;
    for (final item in damagedItems) {
      final d = _asDate(item['createdAt']) ?? _asDate(item['timestamp']) ?? _asDate(item['date']);
      if (start != null && (d == null || d.isBefore(start))) continue;
      if (end != null && (d == null || d.isAfter(end))) continue;
      final qty = _num(item['quantity']);
      wasteQty += qty;
      final total = _num(item['totalCost']);
      if (total > 0) {
        wasteCost += total;
      } else {
        wasteCost += qty * _num(item['unitCost']);
      }
    }

    double consumptionQty = 0, consumptionCost = 0;
    var hasActualConsumption = false;
    for (final movement in stockMovements) {
      final type = (movement['type'] ?? '').toString();
      if (type != 'saleConsumption' && type != 'sale_consumption') continue;
      final d = _asDate(movement['timestamp']) ?? _asDate(movement['createdAt']) ?? _asDate(movement['date']);
      if (start != null && (d == null || d.isBefore(start))) continue;
      if (end != null && (d == null || d.isAfter(end))) continue;
      hasActualConsumption = true;
      final change = _num(movement['changeBase']);
      final qty = change < 0 ? -change : _num(movement['qty']) .abs();
      consumptionQty += qty;
      final impact = _num(movement['totalCostImpact']).abs();
      if (impact > 0) {
        consumptionCost += impact;
      } else {
        consumptionCost += qty * _num(movement['unitCostAtEvent']).abs();
      }
    }

    return InventoryKpi(
      inventoryValue: inventoryValue,
      wasteCost: wasteCost,
      wasteQty: wasteQty,
      consumptionQty: consumptionQty,
      consumptionCost: consumptionCost,
      hasActualConsumption: hasActualConsumption,
    );
  }

  static CogsKpi actualCogsFromMovements(
    List<Map<String, dynamic>> stockMovements, {
    DateTime? start,
    DateTime? end,
  }) {
    double amount = 0;
    var has = false;
    for (final movement in stockMovements) {
      final type = (movement['type'] ?? '').toString();
      if (type != 'saleConsumption' && type != 'sale_consumption') continue;
      final d = _asDate(movement['timestamp']) ?? _asDate(movement['createdAt']) ?? _asDate(movement['date']);
      if (start != null && (d == null || d.isBefore(start))) continue;
      if (end != null && (d == null || d.isAfter(end))) continue;
      has = true;
      amount += _num(movement['totalCostImpact']).abs();
    }
    return CogsKpi(
      amount: amount,
      sourceLabel: has ? 'Actual COGS (sale consumption movements)' : 'Actual COGS unavailable',
      isEstimated: false,
    );
  }

  static List<MenuProfitRow> menuProfitRows(
    List<Map<String, dynamic>> itemPerformance,
  ) {
    final rows = <MenuProfitRow>[];
    for (final item in itemPerformance) {
      final revenue = _num(item['revenue']);
      final qty = _num(item['quantitySold'] ?? item['quantity'] ?? item['count']);
      final unitCost = _num(item['costPerServing'] != 0 ? item['costPerServing'] : item['costPerUnit']);
      final hasCosting = unitCost > 0 && qty > 0;
      final estimatedCogs = hasCosting ? unitCost * qty : 0.0;
      rows.add(MenuProfitRow(
        item: item,
        revenue: revenue,
        estimatedCogs: estimatedCogs,
        profit: revenue - estimatedCogs,
        quantity: qty,
        hasCosting: hasCosting,
      ));
    }
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }

  static CogsKpi resolveCogs({
    required List<Map<String, dynamic>> stockMovements,
    required List<Map<String, dynamic>> itemPerformance,
    DateTime? start,
    DateTime? end,
  }) {
    final actual = actualCogsFromMovements(stockMovements, start: start, end: end);
    if (actual.sourceLabel.startsWith('Actual COGS (sale')) {
      return actual;
    }
    final estimated = menuProfitRows(itemPerformance)
        .where((r) => r.hasCosting)
        .fold<double>(0, (sum, r) => sum + r.estimatedCogs);
    return CogsKpi(
      amount: estimated,
      sourceLabel: 'Estimated COGS (recipe/menu costing fallback)',
      isEstimated: true,
    );
  }

  static PayablesKpi payablesKpi(
    List<Map<String, dynamic>> payables, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final dayStart = startOfDay(today);
    final weekEnd = dayStart.add(const Duration(days: 7));
    final monthEnd = DateTime(today.year, today.month + 1, 0, 23, 59, 59, 999);
    int dueToday = 0, dueThisWeek = 0, dueThisMonth = 0;
    for (final p in payables) {
      if (FinanceMetrics.isPaid(p)) continue;
      final due = FinanceFormat.asDate(p['dueDate']);
      if (due == null) continue;
      final d = startOfDay(due);
      if (d == dayStart) dueToday++;
      if (!d.isBefore(dayStart) && !d.isAfter(weekEnd)) dueThisWeek++;
      if (!d.isBefore(dayStart) && !d.isAfter(monthEnd)) dueThisMonth++;
    }
    return PayablesKpi(
      outstanding: FinanceMetrics.outstandingPayables(payables),
      overdue: FinanceMetrics.overdueAmount(payables, now: today),
      dueToday: dueToday,
      dueThisWeek: dueThisWeek,
      dueThisMonth: dueThisMonth,
      estimatedVariable: FinanceMetrics.estimatedOutstanding(payables),
    );
  }

  static ForecastKpi forecastKpi({
    required List<Map<String, dynamic>> salesForecast,
    required List<Map<String, dynamic>> menuProfitRowsData,
  }) {
    double revenue = 0;
    for (final point in salesForecast) {
      revenue += _num(point['predictedRevenue'] ?? point['predictedSales'] ?? point['revenue']);
    }
    final revenueBase = menuProfitRowsData.fold<double>(0, (s, r) => s + _num(r['revenue']));
    final cogsBase = menuProfitRowsData.fold<double>(0, (s, r) => s + _num(r['estimatedCogs']));
    final costRatio = revenueBase > 0 ? (cogsBase / revenueBase) : 0.0;
    final ingredientCost = revenue * costRatio;
    return ForecastKpi(
      forecastRevenue: revenue,
      forecastIngredientCost: ingredientCost,
      forecastProfit: revenue - ingredientCost,
      isEstimated: true,
    );
  }

  static Map<String, List<double>> dailyRevenueSeries(List<Map<String, dynamic>> orders, {int days = 30, DateTime? end}) {
    final endDay = startOfDay(end ?? DateTime.now());
    final startDay = endDay.subtract(Duration(days: days - 1));
    final map = <String, double>{};
    for (var i = 0; i < days; i++) {
      final d = startDay.add(Duration(days: i));
      map[FinanceFormat.date(d)] = 0;
    }
    for (final facts in completedOrderFacts(orders, start: startDay, end: endOfDay(endDay))) {
      final d = facts.date;
      if (d == null) continue;
      final key = FinanceFormat.date(startOfDay(d));
      if (!map.containsKey(key)) continue;
      map[key] = (map[key] ?? 0) + facts.netSales;
    }
    return {
      'values': map.values.toList(),
    };
  }
}
