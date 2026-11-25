import 'package:flutter/material.dart';

import '../../../../services/receipt_printer_service.dart';
import '../../../../services/report_pdf_service.dart';
import '../../../../theme.dart';
import '../../../../widgets/dashboard/empty_state.dart';
import '../../../../widgets/dashboard/section_card.dart';
import '../../data/business_kpis.dart';
import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';
import 'finance_category_pie_chart.dart';
import 'finance_kpi_grid.dart';

/// Monthly finance report with P&L, growth, menu profitability, COGS/waste and forecast.
class FinanceReportsTab extends StatefulWidget {
  const FinanceReportsTab({
    super.key,
    required this.expenses,
    required this.payables,
    this.orders = const [],
    this.itemPerformance = const [],
    this.stockMovements = const [],
    this.inventoryItems = const [],
    this.damagedItems = const [],
    this.salesForecast = const [],
    required this.fmt,
    required this.onEditBudgets,
  });

  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> payables;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> itemPerformance;
  final List<Map<String, dynamic>> stockMovements;
  final List<Map<String, dynamic>> inventoryItems;
  final List<Map<String, dynamic>> damagedItems;
  final List<Map<String, dynamic>> salesForecast;
  final FinanceFormat fmt;
  final VoidCallback onEditBudgets;

  @override
  State<FinanceReportsTab> createState() => _FinanceReportsTabState();
}

class _FinanceReportsTabState extends State<FinanceReportsTab> {
  int _monthOffset = 0;
  DateTime get _month {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset, 1);
  }

  String get _monthName =>
      '${FinanceFormat.monthLabel(_month.month)} ${_month.year}';

  Future<void> _runPdfAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open report: $e')),
      );
    }
  }

  List<String> _printerLines(List<ReportPdfSection> sections) {
    final lines = <String>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) lines.add(ReceiptPrinterService.documentDivider);
      lines.add('${ReceiptPrinterService.documentSection}${sections[i].title}');
      lines.addAll(sections[i].lines);
    }
    return lines;
  }

  Future<void> _printBluetoothReport(List<ReportPdfSection> sections) async {
    final result = await ReceiptPrinterService.printDocument(
      title: 'Financial Report',
      subtitle: _monthName,
      lines: _printerLines(sections),
      footer: 'SmartEat Financial Reports',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.printed
              ? 'Financial report sent to printer.'
              : result.error ?? 'Could not print financial report.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = BusinessKpis.startOfMonth(_month);
    final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59, 999);
    final prev = DateTime(_month.year, _month.month - 1, 1);
    final prevStart = BusinessKpis.startOfMonth(prev);
    final prevEnd = DateTime(prev.year, prev.month + 1, 0, 23, 59, 59, 999);

    final monthExpenses = widget.expenses.where((e) {
      final d = FinanceMetrics.expenseDate(e);
      return d != null && d.year == _month.year && d.month == _month.month;
    }).toList();
    final sales =
        BusinessKpis.summarizeOrders(widget.orders, start: start, end: end);
    final prevSales = BusinessKpis.summarizeOrders(widget.orders,
        start: prevStart, end: prevEnd);
    final operating =
        BusinessKpis.operatingExpenses(widget.expenses, start: start, end: end);
    final prevOperating = BusinessKpis.operatingExpenses(widget.expenses,
        start: prevStart, end: prevEnd);
    final cogs = BusinessKpis.resolveCogs(
        stockMovements: widget.stockMovements,
        itemPerformance: widget.itemPerformance,
        start: start,
        end: end);
    final grossProfit = sales.revenue - cogs.amount;
    final netProfit = grossProfit - operating;
    final prevProfit = prevSales.revenue - prevOperating;
    final revenueGrowth = prevSales.revenue > 0
        ? ((sales.revenue - prevSales.revenue) / prevSales.revenue) * 100
        : null;
    final expenseGrowth = prevOperating > 0
        ? ((operating - prevOperating) / prevOperating) * 100
        : null;
    final profitGrowth = prevProfit.abs() > 0.0001
        ? ((netProfit - prevProfit) / prevProfit.abs()) * 100
        : null;
    final inventoryKpi = BusinessKpis.inventoryKpi(
        inventoryItems: widget.inventoryItems,
        damagedItems: widget.damagedItems,
        stockMovements: widget.stockMovements,
        start: start,
        end: end);
    final payableKpi =
        BusinessKpis.payablesKpi(widget.payables, now: DateTime.now());
    final menuRows = BusinessKpis.menuProfitRows(widget.itemPerformance);
    final performanceRows =
        menuRows.where((r) => r.revenue > 0 || r.quantity > 0).toList();
    final forecast = BusinessKpis.forecastKpi(
        salesForecast: widget.salesForecast,
        menuProfitRowsData: menuRows
            .map(
                (r) => {'revenue': r.revenue, 'estimatedCogs': r.estimatedCogs})
            .toList());
    final categoryData = FinanceMetrics.expensesByCategory(monthExpenses);
    final grossMarginPct =
        sales.revenue > 0 ? (grossProfit / sales.revenue) * 100 : 0.0;
    final profitMarginPct =
        sales.revenue > 0 ? (netProfit / sales.revenue) * 100 : 0.0;
    final foodCostPct =
        sales.revenue > 0 ? (cogs.amount / sales.revenue) * 100 : 0.0;
    final expensePct =
        sales.revenue > 0 ? (operating / sales.revenue) * 100 : 0.0;

    String growthText(double? value) {
      if (value == null) return 'No prior-month comparison';
      return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
    }

    final reportSections = <ReportPdfSection>[
      ReportPdfSection(
        title: '$_monthName summary',
        lines: [
          'Revenue: ${widget.fmt.money(sales.revenue)}',
          'Orders: ${sales.ordersCount}',
          'Average order value: ${widget.fmt.money(sales.averageOrderValue)}',
          'Gross profit: ${widget.fmt.money(grossProfit)} (${grossMarginPct.toStringAsFixed(1)}%)',
          'Net profit: ${widget.fmt.money(netProfit)} (${profitMarginPct.toStringAsFixed(1)}%)',
          'Operating expenses: ${widget.fmt.money(operating)} (${expensePct.toStringAsFixed(1)}% of sales)',
          'COGS source: ${cogs.sourceLabel}',
        ],
      ),
      ReportPdfSection(
        title: 'Month-over-month',
        lines: [
          'Revenue growth: ${growthText(revenueGrowth)}',
          'Expense growth: ${growthText(expenseGrowth)}',
          'Profit growth: ${growthText(profitGrowth)}',
        ],
      ),
      ReportPdfSection(
        title: 'Costs and inventory',
        lines: [
          'Cost of goods sold: ${widget.fmt.money(cogs.amount)}',
          'Food cost ratio: ${foodCostPct.toStringAsFixed(1)}%',
          'Inventory value: ${widget.fmt.money(inventoryKpi.inventoryValue)}',
          'Consumption: ${inventoryKpi.consumptionQty.toStringAsFixed(2)} / ${widget.fmt.money(inventoryKpi.consumptionCost)}',
          'Waste: ${inventoryKpi.wasteQty.toStringAsFixed(2)} / ${widget.fmt.money(inventoryKpi.wasteCost)}',
          'Payables outstanding: ${widget.fmt.money(payableKpi.outstanding)}',
          'Payables overdue: ${widget.fmt.money(payableKpi.overdue)}',
        ],
      ),
      ReportPdfSection(
        title: 'Expenses by category',
        lines: categoryData.isEmpty
            ? ['No expenses recorded for $_monthName.']
            : [
                for (final entry in categoryData)
                  '${entry.key}: ${widget.fmt.money(entry.value)}',
              ],
      ),
      ReportPdfSection(
        title: 'Menu profitability',
        lines: performanceRows.isEmpty
            ? ['No menu performance data.']
            : [
                for (final row in performanceRows.take(10))
                  '${row.item['name'] ?? 'Unknown'} — sold ${row.quantity.toStringAsFixed(0)}, revenue ${widget.fmt.money(row.revenue)}, profit ${row.hasCosting ? widget.fmt.money(row.profit) : 'N/A'}',
              ],
      ),
      ReportPdfSection(
        title: 'Forecast',
        lines: [
          'Forecast revenue: ${widget.fmt.money(forecast.forecastRevenue)}',
          'Estimated ingredient cost: ${widget.fmt.money(forecast.forecastIngredientCost)}',
          'Estimated profit: ${widget.fmt.money(forecast.forecastProfit)}',
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      children: [
        Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  IconButton(
                      onPressed: () => setState(() => _monthOffset--),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Text(_monthName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold))),
                  IconButton(
                      onPressed: _monthOffset < 0
                          ? () => setState(() => _monthOffset++)
                          : null,
                      icon: const Icon(Icons.chevron_right))
                ]))),
        const SizedBox(height: 16),
        FinanceKpiGrid(kpis: [
          FinanceKpi(
              title: 'Revenue',
              value: widget.fmt.money(sales.revenue),
              icon: Icons.payments_outlined,
              color: AppTheme.sageAccent,
              trendPercent: revenueGrowth,
              subtitle:
                  'Orders ${sales.ordersCount} • AOV ${widget.fmt.money(sales.averageOrderValue)}'),
          FinanceKpi(
              title: 'Gross Profit',
              value: widget.fmt.money(grossProfit),
              icon: Icons.trending_up_rounded,
              color: grossProfit >= 0 ? AppTheme.sageSuccess : scheme.error,
              subtitle:
                  '${grossMarginPct.toStringAsFixed(1)}% • ${cogs.sourceLabel}'),
          FinanceKpi(
              title: 'Net Profit',
              value: widget.fmt.money(netProfit),
              icon: Icons.savings_outlined,
              color: netProfit >= 0 ? AppTheme.sageSuccess : scheme.error,
              trendPercent: profitGrowth,
              subtitle: 'Margin ${profitMarginPct.toStringAsFixed(1)}%',
              description:
                  'Gross profit minus operating expenses for the selected month. Uses the same COGS source shown in Gross Profit.'),
          FinanceKpi(
              title: 'Operating Expenses',
              value: widget.fmt.money(operating),
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.warning,
              trendPercent: expenseGrowth,
              subtitle: '${expensePct.toStringAsFixed(1)}% of net sales',
              description:
                  'Operating expenses for the selected month using an expense-category heuristic; inventory purchases/non-operating entries are treated separately when identifiable.'),
        ]),
        const SizedBox(height: 16),
        SectionCard(
            title: 'Profit & Loss (Monthly)',
            icon: Icons.receipt_long_rounded,
            iconColor: AppTheme.sageAccent,
            badge: _monthName,
            child: Column(children: [
              _RowLine(
                  label: 'Gross Sales',
                  value: widget.fmt.money(sales.grossSales)),
              _RowLine(
                  label: 'Discounts (backward-compatible)',
                  value: '- ${widget.fmt.money(sales.discounts)}'),
              _RowLine(
                  label: 'Net Sales / Revenue',
                  value: widget.fmt.money(sales.revenue),
                  strong: true),
              _RowLine(
                  label: 'COGS (${cogs.sourceLabel})',
                  value: '- ${widget.fmt.money(cogs.amount)}'),
              _RowLine(
                  label: 'Gross Profit',
                  value: widget.fmt.money(grossProfit),
                  strong: true,
                  valueColor:
                      grossProfit >= 0 ? AppTheme.sageSuccess : scheme.error),
              _RowLine(
                  label: 'Operating Expenses',
                  value: '- ${widget.fmt.money(operating)}'),
              _RowLine(
                  label: 'Net Profit',
                  value: widget.fmt.money(netProfit),
                  strong: true,
                  valueColor:
                      netProfit >= 0 ? AppTheme.sageSuccess : scheme.error),
              const SizedBox(height: 8),
              Text(
                  'Gross Margin (by Menu Costing) is separate from Actual COGS. Food cost ${foodCostPct.toStringAsFixed(1)}% • Expense % ${expensePct.toStringAsFixed(1)}%.',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ])),
        const SizedBox(height: 16),
        SectionCard(
            title: 'Inventory / Payables / Forecast KPIs',
            icon: Icons.inventory_2_outlined,
            iconColor: const Color(0xFF2DD4BF),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              _Mini(
                  label: 'Inventory Value',
                  value: widget.fmt.money(inventoryKpi.inventoryValue),
                  description:
                      'Current on-hand inventory value from quantities and unit costs.'),
              _Mini(
                  label: 'Inventory Waste',
                  value: widget.fmt.money(inventoryKpi.wasteCost),
                  description:
                      'Month-to-date waste cost from damaged/write-off records when available.'),
              _Mini(
                  label: 'Consumption',
                  value: inventoryKpi.hasActualConsumption
                      ? '${inventoryKpi.consumptionQty.toStringAsFixed(1)} • ${widget.fmt.money(inventoryKpi.consumptionCost)}'
                      : 'No actual movements'),
              _Mini(
                  label: 'Outstanding Payables',
                  value: widget.fmt.money(payableKpi.outstanding),
                  description:
                      'Total unpaid payables, including overdue and upcoming bills.'),
              _Mini(
                  label: 'Due Today/Week/Month',
                  value:
                      '${payableKpi.dueToday}/${payableKpi.dueThisWeek}/${payableKpi.dueThisMonth}',
                  description:
                      'Number of payable bills due today, this week, and this month.'),
              _Mini(
                  label: 'Forecast Revenue (30d)',
                  value: widget.fmt.money(forecast.forecastRevenue),
                  description:
                      'Forecast revenue for the next 30 days from sales forecast data.'),
              _Mini(
                  label: 'Forecast Ingredient Cost',
                  value: widget.fmt.money(forecast.forecastIngredientCost),
                  description:
                      'Estimated ingredient cost for the forecast period, derived from menu-costing/COGS ratios.'),
              _Mini(
                  label: 'Forecast Profit',
                  value: widget.fmt.money(forecast.forecastProfit),
                  description:
                      'Estimated forecast profit (forecast revenue minus estimated ingredient cost). This is an estimate, not actual profit.'),
            ])),
        const SizedBox(height: 16),
        SectionCard(
            title: 'Menu Profitability (Recipe & Direct Stock Costing)',
            icon: Icons.restaurant_menu_rounded,
            iconColor: AppTheme.sageSuccess,
            badge: 'Estimates when recipe or linked-stock costing exists',
            child: performanceRows.isEmpty
                ? const EmptyState(
                    icon: Icons.restaurant_menu_outlined,
                    title: 'No menu performance data',
                    subtitle: 'Complete orders to populate per-menu KPIs.')
                : Column(children: [
                    for (final row in performanceRows.take(12))
                      _MenuProfit(row: row, fmt: widget.fmt)
                  ])),
        const SizedBox(height: 16),
        SectionCard(
            title: 'Expenses by Category',
            icon: Icons.pie_chart_outline_rounded,
            iconColor: const Color(0xFFA78BFA),
            badge: _monthName,
            action: TextButton.icon(
                onPressed: widget.onEditBudgets,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Budgets')),
            child: categoryData.isEmpty
                ? EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: 'No expenses for $_monthName',
                    subtitle: 'Nothing recorded in this month.')
                : FinanceCategoryPieChart(
                    data: categoryData.take(6).toList(),
                    money: widget.fmt.money)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('finance-bluetooth-print-button'),
              onPressed: () => _printBluetoothReport(reportSections),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print PDF via Bluetooth printer'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('finance-download-pdf-button'),
              onPressed: () => _runPdfAction(() => ReportPdfService.shareReport(
                    title: 'Financial Report',
                    subtitle: _monthName,
                    filePrefix: 'financial_report',
                    sections: reportSections,
                    footer: 'SmartEat Financial Reports',
                  )),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download PDF'),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _RowLine extends StatelessWidget {
  const _RowLine(
      {required this.label,
      required this.value,
      this.strong = false,
      this.valueColor});
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500))),
        Text(value,
            style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                color: valueColor))
      ]));
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.description});
  final String label;
  final String value;
  final String? description;
  @override
  Widget build(BuildContext context) {
    final child = Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800))
        ]));
    return description == null
        ? child
        : Tooltip(
            message: description!,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 300),
            child: child);
  }
}

class _MenuProfit extends StatelessWidget {
  const _MenuProfit({required this.row, required this.fmt});
  final MenuProfitRow row;
  final FinanceFormat fmt;
  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text((row.item['name'] ?? 'Unknown').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    'Sold ${row.quantity.toStringAsFixed(0)} • Rev ${fmt.money(row.revenue)}${row.hasCosting ? " • Profit/item ${fmt.money(row.profitPerItem)}" : " • Costing missing"}',
                    style: TextStyle(
                        fontSize: 12,
                        color: row.hasCosting
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : errorColor))
              ])),
          Text(
              row.hasCosting
                  ? '${fmt.money(row.profit)} (${row.marginPercent.toStringAsFixed(1)}%)'
                  : 'N/A',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: !row.hasCosting
                      ? errorColor
                      : (row.profit >= 0 ? AppTheme.sageSuccess : errorColor)))
        ]));
  }
}
