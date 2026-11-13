import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The dashboard greeting header.
///
/// Gives the page a clear anchor: a time-aware greeting, the eatery name,
/// the current date, a "last updated" timestamp, and a refresh action.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.displayName,
    required this.eateryName,
    this.lastUpdated,
    this.isRefreshing = false,
    required this.onRefresh,
  });

  final String displayName;
  final String eateryName;
  final DateTime? lastUpdated;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = displayName.trim();
    final updatedLabel = lastUpdated == null
        ? 'Not yet synced'
        : 'Updated ${DateFormat('h:mm a').format(lastUpdated!)}';

    return Card(
      elevation: 0,
      color: scheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: scheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? _greeting : '$_greeting, $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (eateryName.trim().isNotEmpty) eateryName.trim(),
                      DateFormat('EEEE, MMM d, yyyy').format(DateTime.now()),
                    ].join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  updatedLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: isRefreshing ? null : onRefresh,
                    icon: isRefreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
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
