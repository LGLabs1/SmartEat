import 'package:cloud_firestore/cloud_firestore.dart';

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
  }) async {
    var written = 0;
    for (final uid in staffUids) {
      for (var i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        if (!shouldAutoMarkAbsent(day: day, today: today)) continue;

        final dateKey = staffFormatYmd(day);
        if (existingKeys.contains('$uid|$dateKey')) continue;

        final docId = '${eateryId}_${uid}_$dateKey';
        await _db
            .collection('eateries')
            .doc(eateryId)
            .collection('staff_attendance')
            .doc(docId)
            .set({
          'eateryId': eateryId,
          'uid': uid,
          'date': dateKey,
          'present': false,
          'workUnit': 0.0,
          'notes': 'Auto-marked absent',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'autoMarked': true,
        }, SetOptions(merge: true));
        written++;
      }
    }
    return written;
  }
}
