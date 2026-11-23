import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/presentation/screens/finance_screen.dart';
import 'package:smarteat/features/inventory/presentation/screens/inventory_feature_screen.dart';
import 'package:smarteat/screens/analytics_screen.dart';
import 'package:smarteat/screens/menu_screen.dart';
import 'package:smarteat/widgets/feature_tab_header.dart';
import 'package:smarteat/widgets/responsive_search_field.dart';

Widget buildHarness(List<Widget> icons) {
  return MaterialApp(
    home: Scaffold(
      body: Column(children: icons),
    ),
  );
}

void main() {
  testWidgets('finance compact navigation icons expose labels and tooltips',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      financeCompactNavIcon(Icons.dashboard_outlined, 'Overview'),
      financeCompactNavIcon(Icons.receipt_long_outlined, 'Expenses'),
      financeCompactNavIcon(Icons.payment_outlined, 'Payables'),
      financeCompactNavIcon(Icons.analytics_outlined, 'Reports'),
      financeCompactNavIcon(Icons.groups_outlined, 'Payroll'),
    ]));

    for (final label in [
      'Overview',
      'Expenses',
      'Payables',
      'Reports',
      'Payroll',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget,
          reason: '$label must be available to screen readers');
      expect(find.byTooltip(label), findsOneWidget,
          reason: '$label must be available as a tooltip');
    }
  });

  testWidgets('menu compact tab and nav icons expose labels and tooltips',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      menuCompactNavIcon(Icons.restaurant_menu_outlined, 'Menu'),
      menuCompactNavIcon(Icons.menu_book_outlined, 'Recipes'),
    ]));

    for (final label in ['Menu', 'Recipes']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
    }
  });

  testWidgets('analytics compact tab icons expose labels and tooltips',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      analyticsCompactTabIcon(Icons.show_chart_outlined, 'Sales'),
      analyticsCompactTabIcon(Icons.insights_outlined, 'Insights'),
      analyticsCompactTabIcon(Icons.auto_graph_outlined, 'Forecast'),
      analyticsCompactTabIcon(Icons.payments_outlined, 'Finance'),
    ]));

    for (final label in ['Sales', 'Insights', 'Forecast', 'Finance']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
    }
  });

  testWidgets('inventory compact nav icons expose labels and tooltips',
      (tester) async {
    await tester.pumpWidget(buildHarness([
      inventoryCompactNavIcon(Icons.dashboard, 'Overview'),
      inventoryCompactNavIcon(Icons.inventory, 'Items'),
      inventoryCompactNavIcon(Icons.history, 'Movements'),
      inventoryCompactNavIcon(Icons.shopping_cart, 'Purchases'),
      inventoryCompactNavIcon(Icons.tune, 'Adjustments'),
      inventoryCompactNavIcon(Icons.bar_chart, 'Reports'),
    ]));

    for (final label in [
      'Overview',
      'Items',
      'Movements',
      'Purchases',
      'Adjustments',
      'Reports',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
    }
  });

  testWidgets('feature tab header shows the current tab', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeatureTabHeader(
          title: 'Finance',
          tabs: const [
            FeatureTabItem(label: 'Overview', icon: Icons.dashboard_outlined),
            FeatureTabItem(label: 'Expenses', icon: Icons.receipt_long_outlined),
          ],
          selectedIndex: 1,
          onTap: (_) {},
        ),
      ),
    ));

    expect(find.textContaining('Expenses'), findsWidgets);
    expect(find.byTooltip('Expenses'), findsOneWidget);
  });

  testWidgets('responsive search collapses to an icon on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResponsiveSearchField(
          fieldBuilder: (context, {required bool autofocus}) => TextField(
            key: const Key('compact-search-field'),
            autofocus: autofocus,
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('compact-search-field')), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-search-field')), findsOneWidget);
  });
}
