import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_service.dart';

/// Eatery-level attendance rules, shared by admins and staff.
///
/// Stored on `eateries/{eateryId}/settings/attendance`. The business may be
/// open 24/7, so no shift start is assumed unless an admin configures one.
class AttendanceSettings {
  const AttendanceSettings({
    this.fullDayHours = 8.0,
    this.halfDayHours = 4.0,
    this.graceMinutes = 10,
    this.scheduledStart = '',
    this.timezone = 'Asia/Manila',
  });

  final double fullDayHours;
  final double halfDayHours;
  final int graceMinutes;
  final String scheduledStart;
  final String timezone;

  factory AttendanceSettings.fromMap(Map<String, dynamic>? data) {
    final full = _asDouble(data?['fullDayHours'], 8.0);
    final half = _asDouble(data?['halfDayHours'], 4.0);
    final graceRaw = data?['graceMinutes'];
    final grace = graceRaw is num
        ? graceRaw.round()
        : int.tryParse(graceRaw?.toString() ?? '') ?? 10;

    return AttendanceSettings(
      fullDayHours: full > 0 ? full : 8.0,
      halfDayHours: half > 0 ? half : 4.0,
      graceMinutes: grace < 0 ? 0 : grace,
      scheduledStart: (data?['scheduledStart'] ?? '').toString().trim(),
      timezone: (data?['timezone'] ?? 'Asia/Manila').toString().trim().isEmpty
          ? 'Asia/Manila'
          : (data?['timezone'] ?? 'Asia/Manila').toString().trim(),
    );
  }

  AttendanceSettings copyWith({
    double? fullDayHours,
    double? halfDayHours,
    int? graceMinutes,
    String? scheduledStart,
    String? timezone,
  }) {
    return AttendanceSettings(
      fullDayHours: fullDayHours ?? this.fullDayHours,
      halfDayHours: halfDayHours ?? this.halfDayHours,
      graceMinutes: graceMinutes ?? this.graceMinutes,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      timezone: timezone ?? this.timezone,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullDayHours': fullDayHours,
        'halfDayHours': halfDayHours,
        'graceMinutes': graceMinutes,
        'scheduledStart': scheduledStart,
        'timezone': timezone,
      };

  static double _asDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? fallback;
  }
}

class AttendanceSettingsService {
  AttendanceSettingsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static AttendanceSettings? _cache;
  static String _cacheEateryId = '';

  static DocumentReference<Map<String, dynamic>> _settingsRef(String eateryId) {
    return _firestore
        .collection('eateries')
        .doc(eateryId)
        .collection('settings')
        .doc('attendance');
  }

  /// Loads settings for the signed-in user's eatery.
  static Future<AttendanceSettings> load() async {
    final eateryId = await FirebaseService.getCurrentEateryId();
    if (eateryId == null || eateryId.trim().isEmpty) {
      return const AttendanceSettings();
    }
    return loadForEatery(eateryId.trim());
  }

  /// Loads settings for a specific eatery, caching the last result.
  static Future<AttendanceSettings> loadForEatery(
    String eateryId, {
    bool forceRefresh = false,
  }) async {
    final id = eateryId.trim();
    if (id.isEmpty) return const AttendanceSettings();

    if (!forceRefresh && _cache != null && _cacheEateryId == id) {
      return _cache!;
    }

    try {
      final snap = await _settingsRef(id).get();
      final settings = AttendanceSettings.fromMap(snap.data());
      _cache = settings;
      _cacheEateryId = id;
      return settings;
    } catch (_) {
      return const AttendanceSettings();
    }
  }

  static Future<void> save(AttendanceSettings settings) async {
    final eateryId = await FirebaseService.getCurrentEateryId();
    if (eateryId == null || eateryId.trim().isEmpty) {
      throw Exception('No eatery linked');
    }
    final id = eateryId.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _settingsRef(id).set(
      {
        'eateryId': id,
        ...settings.toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    _cache = settings;
    _cacheEateryId = id;
  }

  static void clearCache() {
    _cache = null;
    _cacheEateryId = '';
  }
}
