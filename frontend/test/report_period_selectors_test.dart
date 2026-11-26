import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/period/date_range_selector.dart';
import 'package:smarteat/widgets/period/month_selector.dart';

void main() {
  testWidgets('MonthSelector reports the picked month', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MonthSelector(
          month: DateTime(2026, 5, 15),
          onMonthChanged: (month) => picked = month,
        ),
      ),
    ));

    expect(find.text('May 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('month-selector-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Select Month'), findsOneWidget);

    await tester.tap(find.byKey(const Key('month-choice-6')));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2026, 6, 1));
  });

  testWidgets('DateRangeSelector exposes shared quick ranges', (tester) async {
    DateTimeRange? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DateRangeSelector(
          range: null,
          onChanged: (range) => picked = range,
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('date-range-selector-chip')));
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Pick month'), findsOneWidget);
    expect(find.text('Custom range'), findsOneWidget);

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.start.day, 1);
    expect(picked!.end.isAfter(picked!.start), isTrue);
  });
}
