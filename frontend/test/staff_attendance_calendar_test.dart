import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/staff/widgets/staff_attendance_calendar.dart';
import 'package:smarteat/theme.dart';

void main() {
  final records = <Map<String, dynamic>>[
    {
      'date': '2026-10-02',
      'status': 'present',
      'timeIn': DateTime(2026, 10, 2, 8),
      'timeOut': DateTime(2026, 10, 2, 16),
      'hoursWorked': 8.0,
      'workUnit': 1.0,
      'source': 'self',
    },
    {
      'date': '2026-10-03',
      'status': 'halfday',
      'timeIn': DateTime(2026, 10, 3, 8),
      'timeOut': DateTime(2026, 10, 3, 12),
      'hoursWorked': 4.0,
      'workUnit': 0.5,
      'source': 'admin',
    },
    {
      'date': '2026-10-04',
      'status': 'absent',
      'workUnit': 0.0,
      'source': 'cron',
    },
    {
      'date': '2026-10-05',
      'status': 'in_progress',
      'timeIn': DateTime(2026, 10, 5, 9),
      'source': 'self',
    },
  ];

  Widget buildCalendar({
    DateTime? month,
    bool loading = false,
    ValueChanged<DateTime>? onMonthChanged,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StaffAttendanceCalendar(
            records: records,
            selectedMonth: month ?? DateTime(2026, 10),
            isLoading: loading,
            openShift: records.last,
            onMonthChanged: onMonthChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders summary and latest day detail', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar());

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Hours this month'), findsOneWidget);
    expect(find.text('Full days'), findsOneWidget);
    expect(find.text('Half days'), findsOneWidget);
    expect(find.text('Monday, October 5, 2026'), findsOneWidget);
    expect(find.text('Live duration'), findsOneWidget);
  });

  testWidgets('tapping a day updates the inline detail panel', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar());

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(find.text('Friday, October 2, 2026'), findsOneWidget);
    expect(find.text('Hours worked'), findsOneWidget);
    expect(find.text('8h'), findsWidgets);
  });

  testWidgets('month navigation calls the parent callback', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    DateTime? requested;
    await tester.pumpWidget(
      buildCalendar(onMonthChanged: (month) => requested = month),
    );

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();

    expect(requested, isNotNull);
    expect(requested!.year, 2026);
    expect(requested!.month, 9);
  });

  testWidgets('compact layout hides the weekly totals gutter', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildCalendar());
    await tester.pump();

    expect(find.text('Week'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state renders without a selected-day panel',
      (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar(loading: true));

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Monday, October 5, 2026'), findsNothing);
  });
}
