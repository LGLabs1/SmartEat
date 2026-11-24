import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/admin/admin_bottom_tabs.dart';
import 'package:smarteat/widgets/feature_tab_header.dart';
import 'package:smarteat/widgets/responsive_search_field.dart';

const _tabs = [
  AdminTabItem(label: 'Overview', icon: Icons.dashboard_outlined),
  AdminTabItem(label: 'Expenses', icon: Icons.receipt_long_outlined),
  AdminTabItem(label: 'Payables', icon: Icons.payment_outlined),
];

Future<void> _pumpTabs(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AdminBottomTabs(
        tabs: _tabs,
        selectedIndex: 0,
        onTap: (_) {},
      ),
    ),
  ));
}

void main() {
  testWidgets('admin bottom tabs show labels on wide screens', (tester) async {
    await _pumpTabs(tester, const Size(900, 700));

    for (final label in ['Overview', 'Expenses', 'Payables']) {
      expect(find.text(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
    }
  });

  testWidgets('admin bottom tabs are icon-only on narrow screens',
      (tester) async {
    await _pumpTabs(tester, const Size(390, 844));

    for (final label in ['Overview', 'Expenses', 'Payables']) {
      expect(find.text(label), findsNothing);
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
    }
  });

  testWidgets('feature tab header is title-only without tab navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeatureTabHeader(
          title: 'Finance',
          tabs: const [
            FeatureTabItem(label: 'Overview', icon: Icons.dashboard_outlined),
            FeatureTabItem(
                label: 'Expenses', icon: Icons.receipt_long_outlined),
          ],
          selectedIndex: 1,
        ),
      ),
    ));

    expect(find.text('Finance  /  Expenses'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byTooltip('Expenses'), findsNothing);
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
