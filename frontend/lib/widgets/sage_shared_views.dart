import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';
import '../services/auth_provider.dart';
import '../services/briefing_history.dart';
import '../services/sage_briefing_pdf_service.dart';
import 'insight_card.dart';
import 'sage_briefing_card.dart';

// Shared Sage content views used by both the side panel (AISidePanel) and the
// immersive full-screen workspace (SageFullScreen). Keeping them here avoids
// duplicating the summary / history rendering across the two modes.

// ── Identity ──────────────────────────────────────────────────────────────

String sageGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// Resolves the user's first name: profile firstName → profile name →
/// Firebase displayName → email local part. Returns '' when nothing is found.
Future<String> loadSageDisplayName(BuildContext context) async {
  try {
    final auth = context.read<AuthProvider>();
    final profile = await auth.getCurrentUserProfile();
    if (profile != null) {
      final firstName =
          (profile['firstName'] ?? profile['name'] ?? '').toString().trim();
      if (firstName.isNotEmpty) return firstName;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return user.displayName ?? user.email?.split('@')[0] ?? '';
    }
  } catch (_) {}
  return '';
}

// ── Summary views ──────────────────────────────────────────────────────────

Widget buildLatestBriefingCard(SageBriefingContent briefing) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              briefingPeriodEmoji(briefing.period),
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                briefing.periodLabel.isNotEmpty
                    ? briefing.periodLabel
                    : '${briefingPeriodShortLabel(briefing.period)} briefing',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                briefing.businessHealth,
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          DateFormat('MMM d, yyyy • h:mm a').format(briefing.generatedAt),
          style: const TextStyle(color: Colors.white38, fontSize: 10.5),
        ),
        const SizedBox(height: 12),
        SelectableText(
          briefing.summary,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
        if (briefing.recommendation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Main recommendation',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  briefing.recommendation,
                  style: TextStyle(
                    color: Colors.greenAccent.shade100,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildSummarySection(AIAssistantProvider provider) {
  final summary = provider.businessSummary;
  if (provider.loadingSummary && summary.isEmpty) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  final double todayRev = (summary['todayRevenue'] as num?)?.toDouble() ?? 0.0;
  final int todayOrders = (summary['todayOrdersCount'] as num?)?.toInt() ?? 0;
  final int pendingOrders = (summary['pendingOrdersCount'] as num?)?.toInt() ?? 0;
  final int lowStock = (summary['lowStockCount'] as num?)?.toInt() ?? 0;
  final String topSeller = (summary['topSeller'] as String?) ?? 'None';
  final double weekRev = (summary['weekRevenue'] as num?)?.toDouble() ?? 0.0;
  final double dayChange = (summary['dayChangePercent'] as num?)?.toDouble() ?? 0.0;
  final double aov = (summary['averageOrderValue'] as num?)?.toDouble() ?? 0.0;
  final double healthScore = (summary['healthScore'] as num?)?.toDouble() ?? 0.0;
  final String healthLabel = (summary['healthLabel'] as String?) ?? '';
  final String trendDir = (summary['trendDirection'] as String?) ?? 'stable';
  final double monthGrowth = (summary['monthlyGrowthPercent'] as num?)?.toDouble() ?? 0.0;
  final String peakHour = (summary['peakHour'] as String?) ?? 'N/A';
  final String bestDay = (summary['bestDayOfWeek'] as String?) ?? 'N/A';

  final dayChangeLabel = dayChange >= 0
      ? '+${dayChange.toStringAsFixed(1)}%'
      : '${dayChange.toStringAsFixed(1)}%';
  final dayChangeColor = dayChange >= 0 ? Colors.greenAccent : Colors.redAccent;
  final trendIcon = trendDir == 'improving'
      ? Icons.trending_up
      : trendDir == 'declining'
          ? Icons.trending_down
          : Icons.trending_flat;
  final trendColor = trendDir == 'improving'
      ? Colors.greenAccent
      : trendDir == 'declining'
          ? Colors.redAccent
          : Colors.blueGrey;

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "TODAY'S SNAPSHOT",
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            if (healthLabel.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _healthColor(healthScore).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _healthColor(healthScore).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${healthScore.toStringAsFixed(0)} · $healthLabel',
                  style: TextStyle(
                    color: _healthColor(healthScore),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Revenue + change ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Revenue',
                '₱${todayRev.toStringAsFixed(0)}',
                Icons.monetization_on,
                Colors.green,
                badge: dayChangeLabel,
                badgeColor: dayChangeColor,
              ),
            ),
            Expanded(
              child: _buildMetricTile(
                'Orders',
                '$todayOrders',
                Icons.receipt_long,
                Colors.blue,
                badge: aov > 0 ? '₱${aov.toStringAsFixed(0)} avg' : null,
                badgeColor: Colors.blueAccent.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Pending',
                '$pendingOrders',
                Icons.hourglass_bottom,
                Colors.orange,
              ),
            ),
            Expanded(
              child: _buildMetricTile(
                'Low Stock',
                '$lowStock',
                Icons.warning,
                lowStock > 0 ? Colors.redAccent : Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'This Week',
                '₱${weekRev.toStringAsFixed(0)}',
                Icons.date_range_rounded,
                Colors.teal,
              ),
            ),
            Expanded(
              child: _buildMetricTile(
                '14-Day Trend',
                trendDir[0].toUpperCase() + trendDir.substring(1),
                trendIcon,
                trendColor,
              ),
            ),
          ],
        ),

        // ── Divider + bottom row ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(color: Colors.white.withValues(alpha: 0.08)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (topSeller != 'None')
              _buildChip(Icons.star_rounded, topSeller, Colors.amber),
            if (peakHour != 'N/A')
              _buildChip(Icons.access_time_rounded, 'Peak: $peakHour',
                  Colors.blueAccent),
            if (bestDay != 'N/A')
              _buildChip(Icons.calendar_today_rounded, 'Best: $bestDay',
                  Colors.purple),
            if (monthGrowth != 0)
              _buildChip(
                monthGrowth >= 0
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                'MTD ${monthGrowth >= 0 ? '+' : ''}${monthGrowth.toStringAsFixed(1)}%',
                monthGrowth >= 0 ? Colors.greenAccent : Colors.redAccent,
              ),
          ],
        ),
      ],
    ),
  );
}

Widget buildInsightsSection(AIAssistantProvider provider) {
  if (provider.loadingInsights && provider.activeInsights.isEmpty) {
    return const SizedBox(
      height: 60,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  final insights = provider.activeInsights;
  if (insights.isEmpty) return const SizedBox();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${provider.activePage.toUpperCase()} ALERTS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => provider.refreshData(),
            icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha: 0.38), size: 14),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ...insights.map((insight) => InsightCard(insight: insight)),
    ],
  );
}

Widget _buildMetricTile(String label, String value, IconData icon, Color color,
    {String? badge, Color? badgeColor}) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor ?? Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildChip(IconData icon, String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color.withValues(alpha: 0.85), size: 11),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

Color _healthColor(double score) {
  if (score >= 80) return Colors.greenAccent;
  if (score >= 60) return Colors.lightGreen;
  if (score >= 40) return Colors.orange;
  return Colors.redAccent;
}

// ── History views ──────────────────────────────────────────────────────────

/// Builds the report-history content (generate-missed button + date groups).
/// Callers wrap the returned widgets in their own scrollable.
List<Widget> buildBriefingHistoryContent(
    BuildContext context, AIAssistantProvider provider) {
  final grouped = groupBriefingsByDate(provider.briefingHistory);
  final dateKeys = sortedBriefingDateKeysDesc(grouped);
  final showGenerate = provider.hasMissingBriefingsToday;

  if (dateKeys.isEmpty && !showGenerate) {
    return const [
      SizedBox(
        height: 240,
        child: Center(
          child: Text(
            'No Sage Briefings yet.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    ];
  }

  return [
    if (showGenerate) _buildGenerateMissedButton(context, provider),
    for (var i = 0; i < dateKeys.length; i++)
      _buildBriefingDateGroup(
        context,
        dateKeys[i],
        grouped[dateKeys[i]]!,
        initiallyExpanded: i == 0,
      ),
  ];
}

Widget _buildGenerateMissedButton(
    BuildContext context, AIAssistantProvider provider) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () async {
          final count = await provider.generateMissingBriefings();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                count > 0
                    ? 'Generated $count missed briefing${count == 1 ? '' : 's'}.'
                    : 'No missed briefings to generate.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.auto_awesome, size: 16),
        label: const Text('Generate missed briefings'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.blueAccent.shade100,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

Widget _buildBriefingDateGroup(
  BuildContext context,
  String dateKey,
  List<SageBriefingContent> briefings, {
  required bool initiallyExpanded,
}) {
  final now = DateTime.now();
  final todayKey = briefingDateKey(now);
  final yesterdayKey =
      briefingDateKey(now.subtract(const Duration(days: 1)));
  final relative = dateKey == todayKey
      ? 'Today'
      : dateKey == yesterdayKey
          ? 'Yesterday'
          : '';

  final labels = <String>[];
  for (final briefing in briefings) {
    final label = briefingPeriodShortLabel(briefing.period);
    if (!labels.contains(label)) labels.add(label);
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('sage_briefing_$dateKey'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
        backgroundColor: Colors.white.withValues(alpha: 0.03),
        collapsedBackgroundColor: Colors.white.withValues(alpha: 0.03),
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
        iconColor: Colors.blueAccent.shade100,
        collapsedIconColor: Colors.white70,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.event_note_outlined,
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                DateFormat('MMM d, yyyy').format(briefings.first.generatedAt),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (relative.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  relative,
                  style: TextStyle(
                    color: Colors.blueAccent.shade100,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${labels.join(' · ')}  •  ${briefings.length} briefing${briefings.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        children: [
          Theme(
            data:
                Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              childrenPadding: const EdgeInsets.only(bottom: 4),
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              textColor: Colors.white,
              collapsedTextColor: Colors.white70,
              iconColor: Colors.blueAccent.shade100,
              collapsedIconColor: Colors.white54,
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text(
                'Choose a briefing',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              children: [
                for (final briefing in briefings)
                  _buildBriefingPeriodRow(context, briefing),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildBriefingPeriodRow(
    BuildContext context, SageBriefingContent briefing) {
  return InkWell(
    onTap: () => showBriefingDetailDialog(context, briefing),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Text(
            briefingPeriodEmoji(briefing.period),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              briefingPeriodShortLabel(briefing.period),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            DateFormat('h:mm a').format(briefing.generatedAt),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 16, color: Colors.white38),
        ],
      ),
    ),
  );
}

// ── Briefing detail dialog ──────────────────────────────────────────────────

void showBriefingDetailDialog(
    BuildContext context, SageBriefingContent briefing) {
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SageBriefingDetailDialog(
        briefing: briefing,
        onClose: () => Navigator.of(dialogContext).pop(),
        onDownloadPdf: () => SageBriefingPdfService.export(briefing: briefing),
      ),
    ),
  );
}

/// Full-report dialog opened from the briefing history. Renders the stored
/// `detailText` as colour-coded sections — metric tiles for the numbers, an
/// alert box for inventory, and a highlighted callout for the recommendation.
class SageBriefingDetailDialog extends StatelessWidget {
  const SageBriefingDetailDialog({
    required this.briefing,
    required this.onClose,
    required this.onDownloadPdf,
  });

  final SageBriefingContent briefing;
  final VoidCallback onClose;

  /// Generates and exports the briefing PDF. Throws on failure.
  final Future<void> Function() onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    final fields = parseBriefingDetail(briefing.detailText);
    final hasStructured = fields.length >= 3;
    final healthLabel = fields['Business Health'] ?? briefing.businessHealth;
    final score = healthScoreFromLabel(healthLabel);
    final healthColor =
        score == null ? Colors.blueAccent : _healthColor(score.toDouble());
    // Prefer the exact date/time lines stored with the report; fall back to
    // generatedAt for legacy entries that lack them.
    final generated = fields['Date'] != null && fields['Time'] != null
        ? '${fields['Date']} • ${fields['Time']}'
        : DateFormat('MMM d, yyyy • h:mm a').format(briefing.generatedAt);

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(healthLabel, healthColor, generated),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: hasStructured
                  ? _buildStructuredBody(fields)
                  : _buildFallbackBody(),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader(String healthLabel, Color healthColor, String generated) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              briefingPeriodEmoji(briefing.period),
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  briefing.periodLabel.isNotEmpty
                      ? briefing.periodLabel
                      : 'Briefing report',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  generated,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (healthLabel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: healthColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: healthColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                healthLabel,
                style: TextStyle(
                  color: healthColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStructuredBody(Map<String, String> fields) {
    final tiles = <Widget>[
      if (fields['Revenue'] != null)
        _metricTile('Revenue', fields['Revenue']!,
            Icons.payments_rounded, Colors.greenAccent),
      if (fields['Orders'] != null)
        _metricTile('Orders', fields['Orders']!,
            Icons.receipt_long_rounded, Colors.blueAccent),
      if (fields['Best Seller'] != null)
        _metricTile('Best Seller', fields['Best Seller']!,
            Icons.star_rounded, Colors.amber),
      if (fields['Peak Hours'] != null)
        _metricTile('Peak Hours', fields['Peak Hours']!,
            Icons.schedule_rounded, Colors.purpleAccent),
    ];

    final recommendation =
        fields['Recommendations'] ?? briefing.recommendation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tiles.isNotEmpty) ...[
          _metricsGrid(tiles),
          const SizedBox(height: 12),
        ],
        if (fields['Yesterday Summary'] != null) ...[
          _narrativeBlock('YESTERDAY', fields['Yesterday Summary']!,
              Icons.history_rounded, Colors.blueGrey),
          const SizedBox(height: 10),
        ],
        if (fields["Today's Forecast"] != null) ...[
          _narrativeBlock("TODAY'S FORECAST", fields["Today's Forecast"]!,
              Icons.insights_rounded, Colors.tealAccent),
          const SizedBox(height: 10),
        ],
        if (fields['Inventory Alerts'] != null) ...[
          _alertBlock(fields['Inventory Alerts']!),
          const SizedBox(height: 10),
        ],
        if (recommendation.isNotEmpty) ...[
          _recommendationBlock(recommendation),
          const SizedBox(height: 2),
        ],
      ],
    );
  }

  /// Legacy fallback for briefings whose `detailText` cannot be parsed.
  Widget _buildFallbackBody() {
    final text = briefing.detailText.trim().isNotEmpty
        ? briefing.detailText
        : briefing.summary;
    return SelectableText(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12.5,
        height: 1.55,
      ),
    );
  }

  Widget _metricsGrid(List<Widget> tiles) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 10 : 0),
            // IntrinsicHeight bounds the row so the stretch alignment gets a
            // finite height — the surrounding scroll view is unbounded and a
            // stretched row there lays out at infinite height.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _metricTile(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrativeBlock(
      String label, String value, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.7), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.85), size: 13),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertBlock(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'INVENTORY ALERT',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationBlock(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded,
                  color: Colors.greenAccent, size: 15),
              const SizedBox(width: 6),
              const Text(
                'KEY RECOMMENDATION',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: TextStyle(
              color: Colors.greenAccent.shade100,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _DownloadPdfButton(onDownload: onDownloadPdf),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onClose,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              textStyle: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// The dialog's export action. Shows a spinner while the PDF is generated,
/// then closes the dialog with a success snackbar — or re-enables itself with
/// an error snackbar when the export fails.
class _DownloadPdfButton extends StatefulWidget {
  const _DownloadPdfButton({required this.onDownload});

  final Future<void> Function() onDownload;

  @override
  State<_DownloadPdfButton> createState() => _DownloadPdfButtonState();
}

class _DownloadPdfButtonState extends State<_DownloadPdfButton> {
  var _downloading = false;

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownload();
    } catch (_) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate the PDF.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Briefing PDF downloaded.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _downloading ? null : _handleDownload,
      icon: _downloading
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blueAccent,
              ),
            )
          : const Icon(Icons.picture_as_pdf_outlined, size: 15),
      label: Text(_downloading ? 'Generating…' : 'Download PDF'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.blueAccent.shade100,
        textStyle: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
