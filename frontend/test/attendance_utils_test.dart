import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/attendance_utils.dart';

void main() {
  group('attendance date and clock helpers', () {
    test('attendanceYmd zero-pads month and day', () {
      expect(attendanceYmd(DateTime(2026, 1, 5)), '2026-01-05');
      expect(attendanceDateOnly(DateTime(2026, 1, 5, 18, 30)),
          DateTime(2026, 1, 5));
    });

    test('formats clocks and durations', () {
      final noon = DateTime(2026, 1, 5, 12, 5);
      expect(formatAttendanceClock(noon), '12:05 PM');
      expect(formatAttendanceClock('2026-01-05T09:00:00'), '9:00 AM');
      expect(formatAttendanceClock(null), '');
      expect(formatAttendanceDuration(const Duration(minutes: 45)), '45m');
      expect(formatAttendanceDuration(const Duration(hours: 8)), '8h');
      expect(
        formatAttendanceDuration(const Duration(hours: 8, minutes: 12)),
        '8h 12m',
      );
      expect(formatAttendanceHours(7.5), '7h 30m');
    });
  });

  group('shift durations and work units', () {
    test('overnight shifts count forward and negative ranges clamp to zero',
        () {
      final start = DateTime(2026, 1, 5, 22);
      final end = DateTime(2026, 1, 6, 6);
      expect(attendanceShiftDuration(start, end), const Duration(hours: 8));
      expect(
        attendanceShiftDuration(end, start),
        Duration.zero,
      );
      expect(attendanceShiftDuration(start, null), isNull);
    });

    test('work unit thresholds follow full and half day hours', () {
      double unit(int minutes) => computeAttendanceWorkUnit(
            duration: Duration(minutes: minutes),
            fullDayHours: 8,
            halfDayHours: 4,
          );

      expect(unit(8 * 60), 1.0);
      expect(unit(10 * 60), 1.0);
      expect(unit(4 * 60), 0.5);
      expect(unit(7 * 60 + 59), 0.5);
      expect(unit(3 * 60 + 59), 0.0);
    });

    test('open shift duration uses the supplied now', () {
      final start = DateTime(2026, 1, 5, 9);
      final now = DateTime(2026, 1, 5, 12, 30);
      expect(
        attendanceOpenShiftDuration(start, now: now),
        const Duration(hours: 3, minutes: 30),
      );
    });
  });

  group('lateness', () {
    test('grace minutes are subtracted from late minutes', () {
      final onTime = DateTime(2026, 1, 5, 9, 5);
      final late = DateTime(2026, 1, 5, 9, 25);

      expect(
        computeAttendanceLateMinutes(
          timeIn: onTime,
          scheduledStart: '09:00',
          graceMinutes: 10,
        ),
        0,
      );
      expect(
        computeAttendanceLateMinutes(
          timeIn: late,
          scheduledStart: '09:00',
          graceMinutes: 10,
        ),
        15,
      );
      expect(
        computeAttendanceLateMinutes(timeIn: late, scheduledStart: ''),
        0,
      );
      expect(
        computeAttendanceLateMinutes(
          timeIn: late,
          scheduledStart: 'not-a-time',
        ),
        0,
      );
    });
  });

  group('review policy', () {
    test('attendanceNeedsReview is false for complete short or stale records',
        () {
      expect(
        attendanceNeedsReview({
          'status': 'incomplete',
          'needsReview': true,
          'workUnit': 0,
          'timeIn': '2026-01-05T08:00:00',
          'timeOut': '2026-01-05T10:00:00',
        }),
        isFalse,
      );
      expect(
        attendanceNeedsReview({
          'status': 'incomplete',
          'needsReview': true,
          'timeIn': '2026-01-05T08:00:00',
          'timeOut': '2026-01-05T17:00:00',
        }),
        isFalse,
      );
    });

    test(
        'attendanceNeedsReview is true for open or flagged missing-time records',
        () {
      expect(
        attendanceNeedsReview({
          'timeIn': '2026-01-05T08:00:00',
        }),
        isTrue,
      );
      expect(
        attendanceNeedsReview({
          'needsReview': true,
        }),
        isTrue,
      );
      expect(
        attendanceNeedsReview({
          'status': attendanceIncomplete,
        }),
        isTrue,
      );
    });
  });

  group('status resolution', () {
    test('explicit status wins, then work units, then legacy check-ins', () {
      expect(attendanceRecordStatus({'status': 'incomplete'}), 'incomplete');
      expect(attendanceRecordStatus({'workUnit': 1}), 'present');
      expect(attendanceRecordStatus({'workUnit': 0.5}), 'halfday');
      expect(
        attendanceRecordStatus({'present': true, 'workUnit': 0}),
        'short',
      );
      expect(
        attendanceRecordStatus({
          'morningCheckIn': '2026-01-05T08:00:00',
          'afternoonCheckIn': '2026-01-05T13:00:00',
        }),
        'present',
      );
      expect(
        attendanceRecordStatus({'morningCheckIn': '2026-01-05T08:00:00'}),
        'halfday',
      );
      expect(attendanceRecordStatus({}), 'absent');
    });

    test('complete times override stale review flags', () {
      expect(
        attendanceRecordStatus({
          'status': 'incomplete',
          'needsReview': true,
          'workUnit': 0.5,
          'timeIn': '2026-01-05T08:00:00',
          'timeOut': '2026-01-05T12:00:00',
        }),
        attendanceHalfDay,
      );
      expect(
        attendanceRecordStatus({
          'status': 'short',
          'workUnit': 0,
          'timeIn': '2026-01-05T08:00:00',
          'timeOut': '2026-01-05T10:00:00',
        }),
        attendanceShort,
      );
    });

    test('labels cover every status', () {
      expect(attendanceStatusLabel(attendanceInProgress), 'On shift');
      expect(attendanceStatusLabel(attendancePresent), 'Full day');
      expect(attendanceStatusLabel(attendanceHalfDay), 'Half day');
      expect(attendanceStatusLabel(attendanceShort), 'Under half day');
      expect(attendanceStatusLabel(attendanceIncomplete), 'Needs review');
      expect(attendanceStatusLabel(attendanceAbsent), 'Absent');
      expect(attendanceStatusForUnit(1), attendancePresent);
      expect(attendanceStatusForUnit(0.5), attendanceHalfDay);
      expect(attendanceStatusForUnit(0), attendanceShort);
    });

    test('open shift and legacy summaries', () {
      expect(attendanceIsOpen({'timeIn': DateTime(2026, 1, 5)}), isTrue);
      expect(
        attendanceIsOpen({
          'timeIn': DateTime(2026, 1, 5),
          'timeOut': DateTime(2026, 1, 5, 17),
        }),
        isFalse,
      );
      expect(attendanceHasShiftTimes({'timeIn': DateTime(2026, 1, 5)}), isTrue);
      expect(attendanceHasShiftTimes({'morningCheckIn': 'x'}), isFalse);
      expect(
        attendanceLegacySummary({
          'morningCheckIn': '2026-01-05T08:00:00',
          'afternoonCheckIn': '2026-01-05T13:00:00',
        }),
        'Morning: 8:00 AM | Afternoon: 1:00 PM',
      );
      expect(attendanceLegacySummary({}), '');
    });
  });

  group('summaries', () {
    test('month summary counts statuses and hours', () {
      final summary = attendanceMonthSummary([
        {'status': 'present', 'hoursWorked': 8},
        {
          'workUnit': 1,
          'timeIn': '2026-01-05T08:00:00',
          'timeOut': '2026-01-05T16:00:00'
        },
        {'workUnit': 0.5},
        {'status': 'absent'},
        {'status': 'incomplete'},
      ]);

      expect(summary.present, 2);
      expect(summary.half, 1);
      expect(summary.absent, 1);
      expect(summary.hours, 16);
    });

    test('team summary tracks on-shift, completed, review and missing', () {
      final summary = attendanceTeamSummary(
        staffUids: ['a', 'b', 'c', 'd', 'e'],
        todayKey: '2026-01-05',
        todayRecords: [
          {
            'uid': 'a',
            'workUnit': 1,
            'timeIn': '2026-01-05T08:00:00',
            'timeOut': '2026-01-05T17:00:00',
          },
          {'uid': 'b', 'needsReview': true, 'status': 'incomplete'},
          {'uid': 'c', 'timeIn': '2026-01-05T08:00:00'},
          {
            'uid': 'e',
            'status': 'incomplete',
            'needsReview': true,
            'workUnit': 0.5,
            'timeIn': '2026-01-05T08:00:00',
            'timeOut': '2026-01-05T12:00:00',
          },
        ],
        openRecords: [
          {'uid': 'c', 'timeIn': '2026-01-05T08:00:00'},
          {'uid': 'd', 'timeIn': '2026-01-04T22:00:00'},
        ],
      );

      expect(summary.onShift, 2);
      expect(summary.completed, 2);
      expect(summary.needsReview, 2);
      expect(summary.missing, 0);
    });
  });

  test('attendanceStatusCountsAsWork only counts paid units', () {
    expect(attendanceStatusCountsAsWork(attendancePresent), isTrue);
    expect(attendanceStatusCountsAsWork(attendanceHalfDay), isTrue);
    expect(attendanceStatusCountsAsWork(attendanceIncomplete), isFalse);
    expect(attendanceStatusCountsAsWork(attendanceAbsent), isFalse);
  });

  test('attendancePayrollWorkUnit maps stored units and statuses to pay units',
      () {
    expect(attendancePayrollWorkUnit({'workUnit': 1}), 1.0);
    expect(attendancePayrollWorkUnit({'workUnit': 0.5}), 0.5);
    expect(attendancePayrollWorkUnit({'workUnit': 0.25}), 0.5);
    expect(attendancePayrollWorkUnit({'workUnit': 0}), 0.0);
    expect(
      attendancePayrollWorkUnit({'status': attendancePresent}),
      1.0,
    );
    expect(
      attendancePayrollWorkUnit({'status': attendanceHalfDay}),
      0.5,
    );
    expect(attendancePayrollWorkUnit({'status': attendanceAbsent}), 0.0);
    expect(attendancePayrollWorkUnit({}), 0.0);
  });

  test('attendanceGrossPay sums full and half units with rate fallback', () {
    final gross = attendanceGrossPay(
      records: [
        {'uid': 'a', 'workUnit': 1},
        {'uid': 'a', 'workUnit': 0.5},
        {'uid': 'b', 'workUnit': 0.5},
        {'uid': 'b', 'status': attendanceAbsent},
        {'uid': 'missing', 'workUnit': 1},
      ],
      dailyRateByUid: const {'a': 100, 'b': 80},
      halfDayRateByUid: const {'a': 60},
    );

    expect(gross, 200);
  });

  test('attendanceScheduledStartFor parses valid HH:mm values', () {
    expect(
      attendanceScheduledStartFor(DateTime(2026, 1, 5, 18), '09:30'),
      DateTime(2026, 1, 5, 9, 30),
    );
    expect(attendanceScheduledStartFor(DateTime(2026, 1, 5), ''), isNull);
    expect(attendanceScheduledStartFor(DateTime(2026, 1, 5), '25:00'), isNull);
    expect(attendanceScheduledStartFor(DateTime(2026, 1, 5), 'bad'), isNull);
  });
}
