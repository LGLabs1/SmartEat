import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/phone_utils.dart';
import 'sms_service.dart';

class SmsSettings {
  const SmsSettings({
    this.enabled = false,
    this.senderId = 'SmartEat',
    this.lowStockEnabled = true,
    this.billRemindersEnabled = true,
    this.billReminderDays = 3,
    this.dailySummaryEnabled = true,
  });

  final bool enabled;
  final String senderId;
  final bool lowStockEnabled;
  final bool billRemindersEnabled;
  final int billReminderDays;
  final bool dailySummaryEnabled;

  factory SmsSettings.fromMap(Map<String, dynamic>? data) {
    final rawDays = data?['billReminderDays'];
    final days = rawDays is num
        ? rawDays.round()
        : int.tryParse(rawDays?.toString() ?? '') ?? 3;

    return SmsSettings(
      enabled: data?['enabled'] == true,
      senderId: (data?['senderId'] ?? 'SmartEat').toString().trim().isEmpty
          ? 'SmartEat'
          : (data?['senderId'] ?? 'SmartEat').toString().trim(),
      lowStockEnabled: data?['lowStockEnabled'] != false,
      billRemindersEnabled: data?['billRemindersEnabled'] != false,
      billReminderDays: days.clamp(1, 30).toInt(),
      dailySummaryEnabled: data?['dailySummaryEnabled'] != false,
    );
  }

  SmsSettings copyWith({
    bool? enabled,
    String? senderId,
    bool? lowStockEnabled,
    bool? billRemindersEnabled,
    int? billReminderDays,
    bool? dailySummaryEnabled,
  }) {
    return SmsSettings(
      enabled: enabled ?? this.enabled,
      senderId: senderId ?? this.senderId,
      lowStockEnabled: lowStockEnabled ?? this.lowStockEnabled,
      billRemindersEnabled: billRemindersEnabled ?? this.billRemindersEnabled,
      billReminderDays: billReminderDays ?? this.billReminderDays,
      dailySummaryEnabled: dailySummaryEnabled ?? this.dailySummaryEnabled,
    );
  }
}

class SmsAdminContact {
  const SmsAdminContact({
    required this.phone,
    required this.eateryName,
  });

  final String? phone;
  final String eateryName;

  bool get hasPhone => PhoneUtils.isValidPhMobile(phone);
  String get maskedPhone => PhoneUtils.maskPhMobile(phone);
}

class SmsLogEntry {
  const SmsLogEntry({
    required this.type,
    required this.status,
    required this.createdAt,
    this.error,
  });

  final String type;
  final String status;
  final DateTime? createdAt;
  final String? error;
}

class SmsSettingsService {
  SmsSettingsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _settingsRef(
    String eateryId,
  ) {
    return _firestore
        .collection('eateries')
        .doc(eateryId)
        .collection('settings')
        .doc('sms');
  }

  static Future<SmsSettings> loadSettings(String eateryId) async {
    final snap = await _settingsRef(eateryId).get();
    return SmsSettings.fromMap(snap.data());
  }

  static Future<void> saveSettings({
    required String eateryId,
    required SmsSettings settings,
    required String uid,
  }) async {
    await _settingsRef(eateryId).set(
      {
        'eateryId': eateryId,
        'enabled': settings.enabled,
        'senderId': settings.senderId,
        'lowStockEnabled': settings.lowStockEnabled,
        'billRemindersEnabled': settings.billRemindersEnabled,
        'billReminderDays': settings.billReminderDays,
        'dailySummaryEnabled': settings.dailySummaryEnabled,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<SmsAdminContact> loadAdminContact(String eateryId) async {
    final eaterySnap =
        await _firestore.collection('eateries').doc(eateryId).get();
    final eatery = eaterySnap.data() ?? const <String, dynamic>{};
    final eateryName = (eatery['name'] ?? 'SmartEat').toString().trim();
    final ownerUid = (eatery['ownerUid'] ?? '').toString().trim();

    String? phone;
    if (ownerUid.isNotEmpty) {
      final userSnap = await _firestore.collection('users').doc(ownerUid).get();
      final user = userSnap.data() ?? const <String, dynamic>{};
      phone = PhoneUtils.normalizePhMobile(
        (user['phone'] ?? user['phoneNumber'])?.toString(),
      );

      if (phone == null) {
        final adminSnap = await _firestore
            .collection('eateries')
            .doc(eateryId)
            .collection('admin_profiles')
            .doc(ownerUid)
            .get();
        final admin = adminSnap.data() ?? const <String, dynamic>{};
        phone = PhoneUtils.normalizePhMobile(
          (admin['phone'] ?? admin['phoneNumber'])?.toString(),
        );
      }
    }

    return SmsAdminContact(
      phone: phone,
      eateryName: eateryName.isEmpty ? 'SmartEat' : eateryName,
    );
  }

  static Future<SmsLogEntry?> loadLatestLog(String eateryId) async {
    final snap = await _firestore
        .collection('eateries')
        .doc(eateryId)
        .collection('sms_logs')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    final rawCreatedAt = data['createdAt'];
    final createdAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.tryParse(rawCreatedAt?.toString() ?? '');

    return SmsLogEntry(
      type: (data['type'] ?? 'sms').toString(),
      status: (data['status'] ?? 'unknown').toString(),
      createdAt: createdAt,
      error: data['error']?.toString(),
    );
  }

  static Future<String?> sendTestSms(String? eateryId) async {
    if (eateryId == null || eateryId.isEmpty) {
      throw Exception('No eatery linked');
    }
    final result = await SmsService.sendTestSms(eateryId);
    if (result.status == 'sent') {
      return result.messageId;
    }
    throw Exception(result.error ?? 'Failed to send test SMS');
  }
}
