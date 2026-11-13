import 'package:flutter/material.dart';


class CategoryCard extends StatelessWidget {
  final String category;
  final int itemCount;
  final int lowStockCount;
  final VoidCallback onTap;

  const CategoryCard({
    Key? key,
    required this.category,
    required this.itemCount,
    required this.lowStockCount,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = lowStockCount > 0;

    IconData icon;
    switch (category.toLowerCase()) {
      case 'vegetables':
        icon = Icons.eco_outlined;
        break;
      case 'meat':
        icon = Icons.set_meal_outlined;
        break;
      case 'dairy':
        icon = Icons.icecream_outlined;
        break;
      case 'grains':
        icon = Icons.rice_bowl_outlined;
        break;
      case 'spices':
        icon = Icons.spa_outlined;
        break;
      case 'beverages':
        icon = Icons.local_cafe_outlined;
        break;
      default:
        icon = Icons.inventory_2_outlined;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isWarning
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: isWarning
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                category,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                itemCount.toString() + ' items',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (lowStockCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  lowStockCount.toString() + ' low stock',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class StockStatusCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const StockStatusCard({
    Key? key,
    required this.title,
    required this.itemCount,
    required this.icon,
    required this.accent,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                itemCount.toString() + ' items',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
