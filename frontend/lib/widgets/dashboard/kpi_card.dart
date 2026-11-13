import 'package:flutter/material.dart';

/// A single metric tile with an optional day-over-day trend badge.
///
/// Used for the top row of the dashboard. Designed to work inside a fixed
/// aspect-ratio grid, so it scales down gracefully on phones.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
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

  /// Positive/negative percentage. When null, no trend badge is shown.
  final double? trendPercent;
  final String? subtitle;
  /// Short helper text shown on hover/long-press explaining this KPI.
  final String? description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 420;

    final card = Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          // Horizontal layout: icon on the left, metrics on the right. Keeps
          // the tile a single short row instead of stacking three lines and
          // leaving dead space below.
          child: Row(
            children: [
              Container(
                width: compact ? 30 : 34,
                height: compact ? 30 : 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: compact ? 16 : 18),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: compact ? 15 : 17,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        if (trendPercent != null) ...[
                          const SizedBox(width: 6),
                          _TrendBadge(percent: trendPercent!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 10.5 : 11,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (description == null || description!.trim().isEmpty) return card;
    return Tooltip(
      message: description!,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: card,
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final isUp = percent >= 0;
    final color = isUp
        ? const Color(0xFF16A34A)
        : Theme.of(context).colorScheme.error;
    final rounded = percent.abs().toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '$rounded%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
