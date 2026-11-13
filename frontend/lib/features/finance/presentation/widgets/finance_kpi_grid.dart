import 'package:flutter/material.dart';

import '../../../../theme.dart';
import '../../../../widgets/dashboard/kpi_card.dart';

/// One entry in a responsive KPI grid.
class FinanceKpi {
  const FinanceKpi({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trendPercent,
    this.subtitle,
    this.description,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double? trendPercent;
  final String? subtitle;
  /// Hover helper text explaining this KPI.
  final String? description;
  final VoidCallback? onTap;
}

/// Lays out [KpiCard] tiles responsively, matching the dashboard grid
/// breakpoints (>=1100 -> 4 columns, >=560 -> 2, else 1).
class FinanceKpiGrid extends StatelessWidget {
  const FinanceKpiGrid({super.key, required this.kpis});

  final List<FinanceKpi> kpis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 4
            : width >= 560
                ? 2
                : 1;
        const gap = 12.0;
        final tileWidth = (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in kpis)
              SizedBox(
                width: tileWidth.isFinite ? tileWidth : width,
                child: KpiCard(
                  title: k.title,
                  value: k.value,
                  icon: k.icon,
                  color: k.color,
                  trendPercent: k.trendPercent,
                  subtitle: k.subtitle,
                  description: k.description,
                  onTap: k.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Applies the shared max content width and page padding for tab bodies.
class FinancePageBody extends StatelessWidget {
  const FinancePageBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.pagePadding),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.contentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
