import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/attendance_settings_service.dart';
import '../../../utils/attendance_utils.dart';
import '../../../utils/staff_utils.dart';

/// Centralised Firestore access for the staff management feature.
///
/// Keeping collection paths and write shapes here means the screens only deal
/// with presentation, and the payroll/attendance paths stay consistent.
class StaffService {
  StaffService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> usersStream(
    String eateryId,
  ) {
    return _db
        .collection('users')
        .where('eateryId', isEqualTo: eateryId)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> staffProfilesStream(
    String eateryId,
  ) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_profiles')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> attendanceStream(
    String eateryId, {
    required String startKey,
    required String endKey,
  }) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> attendanceDayStream(
    String eateryId, {
    required String dateKey,
  }) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .where('date', isEqualTo: dateKey)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> recentAttendanceStream(
    String eateryId, {
    required String startKey,
    required String endKey,
  }) {
    return attendanceStream(
      eateryId,
      startKey: startKey,
      endKey: endKey,
    );
  }

  static DocumentReference<Map<String, dynamic>> _attendanceRef(
    String eateryId,
    String uid,
    String dateKey,
  ) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .doc('${eateryId}_${uid}_$dateKey');
  }

  static Future<Map<String, dynamic>?> getAttendanceForDate({
    required String eateryId,
    required String uid,
    required DateTime day,
  }) async {
    final snap = await _attendanceRef(eateryId, uid, attendanceYmd(day)).get();
    if (!snap.exists) return null;
    return {'id': snap.id, ...snap.data()!};
  }

  /// The most recent shift that has a Time In but no Time Out.
  static Future<Map<String, dynamic>?> findOpenShift({
    required String eateryId,
    required String uid,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    // Query one day at a time so this lookup only needs Firestore's automatic
    // single-field indexes. Adding a `uid` filter alongside a `date` range
    // would require a composite index and break Time In/Out until it builds.
    final dayKeys = List.generate(
      3,
      (offset) => attendanceYmd(
        attendanceDateOnly(current).subtract(Duration(days: offset)),
      ),
    );
    final snapshots = await Future.wait(
      dayKeys.map(
        (dateKey) => _db
            .collection('eateries')
            .doc(eateryId)
            .collection('staff_attendance')
            .where('date', isEqualTo: dateKey)
            .get(),
      ),
    );

    Map<String, dynamic>? latest;
    DateTime? latestIn;
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['uid'] ?? '').toString() != uid) continue;
        if (!attendanceIsOpen(data)) continue;
        final timeIn = attendanceAsDateTime(data['timeIn']);
        if (timeIn == null) continue;
        if (latestIn == null || timeIn.isAfter(latestIn)) {
          latestIn = timeIn;
          latest = {'id': doc.id, ...data};
        }
      }
    }
    return latest;
  }

  /// Starts a shift for [uid] using a server timestamp.
  static Future<Map<String, dynamic>> clockIn({
    required String eateryId,
    required String uid,
    AttendanceSettings? settings,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final config =
        settings ?? await AttendanceSettingsService.loadForEatery(eateryId);

    final open = await findOpenShift(
      eateryId: eateryId,
      uid: uid,
      now: current,
    );
    if (open != null) {
      throw Exception('You already have an open shift. Time out first.');
    }

    final dateKey = attendanceYmd(current);
    final ref = _attendanceRef(eateryId, uid, dateKey);
    final lateMinutes = computeAttendanceLateMinutes(
      timeIn: current,
      scheduledStart: config.scheduledStart,
      graceMinutes: config.graceMinutes,
    );

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final data = snap.data()!;
        if (data['timeIn'] != null) {
          throw Exception('Attendance for today has already been recorded.');
        }
        final source = (data['source'] ?? '').toString().trim().toLowerCase();
        final workUnit = data['workUnit'];
        final hasEncodedUnit = workUnit is num && workUnit > 0;
        if (source == 'admin' ||
            hasEncodedUnit ||
            (data['present'] == true && source != 'cron')) {
          throw Exception(
            'Today was already encoded by an admin. Ask them to update it.',
          );
        }
      }

      final payload = <String, dynamic>{
        'eateryId': eateryId,
        'uid': uid,
        'date': dateKey,
        'timeIn': FieldValue.serverTimestamp(),
        'present': true,
        'workUnit': 0.0,
        'status': attendanceInProgress,
        'source': 'self',
        'scheduledStart': config.scheduledStart,
        'late': lateMinutes > 0,
        'lateMinutes': lateMinutes,
        'needsReview': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snap.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      tx.set(ref, payload, SetOptions(merge: true));
    });

    final updated = await ref.get();
    return {'id': updated.id, ...updated.data()!};
  }

  /// Ends the most recent open shift for [uid].
  static Future<Map<String, dynamic>> clockOut({
    required String eateryId,
    required String uid,
    AttendanceSettings? settings,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final config =
        settings ?? await AttendanceSettingsService.loadForEatery(eateryId);

    final open = await findOpenShift(
      eateryId: eateryId,
      uid: uid,
      now: current,
    );
    if (open == null) {
      throw Exception('No open shift found. Time in first.');
    }

    final timeIn = attendanceAsDateTime(open['timeIn']);
    if (timeIn == null) {
      throw Exception('This shift has an invalid Time In value.');
    }

    var duration = current.difference(timeIn);
    if (duration.isNegative) duration = Duration.zero;
    final workUnit = computeAttendanceWorkUnit(
      duration: duration,
      fullDayHours: config.fullDayHours,
      halfDayHours: config.halfDayHours,
    );
    final status = attendanceStatusForUnit(workUnit);
    final docId = (open['id'] ?? '').toString().trim();
    if (docId.isEmpty) {
      throw Exception('Unable to locate the open attendance record.');
    }
    final ref = _db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .doc(docId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('Attendance record no longer exists.');
      }
      final data = snap.data()!;
      if (data['timeOut'] != null) {
        throw Exception('This shift has already been closed.');
      }
      tx.update(ref, {
        'timeOut': FieldValue.serverTimestamp(),
        'hoursWorked': duration.inSeconds / 3600.0,
        'workUnit': workUnit,
        'status': status,
        'present': true,
        'needsReview': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final updated = await ref.get();
    return {'id': updated.id, ...updated.data()!};
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> payrollPayoutsStream(
    String eateryId, {
    required String weekStartKey,
  }) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('payroll_payouts')
        .where('weekStart', isEqualTo: weekStartKey)
        .snapshots();
  }

  /// A single staff member's full payout history. The security rules only
  /// allow this query for the signed-in staff member (or an admin).
  static Stream<QuerySnapshot<Map<String, dynamic>>> myPayoutsStream(
    String eateryId, {
    required String uid,
  }) {
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('payroll_payouts')
        .where('uid', isEqualTo: uid)
        .snapshots();
  }

  static Future<void> approveStaff(String uid) {
    return _db.collection('users').doc(uid).set({
      'approved': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveStaffProfile({
    required String eateryId,
    required String uid,
    required bool isAdmin,
    required String position,
    required double dailyRate,
    required double halfDayRate,
    required String status,
    dynamic createdAt,
  }) {
    final collection = isAdmin ? 'admin_profiles' : 'staff_profiles';
    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection(collection)
        .doc(uid)
        .set({
      'eateryId': eateryId,
      'uid': uid,
      'position': position,
      'dailyRate': dailyRate,
      'halfDayRate': halfDayRate,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> recordPayout({
    required String eateryId,
    required String uid,
    required String weekStartKey,
    required double amount,
    required String type,
    required String adminUid,
    required String adminName,
  }) {
    final payoutId = type == 'weekly'
        ? '${eateryId}_${uid}_$weekStartKey'
        : '${eateryId}_${uid}_${weekStartKey}_advance_${DateTime.now().millisecondsSinceEpoch}';

    return _db
        .collection('eateries')
        .doc(eateryId)
        .collection('payroll_payouts')
        .doc(payoutId)
        .set({
      'eateryId': eateryId,
      'uid': uid,
      'weekStart': weekStartKey,
      'amount': amount,
      'type': type,
      'paidByUid': adminUid,
      'paidByName': adminName,
      'paidAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks every past day in [weekStart]..[weekStart]+6 without an existing
  /// attendance record as absent. Today and future days are skipped.
  static Future<int> markMissingAbsent({
    required String eateryId,
    required Iterable<String> staffUids,
    required DateTime weekStart,
    required Set<String> existingKeys,
    required DateTime today,
  }) {
    return markMissingAbsentInRange(
      eateryId: eateryId,
      staffUids: staffUids,
      start: weekStart,
      end: weekStart.add(const Duration(days: 6)),
      existingKeys: existingKeys,
      today: today,
    );
  }

  /// Marks every past day in [start]..[end] without an existing attendance
  /// record as absent. Today and future days are skipped.
  static Future<int> markMissingAbsentInRange({
    required String eateryId,
    required Iterable<String> staffUids,
    required DateTime start,
    required DateTime end,
    required Set<String> existingKeys,
    required DateTime today,
  }) async {
    final firstDay = staffDateOnly(start);
    final lastDay = staffDateOnly(end);
    if (lastDay.isBefore(firstDay)) return 0;

    var written = 0;
    var pending = 0;
    var batch = _db.batch();

    Future<void> commitIfNeeded({bool force = false}) async {
      if (pending == 0) return;
      if (!force && pending < 450) return;
      await batch.commit();
      batch = _db.batch();
      pending = 0;
    }

    for (final uid in staffUids) {
      var day = firstDay;
      while (!day.isAfter(lastDay)) {
        if (shouldAutoMarkAbsent(day: day, today: today)) {
          final dateKey = staffFormatYmd(day);
          if (!existingKeys.contains('$uid|$dateKey')) {
            final docId = '${eateryId}_${uid}_$dateKey';
            batch.set(
              _db
                  .collection('eateries')
                  .doc(eateryId)
                  .collection('staff_attendance')
                  .doc(docId),
              {
                'eateryId': eateryId,
                'uid': uid,
                'date': dateKey,
                'present': false,
                'workUnit': 0.0,
                'status': attendanceAbsent,
                'source': 'cron',
                'notes': 'Auto-marked absent',
                'updatedAt': FieldValue.serverTimestamp(),
                'createdAt': FieldValue.serverTimestamp(),
                'autoMarked': true,
              },
              SetOptions(merge: true),
            );
            written++;
            pending++;
            await commitIfNeeded();
          }
        }
        day = day.add(const Duration(days: 1));
      }
    }

    await commitIfNeeded(force: true);
    return written;
  }
}
