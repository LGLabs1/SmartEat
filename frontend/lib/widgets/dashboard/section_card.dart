import 'package:flutter/material.dart';

/// A consistent, reusable container used for every dashboard section.
///
/// Renders an icon tile, a title, an optional count/status badge, an optional
/// trailing action, and the section body. Keeps dashboard cards visually
/// uniform and removes the repeated header markup.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor,
    this.badge,
    this.action,
    this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final IconData icon;
  final Color? iconColor;
  final String? badge;
  final Widget? action;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = iconColor ?? scheme.primary;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                if (action != null) ...[
                  const SizedBox(width: 4),
                  action!,
                ],
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 14),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}
