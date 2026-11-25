import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'finance_category_bar.dart';

class FinanceCategoryPieChart extends StatelessWidget {
  const FinanceCategoryPieChart({
    super.key,
    required this.data,
    required this.money,
    this.height = 220,
  });

  final List<MapEntry<String, double>> data;
  final String Function(num) money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slices = data.where((entry) => entry.value > 0).toList();
    if (slices.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No expense data yet.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }

    final total = slices.fold<double>(0, (sum, entry) => sum + entry.value);
    final colors = [
      for (final entry in slices) financeCategoryColor(entry.key),
    ];
    final sections = <PieChartSectionData>[
      for (var index = 0; index < slices.length; index++)
        PieChartSectionData(
          value: slices[index].value,
          color: colors[index],
          radius: 54,
          showTitle: slices.length <= 4,
          title: '${(slices[index].value / total * 100).toStringAsFixed(0)}%',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 44,
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var index = 0; index < slices.length; index++)
              _CategoryLegend(
                color: colors[index],
                label: slices[index].key,
                value:
                    '${(slices[index].value / total * 100).toStringAsFixed(1)}% • ${money(slices[index].value)}',
              ),
          ],
        ),
      ],
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
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
