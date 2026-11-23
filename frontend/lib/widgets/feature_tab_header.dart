import 'package:flutter/material.dart';

import '../theme.dart';

class FeatureTabItem {
  const FeatureTabItem({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

class FeatureTabHeader extends StatelessWidget {
  const FeatureTabHeader({
    super.key,
    required this.title,
    required this.tabs,
    required this.selectedIndex,
    this.onTap,
  });

  final String title;
  final List<FeatureTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final index = tabs.isEmpty
        ? 0
        : selectedIndex.clamp(0, tabs.length - 1).toInt();
    final currentLabel = tabs.isEmpty ? title : tabs[index].label;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.sagePanel,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.sageAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$title  /  $currentLabel',
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, tabIndex) {
                final tab = tabs[tabIndex];
                final selected = tabIndex == index;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: tab.label,
                  child: Tooltip(
                    message: tab.label,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onTap == null ? null : () => onTap!(tabIndex),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.sageAccent
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.sageAccent
                                  : Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tab.icon,
                                size: 16,
                                color: selected
                                    ? AppTheme.sageNavy
                                    : Colors.white.withValues(alpha: 0.78),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tab.label,
                                style: TextStyle(
                                  color: selected
                                      ? AppTheme.sageNavy
                                      : Colors.white.withValues(alpha: 0.78),
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
