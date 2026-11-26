/// Shared, side-effect free helpers for the shift-based attendance system.
///
/// The app stores attendance in `eateries/{eateryId}/staff_attendance` using
/// Firestore timestamps for `timeIn`/`timeOut`. Older records still carry
/// `morningCheckIn`/`afternoonCheckIn` ISO strings, so the helpers here accept
/// both formats where it matters.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'staff_utils.dart';

const String attendanceInProgress = 'in_progress';
const String attendancePresent = 'present';
const String attendanceHalfDay = 'halfday';
const String attendanceShort = 'short';
const String attendanceAbsent = 'absent';
const String attendanceIncomplete = 'incomplete';

/// Converts a Firestore timestamp, DateTime, or ISO string to a DateTime.
DateTime? attendanceAsDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

/// `yyyy-MM-dd` key used by attendance documents.
String attendanceYmd(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime attendanceDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Duration between [timeIn] and [timeOut], never negative.
Duration? attendanceShiftDuration(dynamic timeIn, dynamic timeOut) {
  final start = attendanceAsDateTime(timeIn);
  final end = attendanceAsDateTime(timeOut);
  if (start == null || end == null) return null;
  final diff = end.difference(start);
  return diff.isNegative ? Duration.zero : diff;
}

bool attendanceHasCompleteTimes(Map<String, dynamic> record) {
  return attendanceAsDateTime(record['timeIn']) != null &&
      attendanceAsDateTime(record['timeOut']) != null;
}

bool attendanceNeedsReview(Map<String, dynamic> record) {
  if (attendanceHasCompleteTimes(record)) return false;

  final hasTimeIn = attendanceAsDateTime(record['timeIn']) != null;
  final hasTimeOut = attendanceAsDateTime(record['timeOut']) != null;
  if (hasTimeIn && !hasTimeOut) return true;

  if (record['needsReview'] == true && (!hasTimeIn || !hasTimeOut)) {
    return true;
  }

  final status = (record['status'] ?? '').toString().trim();
  if (status == attendanceIncomplete && (!hasTimeIn || !hasTimeOut)) {
    return true;
  }

  return false;
}

/// Duration worked so far for an open shift.
Duration attendanceOpenShiftDuration(dynamic timeIn, {DateTime? now}) {
  final start = attendanceAsDateTime(timeIn);
  if (start == null) return Duration.zero;
  final diff = (now ?? DateTime.now()).difference(start);
  return diff.isNegative ? Duration.zero : diff;
}

bool attendanceIsOpen(Map<String, dynamic> record) {
  return record['timeIn'] != null && record['timeOut'] == null;
}

bool attendanceHasShiftTimes(Map<String, dynamic> record) {
  return record['timeIn'] != null;
}

/// Full/half day unit from a worked duration.
///
/// Below the half-day threshold the shift counts as zero units so payroll is
/// not inflated by very short visits. Admins can always override the unit.
double computeAttendanceWorkUnit({
  required Duration duration,
  required double fullDayHours,
  required double halfDayHours,
}) {
  final full = fullDayHours > 0 ? fullDayHours : 8.0;
  var half = halfDayHours > 0 ? halfDayHours : full / 2;
  if (half > full) half = full;

  final hours = duration.inSeconds / 3600.0;
  if (hours >= full) return 1.0;
  if (hours >= half) return 0.5;
  return 0.0;
}

double attendancePayrollWorkUnit(Map<String, dynamic> record) {
  final rawUnit = record['workUnit'];
  if (rawUnit is num) {
    final unit = rawUnit.toDouble();
    if (unit >= 1.0) return 1.0;
    if (unit > 0) return 0.5;
    return 0.0;
  }

  final status = attendanceRecordStatus(record);
  if (status == attendancePresent) return 1.0;
  if (status == attendanceHalfDay) return 0.5;
  return 0.0;
}

double attendanceGrossPay({
  required Iterable<Map<String, dynamic>> records,
  required Map<String, double> dailyRateByUid,
  required Map<String, double> halfDayRateByUid,
}) {
  var total = 0.0;
  for (final record in records) {
    final uid = (record['uid'] ?? '').toString().trim();
    if (uid.isEmpty) continue;
    final unit = attendancePayrollWorkUnit(record);
    if (unit <= 0) continue;
    final dailyRate = dailyRateByUid[uid] ?? 0.0;
    final halfDayRate = halfDayRateByUid[uid] ?? 0.0;
    total += unit >= 1.0
        ? dailyRate
        : effectiveHalfDayRate(
            dailyRate: dailyRate,
            halfDayRate: halfDayRate,
          );
  }
  return total;
}

String attendanceStatusForUnit(double workUnit) {
  if (workUnit >= 1.0) return attendancePresent;
  if (workUnit > 0) return attendanceHalfDay;
  return attendanceShort;
}

/// Parses an `HH:mm` scheduled start onto [day], or null when unset/invalid.
DateTime? attendanceScheduledStartFor(DateTime day, String? scheduledStart) {
  final raw = (scheduledStart ?? '').trim();
  if (raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// Minutes late against an `HH:mm` scheduled start. Empty schedule = 0.
int computeAttendanceLateMinutes({
  required DateTime timeIn,
  String? scheduledStart,
  int graceMinutes = 0,
}) {
  final scheduled = attendanceScheduledStartFor(timeIn, scheduledStart);
  if (scheduled == null) return 0;

  final late = timeIn.difference(scheduled).inMinutes - graceMinutes;
  return late > 0 ? late : 0;
}

/// Best-effort status for both new shift records and legacy check-ins.
String attendanceRecordStatus(Map<String, dynamic> record) {
  final timeIn = attendanceAsDateTime(record['timeIn']);
  final timeOut = attendanceAsDateTime(record['timeOut']);
  if (timeIn != null && timeOut != null) {
    final rawUnit = record['workUnit'];
    if (rawUnit is num) {
      if (rawUnit >= 1) return attendancePresent;
      if (rawUnit > 0) return attendanceHalfDay;
      return attendanceShort;
    }
    final status = (record['status'] ?? '').toString().trim();
    if (status == attendancePresent ||
        status == attendanceHalfDay ||
        status == attendanceShort) {
      return status;
    }
  }

  final status = (record['status'] ?? '').toString().trim();
  if (status.isNotEmpty) return status;

  final workUnit = record['workUnit'];
  if (workUnit is num) {
    if (workUnit >= 1) return attendancePresent;
    if (workUnit > 0) return attendanceHalfDay;
    if (record['present'] == true) return attendanceShort;
  }

  final morning = record['morningCheckIn'] != null;
  final afternoon = record['afternoonCheckIn'] != null;
  if (morning && afternoon) return attendancePresent;
  if (morning || afternoon) return attendanceHalfDay;
  return attendanceAbsent;
}

String attendanceStatusLabel(String status) {
  switch (status) {
    case attendanceInProgress:
      return 'On shift';
    case attendancePresent:
      return 'Full day';
    case attendanceHalfDay:
      return 'Half day';
    case attendanceShort:
      return 'Under half day';
    case attendanceIncomplete:
      return 'Needs review';
    case attendanceAbsent:
    default:
      return 'Absent';
  }
}

/// 12-hour clock label for a timestamp, or an empty string.
String formatAttendanceClock(dynamic value) {
  final dt = attendanceAsDateTime(value);
  if (dt == null) return '';
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// Compact hours/minutes label, e.g. `8h 12m`.
String formatAttendanceDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String formatAttendanceHours(double hours) {
  final whole = hours.floor();
  final minutes = ((hours - whole) * 60).round();
  if (minutes == 0) return '${whole}h';
  return '${whole}h ${minutes}m';
}

/// A month's worth of attendance figures for the profile header.
({int present, int half, int absent, double hours}) attendanceMonthSummary(
  Iterable<Map<String, dynamic>> records,
) {
  var present = 0;
  var half = 0;
  var absent = 0;
  var hours = 0.0;

  for (final record in records) {
    final status = attendanceRecordStatus(record);
    if (status == attendancePresent) {
      present++;
    } else if (status == attendanceHalfDay) {
      half++;
    } else if (status == attendanceAbsent) {
      absent++;
    }

    final rawHours = record['hoursWorked'];
    if (rawHours is num) {
      hours += rawHours.toDouble();
    } else {
      final duration = attendanceShiftDuration(
        record['timeIn'],
        record['timeOut'],
      );
      if (duration != null) hours += duration.inSeconds / 3600.0;
    }
  }

  return (present: present, half: half, absent: absent, hours: hours);
}

/// Staff counts for the admin profile's team attendance monitor.
({int onShift, int completed, int needsReview, int missing})
    attendanceTeamSummary({
  required Iterable<String> staffUids,
  required Iterable<Map<String, dynamic>> todayRecords,
  required Iterable<Map<String, dynamic>> openRecords,
  required String todayKey,
}) {
  final todayByUid = <String, Map<String, dynamic>>{};
  for (final record in todayRecords) {
    final uid = (record['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty) todayByUid[uid] = record;
  }

  final onShiftUids = <String>{};
  for (final record in openRecords) {
    final uid = (record['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty && attendanceIsOpen(record)) onShiftUids.add(uid);
  }

  var completed = 0;
  var needsReview = 0;
  for (final record in todayByUid.values) {
    if (attendanceAsDateTime(record['timeOut']) != null) completed++;
    if (attendanceNeedsReview(record)) needsReview++;
  }

  var missing = 0;
  for (final uid in staffUids) {
    if (todayByUid.containsKey(uid)) continue;
    if (onShiftUids.contains(uid)) continue;
    missing++;
  }

  return (
    onShift: onShiftUids.length,
    completed: completed,
    needsReview: needsReview,
    missing: missing,
  );
}

/// Legacy check-in summary used by older attendance records.
String attendanceLegacySummary(Map<String, dynamic> record) {
  final morning = formatAttendanceClock(record['morningCheckIn']);
  final afternoon = formatAttendanceClock(record['afternoonCheckIn']);
  if (morning.isEmpty && afternoon.isEmpty) return '';
  return [
    if (morning.isNotEmpty) 'Morning: $morning',
    if (afternoon.isNotEmpty) 'Afternoon: $afternoon',
  ].join(' | ');
}

/// Whether an attendance status should be treated as paid work.
bool attendanceStatusCountsAsWork(String status) {
  return status == attendancePresent || status == attendanceHalfDay;
}
