import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/presentation/screens/finance_screen.dart';
import 'package:smarteat/screens/analytics_screen.dart';
import 'package:smarteat/screens/menu_screen.dart';

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
}
