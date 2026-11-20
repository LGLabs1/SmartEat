import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/staff/widgets/admin_attendance_calendar.dart';
import 'package:smarteat/theme.dart';

void main() {
  final usersByUid = <String, Map<String, dynamic>>{
    'u1': {'firstName': 'Alice', 'lastName': 'Diaz'},
    'u2': {'firstName': 'Ben', 'lastName': 'Ramos'},
    'u3': {'firstName': 'Cara', 'lastName': 'Santos'},
    'admin': {
      'firstName': 'Admin',
      'lastName': 'User',
      'role': 'admin',
    },
  };

  List<Map<String, dynamic>> buildRecords() => [
        {
          'uid': 'u1',
          'date': '2026-10-02',
          'status': 'present',
          'timeIn': DateTime(2026, 10, 2, 9),
          'timeOut': DateTime(2026, 10, 2, 17),
          'hoursWorked': 8.0,
          'workUnit': 1.0,
          'source': 'self',
        },
        {
          'uid': 'u2',
          'date': '2026-10-02',
          'status': 'halfday',
          'timeIn': DateTime(2026, 10, 2, 9),
          'timeOut': DateTime(2026, 10, 2, 13),
          'hoursWorked': 4.0,
          'workUnit': 0.5,
          'source': 'admin',
        },
        {
          'uid': 'u3',
          'date': '2026-10-02',
          'status': 'absent',
          'workUnit': 0.0,
          'source': 'cron',
        },
        {
          'uid': 'u1',
          'date': '2026-10-05',
          'status': 'in_progress',
          'timeIn': DateTime(2026, 10, 5, 9),
          'source': 'self',
        },
      ];

  Widget buildCalendar({
    List<Map<String, dynamic>>? records,
    DateTime? month,
    bool loading = false,
    ValueChanged<DateTime>? onMonthChanged,
    void Function(String uid, String label, DateTime day)? onEncode,
    Future<int> Function(
      DateTime monthStart,
      Map<String, Map<String, dynamic>> existing,
    )? onMarkMissing,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: AdminAttendanceCalendar(
            records: records ?? buildRecords(),
            usersByUid: usersByUid,
            selectedMonth: month ?? DateTime(2026, 10),
            isLoading: loading,
            onMonthChanged: onMonthChanged ?? (_) {},
            onEncodeAttendance: onEncode ?? (_, __, ___) {},
            onMarkMissingAbsent: onMarkMissing == null
                ? (_, __) async => 0
                : (monthStart, existing) => onMarkMissing(monthStart, existing),
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

  testWidgets('renders month summary and latest selected day', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar());

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('On duty · October 5'), findsOneWidget);
    expect(find.text('Monday, October 5, 2026'), findsOneWidget);
    expect(find.text('Alice Diaz'), findsOneWidget);
    expect(find.text('On shift'), findsWidgets);
    expect(find.text('Absent / No record (2)'), findsOneWidget);
  });

  testWidgets('tapping a day updates the on-duty card', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar());

    await tester
        .tap(find.byKey(const ValueKey('admin-attendance-day-2026-10-02')));
    await tester.pumpAndSettle();

    expect(find.text('Friday, October 2, 2026'), findsOneWidget);
    expect(find.text('Alice Diaz'), findsOneWidget);
    expect(find.text('Ben Ramos'), findsOneWidget);
    expect(find.text('Absent / No record (1)'), findsOneWidget);
    expect(find.text('Cara Santos'), findsNothing);

    await tester.tap(find.text('Absent / No record (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Cara Santos'), findsOneWidget);
  });

  testWidgets('encode callback receives the selected day', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    String? encodedUid;
    DateTime? encodedDay;

    await tester.pumpWidget(
      buildCalendar(
        onEncode: (uid, label, day) {
          encodedUid = uid;
          encodedDay = day;
        },
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('admin-attendance-day-2026-10-02')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-attendance-on-duty-u2')),
    );

    expect(encodedUid, 'u2');
    expect(encodedDay, DateTime(2026, 10, 2));
  });

  testWidgets('month navigation calls the parent callback', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    DateTime? requested;

    await tester.pumpWidget(
      buildCalendar(onMonthChanged: (month) => requested = month),
    );

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();

    expect(requested, DateTime(2026, 9));
  });

  testWidgets('mark missing absent is called with the visible month',
      (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    DateTime? requestedMonth;
    Map<String, Map<String, dynamic>>? existing;

    await tester.pumpWidget(
      buildCalendar(
        onMarkMissing: (monthStart, records) async {
          requestedMonth = monthStart;
          existing = records;
          return 2;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('admin-attendance-mark-missing')));
    await tester.pumpAndSettle();

    expect(requestedMonth, DateTime(2026, 10));
    expect(existing, isNotNull);
    expect(existing!['u1|2026-10-02'], isNotNull);
  });

  testWidgets('compact layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildCalendar());
    await tester.pump();

    expect(find.text('Attendance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state hides the selected-day card', (tester) async {
    await setSurface(tester, const Size(1200, 1000));
    await tester.pumpWidget(buildCalendar(loading: true));

    expect(find.text('Attendance'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-attendance-selected-day')),
      findsNothing,
    );
  });
}
