import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../../../widgets/dashboard/empty_state.dart';
import '../../../../widgets/dashboard/section_card.dart';
import '../../data/business_kpis.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'cashflow_trend_chart.dart';
import 'finance_category_bar.dart';
import 'finance_kpi_grid.dart';
import 'finance_status.dart';

class FinanceOverviewTab extends StatelessWidget {
  const FinanceOverviewTab({
    super.key,
    required this.expenses,
    required this.payables,
    required this.orders,
    this.itemPerformance = const [],
    this.dailySales = const [],
    this.stockMovements = const [],
    this.inventoryItems = const [],
    this.damagedItems = const [],
    this.salesForecast = const [],
    required this.isAdmin,
    required this.isLoading,
    required this.fmt,
    required this.onOpenExpenses,
    required this.onOpenPayables,
    required this.onAddExpense,
    required this.onAddPayable,
    required this.onOpenExpense,
    required this.onOpenPayable,
    required this.onExport,
  });

  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> payables;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> itemPerformance;
  final List<Map<String, dynamic>> dailySales;
  final List<Map<String, dynamic>> stockMovements;
  final List<Map<String, dynamic>> inventoryItems;
  final List<Map<String, dynamic>> damagedItems;
  final List<Map<String, dynamic>> salesForecast;
  final bool isAdmin;
  final bool isLoading;
  final FinanceFormat fmt;
  final VoidCallback onOpenExpenses;
  final VoidCallback onOpenPayables;
  final VoidCallback onAddExpense;
  final VoidCallback onAddPayable;
  final VoidCallback onExport;
  final ValueChanged<Map<String, dynamic>> onOpenExpense;
  final ValueChanged<Map<String, dynamic>> onOpenPayable;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = BusinessKpis.startOfMonth(now);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final prevStart = DateTime(now.year, now.month - 1, 1);
    final prevEnd = DateTime(prevStart.year, prevStart.month + 1, 0, 23, 59, 59, 999);
    final monthSales = BusinessKpis.summarizeOrders(orders, start: monthStart, end: monthEnd);
    final prevSales = BusinessKpis.summarizeOrders(orders, start: prevStart, end: prevEnd);
    final revenueGrowth = prevSales.revenue > 0 ? ((monthSales.revenue - prevSales.revenue) / prevSales.revenue) * 100 : null;
    final operating = BusinessKpis.operatingExpenses(expenses, start: monthStart, end: monthEnd);
    final prevOperating = BusinessKpis.operatingExpenses(expenses, start: prevStart, end: prevEnd);
    final expenseGrowth = prevOperating > 0 ? ((operating - prevOperating) / prevOperating) * 100 : null;
    final menuRows = BusinessKpis.menuProfitRows(itemPerformance);
    final cogs = BusinessKpis.resolveCogs(stockMovements: stockMovements, itemPerformance: itemPerformance, start: monthStart, end: monthEnd);
    final grossProfit = monthSales.revenue - cogs.amount;
    final netProfit = grossProfit - operating;
    final grossMarginPct = monthSales.revenue > 0 ? (grossProfit / monthSales.revenue) * 100 : 0.0;
    final foodCostPct = monthSales.revenue > 0 ? (cogs.amount / monthSales.revenue) * 100 : 0.0;
    final profitMarginPct = monthSales.revenue > 0 ? (netProfit / monthSales.revenue) * 100 : 0.0;
    final expensePct = monthSales.revenue > 0 ? (operating / monthSales.revenue) * 100 : 0.0;
    final payableKpi = BusinessKpis.payablesKpi(payables, now: now);
    final inventoryKpi = BusinessKpis.inventoryKpi(inventoryItems: inventoryItems, damagedItems: damagedItems, stockMovements: stockMovements, start: monthStart, end: monthEnd);
    final forecast = BusinessKpis.forecastKpi(salesForecast: salesForecast, menuProfitRowsData: menuRows.map((r) => {'revenue': r.revenue, 'estimatedCogs': r.estimatedCogs}).toList());
    final prevProfit = prevSales.revenue - prevOperating;
    final profitGrowth = prevProfit.abs() > 0.0001 ? ((netProfit - prevProfit) / prevProfit.abs()) * 100 : null;
    final dueBills = FinanceMetrics.upcomingPayables(payables, days: 30);
    final trend = FinanceMetrics.dailyTrend(expenses, days: 14);
    final trendPoints = [for (final e in trend) CashflowPoint(label: '${e.key.day}', value: e.value)];
    final categoryData = FinanceMetrics.expensesByCategory(expenses.where((e) {
      final d = FinanceMetrics.expenseDate(e);
      return d != null && !d.isBefore(monthStart) && d.isBefore(monthEnd.add(const Duration(milliseconds: 1)));
    }).toList());
    final recent = [...expenses]..sort((a, b) {
      final ad = FinanceMetrics.expenseDate(a);
      final bd = FinanceMetrics.expenseDate(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    final bestSelling = menuRows.isEmpty ? null : menuRows.reduce((a, b) => a.quantity >= b.quantity ? a : b);
    final highestRevenue = menuRows.isEmpty ? null : menuRows.first;
    final highestProfit = menuRows.where((r) => r.hasCosting).toList()..sort((a, b) => b.profit.compareTo(a.profit));
    final lowProfit = menuRows.where((r) => r.hasCosting && r.revenue > 0 && r.marginPercent < 25).toList()..sort((a, b) => a.marginPercent.compareTo(b.marginPercent));
    final menuCosting = _menuCostingForCurrentMonth(now);

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          FinanceKpiGrid(kpis: [
            FinanceKpi(title: 'Revenue (MTD)', value: fmt.money(monthSales.revenue), icon: Icons.payments_outlined, color: AppTheme.primary, trendPercent: revenueGrowth, subtitle: 'Net sales from completed orders', description: 'Net sales for the current month from completed/paid orders. Separate from Gross Sales (before discounts).'),
            FinanceKpi(title: 'Gross Sales', value: fmt.money(monthSales.grossSales), icon: Icons.point_of_sale_outlined, color: const Color(0xFF2563EB), subtitle: 'Discounts ${fmt.money(monthSales.discounts)} (fallback if missing)', description: 'Sales before discounts. Discounts are read from order fields when available; if missing, they are inferred or treated as zero for backward compatibility.'),
            FinanceKpi(title: 'Net Profit', value: fmt.money(netProfit), icon: Icons.savings_outlined, color: netProfit >= 0 ? const Color(0xFF16A34A) : AppTheme.error, trendPercent: profitGrowth, subtitle: 'After ${cogs.isEstimated ? "estimated" : "actual"} COGS + operating expenses', description: 'Net sales minus COGS and operating expenses. COGS uses Actual sale-consumption stock movements when available; otherwise falls back to Estimated COGS from recipe/menu costing and is labeled clearly.'),
            FinanceKpi(title: 'Profit Margin', value: '${profitMarginPct.toStringAsFixed(1)}%', icon: Icons.percent_rounded, color: profitMarginPct >= 0 ? const Color(0xFF16A34A) : AppTheme.error, subtitle: 'Gross ${grossMarginPct.toStringAsFixed(1)}% / Food ${foodCostPct.toStringAsFixed(1)}%', description: 'Net profit as a percentage of net sales. Also shows gross margin and food cost percentage based on the current COGS source.'),
            FinanceKpi(title: 'Operating Expenses', value: fmt.money(operating), icon: Icons.account_balance_wallet_outlined, color: AppTheme.warning, trendPercent: expenseGrowth, subtitle: 'Expense % ${expensePct.toStringAsFixed(1)} of net sales', description: 'Month-to-date operating expenses using an expense-category heuristic (e.g., rent/utilities/wages). Inventory purchases and non-operating entries are treated separately where identifiable.'),
            FinanceKpi(title: 'Inventory Value', value: fmt.money(inventoryKpi.inventoryValue), icon: Icons.inventory_2_outlined, color: const Color(0xFF0EA5A4), subtitle: 'Waste MTD ${fmt.money(inventoryKpi.wasteCost)}', description: 'Current on-hand inventory value from inventory item quantities and unit costs, plus month-to-date waste cost from damaged/write-off records when available.'),
            FinanceKpi(title: 'Bills Due / Payables', value: fmt.money(payableKpi.outstanding), icon: Icons.receipt_long_outlined, color: AppTheme.warning, subtitle: 'Due wk/mo ${payableKpi.dueThisWeek}/${payableKpi.dueThisMonth} • Overdue ${fmt.money(payableKpi.overdue)}', onTap: onOpenPayables, description: 'Outstanding payable balance, including overdue bills and counts due this week/month. Uses actual amounts when present and estimated values only as fallback.'),
            FinanceKpi(title: 'Forecast (30d)', value: fmt.money(forecast.forecastRevenue), icon: Icons.auto_graph_rounded, color: const Color(0xFF8B5CF6), subtitle: 'Est. profit ${fmt.money(forecast.forecastProfit)}', description: 'Forecast revenue for the next 30 days. Ingredient cost and profit are estimates derived from menu-costing/COGS ratios and are labeled separately from actual results.'),
          ]),
          const SizedBox(height: 16),
          SectionCard(title: 'P&L / COGS Snapshot (MTD)', icon: Icons.insights_outlined, iconColor: AppTheme.primary, badge: cogs.sourceLabel, child: Wrap(spacing: 10, runSpacing: 10, children: [
            _Metric(label: 'Net Sales / Revenue', value: fmt.money(monthSales.revenue), color: AppTheme.primary, description: 'Net sales for the month from completed/paid orders (after discounts where available).'),
            _Metric(label: 'Discounts', value: fmt.money(monthSales.discounts), color: AppTheme.warning, description: 'Total discounts for the month. Uses order discount fields when available; otherwise infers/falls back safely.'),
            _Metric(label: 'COGS', value: fmt.money(cogs.amount), color: const Color(0xFFEF4444), description: 'Cost of goods sold. Uses Actual sale-consumption stock movements when available; otherwise Estimated recipe/menu costing.'),
            _Metric(label: 'Gross Profit', value: fmt.money(grossProfit), color: grossProfit >= 0 ? const Color(0xFF16A34A) : AppTheme.error, description: 'Net sales minus COGS for the month.'),
            _Metric(label: 'Net Profit', value: fmt.money(netProfit), color: netProfit >= 0 ? const Color(0xFF16A34A) : AppTheme.error, description: 'Gross profit minus operating expenses.'),
            _Metric(label: 'AOV', value: fmt.money(monthSales.averageOrderValue), color: AppTheme.primary, description: 'Average Order Value: net sales divided by number of completed orders.'),
            _Metric(label: 'Avg Item Selling Price', value: fmt.money(monthSales.averageSellingPricePerItem), color: const Color(0xFF2563EB), description: 'Average selling price per sold item unit, based on available order item data.'),
            _Metric(label: 'Inventory Consumption', value: inventoryKpi.hasActualConsumption ? '${inventoryKpi.consumptionQty.toStringAsFixed(1)} units • ${fmt.money(inventoryKpi.consumptionCost)}' : 'No sale-consumption movements', color: const Color(0xFF0EA5A4)),
            _Metric(label: 'Forecast Ingredient Cost', value: fmt.money(forecast.forecastIngredientCost), color: AppTheme.warning, description: 'Estimated ingredient cost for the forecast period, derived from menu-costing/COGS ratios.'),
          ])),
          const SizedBox(height: 16),
          SectionCard(title: 'Gross Margin (by Menu Costing)', icon: Icons.restaurant_menu_rounded, iconColor: const Color(0xFF16A34A), badge: 'Separate from Actual COGS', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recipe/menu costing margin. Actual COGS above uses stock-movement COGS when available and recipe-cost fallback.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Metric(label: 'Gross revenue', value: fmt.money(menuCosting.revenue), color: const Color(0xFF16A34A), description: 'Revenue used by the menu-costing margin view for the current month.'),
              _Metric(label: 'Est. COGS (recipe)', value: fmt.money(menuCosting.estimatedCogs), color: AppTheme.warning, description: 'Estimated COGS from recipe/unit costing for costed menu items. Separate from Actual COGS.'),
              _Metric(label: 'Gross margin', value: fmt.money(menuCosting.grossMargin), color: menuCosting.grossMargin >= 0 ? const Color(0xFF16A34A) : AppTheme.error, description: 'Gross Margin (by Menu Costing): revenue minus estimated recipe/unit COGS. Separate from Actual COGS.'),
              _Metric(label: 'Coverage', value: '${menuCosting.withCosting}/${itemPerformance.length} items', color: AppTheme.primary, description: 'How many menu/performance items have recipe or unit costing available for margin estimates.'),
            ]),
          ])),
          const SizedBox(height: 16),
          SectionCard(title: 'Top / Low-Profit Menu Items', icon: Icons.restaurant_menu_rounded, iconColor: const Color(0xFF16A34A), badge: 'Recipe costing when available', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (bestSelling != null) _MenuRow(label: 'Best selling', name: (bestSelling.item['name'] ?? '').toString(), detail: '${bestSelling.quantity.toStringAsFixed(0)} sold • ${fmt.money(bestSelling.revenue)}'),
            if (highestRevenue != null) _MenuRow(label: 'Highest revenue', name: (highestRevenue.item['name'] ?? '').toString(), detail: fmt.money(highestRevenue.revenue)),
            if (highestProfit.isNotEmpty) _MenuRow(label: 'Highest profit', name: (highestProfit.first.item['name'] ?? '').toString(), detail: '${fmt.money(highestProfit.first.profit)} (${highestProfit.first.marginPercent.toStringAsFixed(1)}%)'),
            if (lowProfit.isNotEmpty) _MenuRow(label: 'Low profit', name: (lowProfit.first.item['name'] ?? '').toString(), detail: '${fmt.money(lowProfit.first.profit)} (${lowProfit.first.marginPercent.toStringAsFixed(1)}%)', warn: true),
            if (menuRows.isEmpty) const EmptyState(icon: Icons.restaurant_menu_outlined, title: 'No menu performance data', subtitle: 'Complete orders to populate per-menu KPIs.'),
            if (menuRows.any((r) => !r.hasCosting)) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Some items lack recipe/unit costing; profit/COGS shown only where costing exists.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ])),
          const SizedBox(height: 16),
          SectionCard(title: 'Cash-out Trend', icon: Icons.show_chart_rounded, iconColor: AppTheme.primary, badge: 'Last 14 days', action: TextButton.icon(onPressed: onExport, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Export')), child: CashflowTrendChart(points: trendPoints, compactMoney: fmt.moneyCompact)),
          const SizedBox(height: 16),
          SectionCard(title: 'Expenses by Category', icon: Icons.pie_chart_outline_rounded, iconColor: const Color(0xFF8B5CF6), badge: 'This month', child: categoryData.isEmpty ? const EmptyState(icon: Icons.pie_chart_outline, title: 'No expenses this month', subtitle: 'Recorded expenses will be grouped here.') : Column(children: [for (final entry in categoryData.take(6)) FinanceCategoryBar(category: entry.key, amount: entry.value, percent: operating > 0 ? entry.value / operating * 100 : 0, color: financeCategoryColor(entry.key), money: fmt.money)])),
          const SizedBox(height: 16),
          SectionCard(title: 'Upcoming and Overdue Bills', icon: Icons.notifications_active_outlined, iconColor: AppTheme.warning, badge: '${dueBills.length}', action: TextButton(onPressed: onOpenPayables, child: const Text('View all')), child: dueBills.isEmpty ? const EmptyState(icon: Icons.check_circle_outline, title: 'No bills due soon', subtitle: 'You are all caught up.') : Column(children: [for (final p in dueBills.take(5)) _BillRow(payable: p, fmt: fmt, onTap: () => onOpenPayable(p))])),
          const SizedBox(height: 16),
          SectionCard(title: 'Recent Expenses', icon: Icons.history_rounded, iconColor: AppTheme.primary, action: TextButton(onPressed: onOpenExpenses, child: const Text('View all')), child: recent.isEmpty ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No expenses yet', subtitle: 'Add your first expense to get started.') : Column(children: [for (final e in recent.take(6)) _ExpenseRow(expense: e, fmt: fmt, onTap: () => onOpenExpense(e))])),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  _MenuCostingSummary _menuCostingForCurrentMonth(DateTime now) {
    double revenue = 0;
    for (final sale in dailySales) {
      final date = DateTime.tryParse(sale['date']?.toString() ?? '');
      if (date == null) continue;
      if (date.year != now.year || date.month != now.month) continue;
      revenue += (sale['revenue'] as num?)?.toDouble() ?? 0;
    }
    double estimatedCogs = 0;
    int withCosting = 0;
    for (final item in itemPerformance) {
      final costPerServing = (item['costPerServing'] as num?)?.toDouble() ?? (item['costPerUnit'] as num?)?.toDouble();
      final qty = (item['quantity'] as num?)?.toDouble() ?? (item['quantitySold'] as num?)?.toDouble() ?? (item['count'] as num?)?.toDouble() ?? 0;
      if (costPerServing != null && costPerServing > 0 && qty > 0) {
        estimatedCogs += costPerServing * qty;
        withCosting++;
      }
    }
    final grossMargin = revenue - estimatedCogs;
    final marginPct = revenue > 0 ? (grossMargin / revenue) * 100 : 0.0;
    return _MenuCostingSummary(revenue: revenue, estimatedCogs: estimatedCogs, grossMargin: grossMargin, marginPct: marginPct, withCosting: withCosting);
  }
}

class _MenuCostingSummary {
  const _MenuCostingSummary({required this.revenue, required this.estimatedCogs, required this.grossMargin, required this.marginPct, required this.withCosting});
  final double revenue;
  final double estimatedCogs;
  final double grossMargin;
  final double marginPct;
  final int withCosting;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color, this.description});
  final String label;
  final String value;
  final Color color;
  final String? description;
  @override
  Widget build(BuildContext context) {
    final child = Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
    return description == null ? child : Tooltip(message: description!, preferBelow: false, waitDuration: const Duration(milliseconds: 300), child: child);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, required this.name, required this.detail, this.warn = false});
  final String label;
  final String name;
  final String detail;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final color = warn ? AppTheme.warning : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
        Expanded(child: Text(name.isEmpty ? 'Unknown' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(detail, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.payable, required this.fmt, required this.onTap});
  final Map<String, dynamic> payable;
  final FinanceFormat fmt;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final name = (payable['name'] ?? 'Bill').toString();
    final amount = FinanceMetrics.amountOf(payable);
    final color = FinanceStatus.payable(payable);
    final label = FinanceStatus.payableLabel(payable);
    final days = FinanceMetrics.daysUntilDue(payable);
    String dueText = label;
    if (days != null) {
      if (days.inDays < 0) { dueText = '${days.inDays.abs()} days overdue'; }
      else if (days.inDays == 0) { dueText = 'Due today'; }
      else { dueText = 'Due in ${days.inDays} days'; }
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.receipt_long_outlined, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), Text(dueText, style: TextStyle(fontSize: 12, color: color))])),
          Text(amount > 0 ? fmt.money(amount) : (FinanceMetrics.estimatedAmountOf(payable) > 0 ? 'Est. ${fmt.money(FinanceMetrics.estimatedAmountOf(payable))}' : 'Variable'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.fmt, required this.onTap});
  final Map<String, dynamic> expense;
  final FinanceFormat fmt;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final name = (expense['name'] ?? '').toString();
    final category = (expense['category'] ?? '').toString();
    final amount = FinanceMetrics.amountOf(expense);
    final date = FinanceMetrics.expenseDate(expense);
    final linked = FinanceMetrics.isLinkedPurchase(expense);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: financeCategoryColor(category).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(financeCategoryIcon(category), size: 18, color: financeCategoryColor(category))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(name.trim().isEmpty ? (category.isEmpty ? 'Expense' : category) : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))), if (linked) ...[const SizedBox(width: 6), const Icon(Icons.link, size: 12, color: AppTheme.primary)]]),
            Text('${date == null ? '' : FinanceFormat.date(date)}${category.isEmpty ? '' : ' • $category'}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          Text(fmt.money(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}