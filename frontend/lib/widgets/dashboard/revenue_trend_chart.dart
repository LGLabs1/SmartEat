import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A single point on the sales trend chart.
class TrendPoint {
  const TrendPoint({required this.label, required this.value});

  final String label;
  final double value;
}

/// A compact, self-contained 7-day revenue line chart.
class RevenueTrendChart extends StatelessWidget {
  const RevenueTrendChart({
    super.key,
    required this.points,
    this.color = const Color(0xFF1E88E5),
    this.height = 190,
  });

  final List<TrendPoint> points;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No sales data yet.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    var maxValue = 0.0;
    for (final p in points) {
      if (p.value > maxValue) maxValue = p.value;
    }
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.25;
    final interval = maxY / 4;

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: interval,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value >= 1000
                        ? '₱${(value / 1000).toStringAsFixed(0)}k'
                        : '₱${value.toInt()}',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[index].label,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchSpotThreshold: 24,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: const Color(0xFF17324D),
              tooltipRoundedRadius: 10,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final index = spot.x.round();
                final label =
                    index >= 0 && index < points.length ? points[index].label : '';
                return LineTooltipItem(
                  '$label\n₱${spot.y.toStringAsFixed(2)}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: points.length <= 10),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.20),
                    color.withValues(alpha: 0.01),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
