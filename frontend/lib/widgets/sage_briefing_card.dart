import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/business_context.dart';

class SageBriefingContent {
  final String id;
  final String title;
  final String summary;
  final String periodLabel;
  final DateTime generatedAt;
  final String recommendation;
  final String businessHealth;
  final String detailText;
  final String period;

  const SageBriefingContent({
    required this.id,
    required this.title,
    required this.summary,
    required this.periodLabel,
    required this.generatedAt,
    required this.recommendation,
    required this.businessHealth,
    required this.detailText,
    required this.period,
  });

  factory SageBriefingContent.fromJson(Map<String, dynamic> json) {
    return SageBriefingContent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      periodLabel: (json['periodLabel'] ?? '').toString(),
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? '') ?? DateTime.now(),
      recommendation: (json['recommendation'] ?? '').toString(),
      businessHealth: (json['businessHealth'] ?? '').toString(),
      detailText: (json['detailText'] ?? '').toString(),
      period: (json['period'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'periodLabel': periodLabel,
        'generatedAt': generatedAt.toIso8601String(),
        'recommendation': recommendation,
        'businessHealth': businessHealth,
        'detailText': detailText,
        'period': period,
      };
}

class SageBriefingCard extends StatelessWidget {
  const SageBriefingCard({
    super.key,
    required this.content,
    required this.onDismiss,
    required this.onAskSage,
  });

  final SageBriefingContent content;
  final VoidCallback onDismiss;
  final VoidCallback onAskSage;

  static SageBriefingContent buildContent(
    BusinessContext ctx,
    String period, {
    bool backfill = false,
  }) {
    // A backfilled briefing (generated after its window passed) uses a
    // time-neutral greeting so a "morning" briefing made at 3pm isn't awkward.
    final greeting = backfill
        ? 'Hello'
        : switch (period) {
            'morning' => 'Good morning',
            'afternoon' => 'Good afternoon',
            'evening' => 'Good evening',
            _ => 'Hello',
          };
    final restaurantName = ctx.eateryName.isNotEmpty ? ctx.eateryName : 'your restaurant';

    final yesterdayRevenue = NumberFormat.currency(symbol: '₱', decimalDigits: 2)
        .format(ctx.yesterdayRevenue);
    final todayRevenue = NumberFormat.currency(symbol: '₱', decimalDigits: 2)
        .format(ctx.todayRevenue);
    final bestSeller = ctx.todayBestSeller == 'None' || ctx.todayBestSellerQty == 0
        ? 'No sales have been recorded yet today. I\'ll continue monitoring your business throughout the day.'
        : '${ctx.todayBestSeller} is leading today with ${ctx.todayBestSellerQty} sold.';

    final inventoryAlert = ctx.lowStockItems.isNotEmpty
        ? _formatInventoryAlert(ctx.lowStockItems)
        : 'Inventory is stable for now.';

    final revenueLine = ctx.dayChangePercent >= 0
        ? 'Revenue increased by ${ctx.dayChangePercent.toStringAsFixed(1)}% compared with yesterday.'
        : 'Today\'s revenue is lower than yesterday. Consider highlighting combo meals during the next rush.';

    final forecastLine = ctx.salesForecast.isNotEmpty
        ? 'The forecast points to ${NumberFormat.currency(symbol: '₱', decimalDigits: 0).format((ctx.salesForecast.first['predictedRevenue'] as num?)?.toDouble() ?? ctx.todayRevenue)} for the next peak window.'
        : 'I\'ll keep tracking demand and update you as the forecast changes.';

    final recommendation = _buildRecommendation(ctx, period);
    final summary = [
      '$greeting, $restaurantName. Yesterday you brought in $yesterdayRevenue across the day. $revenueLine',
      '$bestSeller $forecastLine',
      '$inventoryAlert',
      'Most important recommendation: $recommendation',
    ].join('\n\n');

    final detailText = [
      'Date: ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
      'Time: ${DateFormat('h:mm a').format(DateTime.now())}',
      'Yesterday Summary: $yesterdayRevenue in sales and $revenueLine',
      'Today\'s Forecast: $forecastLine',
      'Business Health: ${ctx.healthLabel} (${ctx.healthScore.toStringAsFixed(0)}/100)',
      'Revenue: ${NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(ctx.todayRevenue)}',
      'Orders: ${ctx.todayOrderCount}',
      'Best Seller: ${ctx.todayBestSeller == 'None' ? 'No sales yet' : ctx.todayBestSeller}',
      'Peak Hours: ${ctx.peakHour == 'N/A' ? 'Not available' : ctx.peakHour}',
      'Inventory Alerts: $inventoryAlert',
      'Recommendations: $recommendation',
    ].join('\n');

    return SageBriefingContent(
      id: '${period}_${DateTime.now().millisecondsSinceEpoch}',
      title: '$greeting, $restaurantName',
      summary: summary,
      periodLabel: _periodLabel(period),
      generatedAt: DateTime.now(),
      recommendation: recommendation,
      businessHealth: '${ctx.healthLabel} (${ctx.healthScore.toStringAsFixed(0)}/100)',
      detailText: detailText,
      period: period,
    );
  }

  static String _formatInventoryAlert(List<Map<String, dynamic>> items) {
    final critical = items.where((item) => item['isCritical'] == true).toList();
    if (critical.isNotEmpty) {
      final lead = critical.first['name'] as String? ?? 'Key item';
      return '$lead is running critically low and should be restocked before tomorrow.';
    }
    final lead = items.first['name'] as String? ?? 'Key item';
    return '$lead is low, so keep an eye on reordering before the next rush.';
  }

  static String _buildRecommendation(BusinessContext ctx, String period) {
    if (period == 'morning') {
      if (ctx.lowStockItems.isNotEmpty) {
        final first = ctx.lowStockItems.first['name'] as String? ?? 'inventory';
        return 'Start the morning with a quick stock check on $first and confirm prep for the first rush.';
      }
      return 'Keep the team focused on prep for the lunch rush and make sure your top seller is fully stocked.';
    }

    if (period == 'afternoon') {
      if (ctx.todayBestSeller != 'None' && ctx.todayBestSellerQty > 0) {
        return 'Lean into ${ctx.todayBestSeller} during the dinner push and keep service fast while demand is rising.';
      }
      return 'Use the next hour to adjust staffing and upsell add-ons before dinner starts.';
    }

    if (ctx.todayBestSeller != 'None' && ctx.todayBestSellerQty > 0) {
      return 'Finish strong by reinforcing ${ctx.todayBestSeller} and reviewing tomorrow\'s prep list before close.';
    }
    return 'Close on a strong note by locking in tomorrow\'s prep and restock plan before you leave.';
  }

  static String _periodLabel(String period) {
    return switch (period) {
      'morning' => 'Morning briefing',
      'afternoon' => 'Afternoon update',
      'evening' => 'Closing briefing',
      _ => 'Briefing',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content.periodLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              content.summary,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAskSage,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Ask Sage'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
