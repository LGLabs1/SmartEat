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
  });

  final String title;
  final List<FeatureTabItem> tabs;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final index =
        tabs.isEmpty ? 0 : selectedIndex.clamp(0, tabs.length - 1).toInt();
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
    );
  }
}
