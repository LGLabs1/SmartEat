import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/report_period.dart';
import 'package:smarteat/widgets/period/period_navigator.dart';

void main() {
  final now = DateTime(2026, 11, 26, 15, 30);
  final currentMonth = ReportPeriod.month(now);

  Future<void> pumpNavigator(
    WidgetTester tester, {
    required ReportPeriodSelection selection,
    required List<ReportPeriodSelection> changes,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PeriodNavigator(
          selection: selection,
          now: now,
          onChanged: changes.add,
        ),
      ),
    ));
  }

  testWidgets(
      'shows the month label with both arrows enabled on the current month',
      (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: currentMonth),
      changes: changes,
    );

    expect(find.byKey(const Key('period-navigator')), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const Key('period-navigator-previous')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('period-navigator-next')))
            .onPressed,
        isNotNull);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('right arrow moves from the current month to year-to-date',
      (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: currentMonth),
      changes: changes,
    );

    await tester.tap(find.byKey(const Key('period-navigator-next')));
    await tester.pump();

    expect(changes, [
      ReportPeriodSelection(month: currentMonth, yearToDate: true),
    ]);
  });

  testWidgets('right arrow advances a past month one at a time',
      (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: DateTime(2026, 9, 1)),
      changes: changes,
    );

    await tester.tap(find.byKey(const Key('period-navigator-next')));
    await tester.pump();

    expect(changes, [ReportPeriodSelection(month: DateTime(2026, 10, 1))]);
  });

  testWidgets('year-to-date disables the right arrow and shows its label',
      (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: currentMonth, yearToDate: true),
      changes: changes,
    );

    expect(find.text('All months this year'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('period-navigator-next')))
            .onPressed,
        isNull);

    await tester.tap(find.byKey(const Key('period-navigator-next')));
    await tester.pump();
    expect(changes, isEmpty);
  });

  testWidgets('left arrow leaves year-to-date for the current month',
      (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: currentMonth, yearToDate: true),
      changes: changes,
    );

    await tester.tap(find.byKey(const Key('period-navigator-previous')));
    await tester.pump();

    expect(changes, [ReportPeriodSelection(month: currentMonth)]);
  });

  testWidgets('left arrow walks back through past months', (tester) async {
    final changes = <ReportPeriodSelection>[];
    await pumpNavigator(
      tester,
      selection: ReportPeriodSelection(month: DateTime(2026, 1, 1)),
      changes: changes,
    );

    await tester.tap(find.byKey(const Key('period-navigator-previous')));
    await tester.pump();

    expect(changes, [ReportPeriodSelection(month: DateTime(2025, 12, 1))]);
  });
}
