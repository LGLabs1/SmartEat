import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/sage_briefing_card.dart';

SageBriefingContent _highlightBriefing() => SageBriefingContent(
      id: 'test_highlights',
      title: 'Good morning, Sunny Bistro',
      summary: 'Summary text that must remain visible.',
      periodLabel: 'Morning briefing',
      generatedAt: DateTime(2026, 11, 26, 8),
      recommendation: 'Restock immediately.',
      businessHealth: 'Critical (35/100)',
      detailText: 'Yesterday Summary: ₱4,000 in sales and revenue increased by '
          '18.0% compared with yesterday.\n'
          "Today's Forecast: The forecast points to ₱4,100 for the next peak "
          'window.\n'
          'Business Health: Critical (35/100)\n'
          'Best Seller: Banh Mi\n'
          'Inventory Alerts: Beef is running critically low. 3 low stock '
          'items.\n'
          'Recommendations: Restock immediately.',
      period: 'morning',
    );

void main() {
  testWidgets('renders ranked highlights and keeps dialog actions',
      (tester) async {
    var dismissCount = 0;
    var askCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SageBriefingCard(
          content: _highlightBriefing(),
          onDismiss: () => dismissCount++,
          onAskSage: () => askCount++,
        ),
      ),
    ));

    expect(find.byKey(const Key('sage-briefing-highlight-critical-stock')),
        findsOneWidget);
    expect(find.byKey(const Key('sage-briefing-highlight-low-stock')),
        findsOneWidget);
    expect(find.byKey(const Key('sage-briefing-highlight-revenue')),
        findsOneWidget);
    expect(find.byKey(const Key('sage-briefing-highlight-health')),
        findsOneWidget);
    expect(find.byKey(const Key('sage-briefing-highlight-forecast')),
        findsNothing);

    expect(find.text('Morning briefing'), findsOneWidget);
    expect(find.text('Good morning, Sunny Bistro'), findsOneWidget);
    expect(find.text('Summary text that must remain visible.'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Ask Sage'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.tap(find.text('Ask Sage'));

    expect(dismissCount, 1);
    expect(askCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to forecast highlight and stays scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(800, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SageBriefingCard(
          content: SageBriefingContent(
            id: 'test_forecast_only',
            title: 'Hello',
            summary: List.generate(
              20,
              (index) => 'Summary line $index with enough text to scroll.',
            ).join('\n'),
            periodLabel: 'Briefing',
            generatedAt: DateTime(2026, 11, 26, 9),
            recommendation: '',
            businessHealth: 'Good (82/100)',
            detailText: "Today's Forecast: The forecast points to ₱4,100 for "
                'the next peak window.\n'
                'Business Health: Good (82/100)\n'
                'Best Seller: Banh Mi',
            period: 'morning',
          ),
          onDismiss: () {},
          onAskSage: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('sage-briefing-highlight-forecast')),
        findsOneWidget);
    expect(find.text('₱4,100 next peak'), findsOneWidget);
    expect(find.byKey(const Key('sage-briefing-highlight-critical-stock')),
        findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets);

    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Ask Sage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('settings screen no longer includes the app download section', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();

    expect(source, isNot(contains('download_apps_card.dart')));
    expect(source, isNot(contains('DownloadAppsCard')));
    expect(source, isNot(contains('Get Smart Eat')));
  });
}
