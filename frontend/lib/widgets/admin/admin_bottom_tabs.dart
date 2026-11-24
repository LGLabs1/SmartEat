import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../utils/responsive_breakpoints.dart';

class AdminTabItem {
  const AdminTabItem({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

class AdminBottomTabs extends StatelessWidget {
  const AdminBottomTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<AdminTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.adminTabsCompact;
    final index =
        tabs.isEmpty ? 0 : selectedIndex.clamp(0, tabs.length - 1).toInt();

    return SafeArea(
      top: false,
      child: BottomNavigationBar(
        currentIndex: index,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.sagePanel,
        selectedItemColor: AppTheme.sageAccent,
        unselectedItemColor: Colors.white.withValues(alpha: 0.52),
        showSelectedLabels: !compact,
        showUnselectedLabels: !compact,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: [
          for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++)
            BottomNavigationBarItem(
              icon: Semantics(
                button: true,
                selected: tabIndex == index,
                label: tabs[tabIndex].label,
                child: Tooltip(
                  message: tabs[tabIndex].label,
                  child: Icon(
                    tabs[tabIndex].icon,
                    size: compact ? 24 : 22,
                  ),
                ),
              ),
              label: compact ? '' : tabs[tabIndex].label,
            ),
        ],
      ),
    );
  }
}
