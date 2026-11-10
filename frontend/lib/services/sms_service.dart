import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/sms_config.dart';
import '../utils/phone_utils.dart';
import 'api_service.dart';
import 'sms_settings_service.dart';

class SmsSendResult {
  const SmsSendResult({
    required this.status,
    this.messageId,
    this.error,
  });

  final String status; // sent | failed | skipped
  final String? messageId;
  final String? error;
}

class SmsService {
  SmsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String _sanitizeSenderId(String senderId) {
    String s = senderId.trim();
    if (s.isEmpty) return SmsConfig.defaultSenderId;
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (s.isEmpty) return SmsConfig.defaultSenderId;
    if (s.length > 11) s = s.substring(0, 11);
    return s;
  }

  static String _clampMessage(String message, {int maxLength = 459}) {
    if (message.length <= maxLength) return message;
    return '${message.substring(0, maxLength - 3)}...';
  }

  static String _maskPhone(String? phone) {
    final normalized = PhoneUtils.normalizePhMobile(phone);
    if (normalized == null || normalized.length < 7) return 'Not set';
    final local = normalized.substring(2);
    return '+63 ${local[0]}** *** ${local.substring(6)}';
  }

  static String _manilaDateKey(DateTime date) {
    final utc = date.toUtc();
    final manila = utc.add(const Duration(hours: 8));
    final y = manila.year.toString().padLeft(4, '0');
    final m = manila.month.toString().padLeft(2, '0');
    final d = manila.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _safeDocId(String value) {
    return value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-')
        .substring(0, value.length > 200 ? 200 : value.length);
  }

  static Future<SmsAdminContact> _loadAdminContact(String eateryId) async {
    return SmsSettingsService.loadAdminContact(eateryId);
  }

  static Future<SmsSettings> _loadSettings(String eateryId) async {
    return SmsSettingsService.loadSettings(eateryId);
  }

  static Future<void> _logSms({
    required String eateryId,
    required String type,
    required String status,
    String? dedupeKey,
    String? recipient,
    String? messagePreview,
    String? messageId,
    String? error,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final logRef = _firestore
          .collection('eateries')
          .doc(eateryId)
          .collection('sms_logs')
          .doc(dedupeKey ?? '${type}_${DateTime.now().millisecondsSinceEpoch}');
      final preview = messagePreview ?? '';
      final err = error ?? '';
      await logRef.set({
        'type': type,
        'status': status,
        'recipient': _maskPhone(recipient),
        'messagePreview': preview.length > 160 ? preview.substring(0, 160) : preview,
        if (dedupeKey != null) 'dedupeKey': dedupeKey,
        if (messageId != null && messageId.isNotEmpty) 'providerMessageId': messageId,
        if (err.isNotEmpty) 'error': err.length > 500 ? err.substring(0, 500) : err,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }



  static Future<SmsSendResult> _send({
    required String eateryId,
    required String type,
    required String message,
    required String recipient,
    String? senderId,
    String? dedupeKey,
    bool requireEnabled = true,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const SmsSendResult(status: 'failed', error: 'Unauthenticated');
      }

      final settings = await _loadSettings(eateryId);
      if (requireEnabled && !settings.enabled) {
        return const SmsSendResult(status: 'skipped');
      }

      final normalizedRecipient = PhoneUtils.normalizePhMobile(recipient);
      if (normalizedRecipient == null) {
        await _logSms(
          eateryId: eateryId,
          type: type,
          status: 'failed',
          recipient: recipient,
          messagePreview: message,
          error: 'Invalid recipient number',
          dedupeKey: dedupeKey,
        );
        return const SmsSendResult(status: 'failed', error: 'Invalid recipient number');
      }

      final clampedMessage = _clampMessage(message);
      try {
        final data = await ApiService.sendSmsMessage(
          phoneNumber: normalizedRecipient,
          message: clampedMessage,
        );
        final messageId = data['message_id']?.toString() ?? data['id']?.toString() ?? data['messageId']?.toString();
        await _logSms(
          eateryId: eateryId,
          type: type,
          status: 'sent',
          recipient: normalizedRecipient,
          messagePreview: clampedMessage,
          messageId: messageId,
          dedupeKey: dedupeKey,
        );
        return SmsSendResult(status: 'sent', messageId: messageId);
      } catch (e) {
        final err = e.toString().replaceFirst('Exception: ', '');
        await _logSms(
          eateryId: eateryId,
          type: type,
          status: 'failed',
          recipient: normalizedRecipient,
          messagePreview: clampedMessage,
          error: err,
          dedupeKey: dedupeKey,
        );
        return SmsSendResult(status: 'failed', error: err);
      }
    } catch (e) {
      await _logSms(
        eateryId: eateryId,
        type: type,
        status: 'failed',
        recipient: recipient,
        messagePreview: message,
        error: e.toString(),
        dedupeKey: dedupeKey,
      );
      return SmsSendResult(status: 'failed', error: e.toString());
    }
  }

  static Future<SmsSendResult> sendTestSms(String eateryId) async {
    try {
      final contact = await _loadAdminContact(eateryId);
      if (contact.phone == null || !PhoneUtils.isValidPhMobile(contact.phone)) {
        return const SmsSendResult(status: 'failed', error: 'Add a valid mobile number to the admin profile first');
      }
      final settings = await _loadSettings(eateryId);
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final time = '${now.month}/${now.day}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final message = 'SmartEat: Test SMS for ${contact.eateryName} at $time. Alerts work.';
      final result = await _send(
        eateryId: eateryId,
        type: 'test',
        message: message,
        recipient: contact.phone!,
        senderId: settings.senderId,
        dedupeKey: 'test_${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
        requireEnabled: false,
      );
      return result;
    } catch (e) {
      return SmsSendResult(status: 'failed', error: e.toString());
    }
  }

  static Future<SmsSendResult> sendLowStock({
    required String eateryId,
    required String itemId,
    required String itemName,
    required double currentStock,
    required String unit,
    required double threshold,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SmsSendResult(status: 'skipped');
    final settings = await _loadSettings(eateryId);
    if (!settings.enabled || !settings.lowStockEnabled) {
      return const SmsSendResult(status: 'skipped');
    }
    final contact = await _loadAdminContact(eateryId);
    if (contact.phone == null || !PhoneUtils.isValidPhMobile(contact.phone)) {
      return const SmsSendResult(status: 'skipped');
    }

    // cooldown
    try {
      final stateRef = _firestore
          .collection('eateries')
          .doc(eateryId)
          .collection('sms_alert_state')
          .doc('low_stock_${_safeDocId(itemId)}');
      final stateSnap = await stateRef.get();
      final last = stateSnap.data()?['lastLowStockAt'];
      if (last is Timestamp) {
        if (DateTime.now().difference(last.toDate()).inHours < 6) {
          return const SmsSendResult(status: 'skipped');
        }
      }
      await stateRef.set({
        'itemId': itemId,
        'lastLowStockAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    String message;
    if (currentStock <= 0) {
      message = 'SmartEat: OUT OF STOCK - $itemName. Reorder now.';
    } else {
      final stockStr = currentStock == currentStock.roundToDouble() ? currentStock.toInt().toString() : currentStock.toString();
      final threshStr = threshold == threshold.roundToDouble() ? threshold.toInt().toString() : threshold.toString();
      final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
      message = 'SmartEat: LOW STOCK - $itemName: $stockStr$unitSuffix left (threshold $threshStr$unitSuffix).';
    }

    final result = await _send(
      eateryId: eateryId,
      type: 'low_stock',
      message: message,
      recipient: contact.phone!,
      senderId: settings.senderId,
      dedupeKey: 'low_stock_${_safeDocId(itemId)}_${DateTime.now().millisecondsSinceEpoch}',
    );
    return result;
  }

  static Future<SmsSendResult> sendBillReminders({
    required String eateryId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SmsSendResult(status: 'skipped');
    final settings = await _loadSettings(eateryId);
    if (!settings.enabled || !settings.billRemindersEnabled) {
      return const SmsSendResult(status: 'skipped');
    }
    final contact = await _loadAdminContact(eateryId);
    if (contact.phone == null || !PhoneUtils.isValidPhMobile(contact.phone)) {
      return const SmsSendResult(status: 'skipped');
    }

    final prefs = await SharedPreferences.getInstance();
    final dateKey = _manilaDateKey(DateTime.now());
    final prefKey = 'sms_bill_reminder_sent_${eateryId}_$dateKey';
    if (prefs.getBool(prefKey) == true) {
      return const SmsSendResult(status: 'skipped');
    }

    try {
      final payablesSnap = await _firestore
          .collection('eateries')
          .doc(eateryId)
          .collection('payables')
          .get();
      final bills = <Map<String, dynamic>>[];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final doc in payablesSnap.docs) {
        final payable = doc.data();
        final status = (payable['status'] ?? 'unpaid').toString().toLowerCase();
        if (status == 'paid') continue;
        final dueDate = payable['dueDate'];
        DateTime? due;
        if (dueDate is Timestamp) due = dueDate.toDate();
        if (due == null) continue;
        final dueDay = DateTime(due.year, due.month, due.day);
        final diff = dueDay.difference(today).inDays;
        if (diff > settings.billReminderDays) continue;
        final amount = (payable['amount'] ?? payable['lastAmount'] ?? 0);
        bills.add({
          'name': payable['name'] ?? 'Bill',
          'amount': amount,
          'days': diff,
        });
      }
      if (bills.isEmpty) return const SmsSendResult(status: 'skipped');

      bills.sort((a, b) => (a['days'] as int).compareTo(b['days'] as int));
      final lines = bills.take(3).map((bill) {
        final name = (bill['name'] as String);
        final shortName = name.length > 28 ? name.substring(0, 28) : name;
        final amount = bill['amount'] is num ? bill['amount'] as num : 0;
        final amountText = amount > 0 ? ' PHP${amount.toString()}' : ' variable';
        final days = bill['days'] as int;
        final dueText = days < 0 ? ' overdue ${-days}d' : days == 0 ? ' due today' : ' due in ${days}d';
        return '$shortName$amountText$dueText';
      }).join('; ');
      final more = bills.length > 3 ? ' +${bills.length - 3} more' : '';
      final verb = bills.length == 1 ? 'needs' : 'need';
      final message = 'SmartEat: ${bills.length} bill${bills.length == 1 ? '' : 's'} $verb attention. $lines$more.';

      final result = await _send(
        eateryId: eateryId,
        type: 'bill_reminder',
        message: message,
        recipient: contact.phone!,
        senderId: settings.senderId,
        dedupeKey: 'bill_reminders_$dateKey',
      );
      if (result.status == 'sent') {
        await prefs.setBool(prefKey, true);
      }
      return result;
    } catch (e) {
      return SmsSendResult(status: 'failed', error: e.toString());
    }
  }

  static Future<SmsSendResult> sendDailySummary({
    required String eateryId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SmsSendResult(status: 'skipped');
    final settings = await _loadSettings(eateryId);
    if (!settings.enabled || !settings.dailySummaryEnabled) {
      return const SmsSendResult(status: 'skipped');
    }
    final contact = await _loadAdminContact(eateryId);
    if (contact.phone == null || !PhoneUtils.isValidPhMobile(contact.phone)) {
      return const SmsSendResult(status: 'skipped');
    }

    final prefs = await SharedPreferences.getInstance();
    final dateKey = _manilaDateKey(DateTime.now());
    final prefKey = 'sms_daily_summary_sent_${eateryId}_$dateKey';
    if (prefs.getBool(prefKey) == true) {
      return const SmsSendResult(status: 'skipped');
    }

    try {
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final startUtc = start.toUtc().subtract(const Duration(hours: 8));
      final endUtc = end.toUtc().subtract(const Duration(hours: 8));
      final ordersSnap = await _firestore
          .collection('eateries')
          .doc(eateryId)
          .collection('orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc))
          .where('createdAt', isLessThan: Timestamp.fromDate(endUtc))
          .get();

      int orderCount = 0;
      double revenue = 0;
      final itemQty = <String, int>{};
      for (final doc in ordersSnap.docs) {
        final order = doc.data();
        final status = (order['status'] ?? '').toString().toLowerCase();
        if (status != 'completed') continue;
        orderCount++;
        revenue += (order['totalAmount'] is num) ? (order['totalAmount'] as num).toDouble() : 0;
        final items = order['items'] as List?;
        if (items != null) {
          for (final item in items) {
            if (item is Map) {
              final name = (item['name'] ?? '').toString();
              final qty = item['quantity'] is num ? (item['quantity'] as num).toInt() : 0;
              if (name.isNotEmpty && qty > 0) {
                itemQty[name] = (itemQty[name] ?? 0) + qty;
              }
            }
          }
        }
      }
      if (orderCount == 0) return const SmsSendResult(status: 'skipped');

      String topText = '';
      if (itemQty.isNotEmpty) {
        final sorted = itemQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final top = sorted.first;
        topText = ' Top: ${top.key} (${top.value} sold).';
      }
      final revenueStr = revenue == revenue.roundToDouble() ? revenue.toInt().toString() : revenue.toStringAsFixed(0);
      final message = 'SmartEat: Today $orderCount order${orderCount == 1 ? '' : 's'}, PHP$revenueStr.$topText';

      final result = await _send(
        eateryId: eateryId,
        type: 'daily_summary',
        message: message,
        recipient: contact.phone!,
        senderId: settings.senderId,
        dedupeKey: 'daily_summary_$dateKey',
      );
      if (result.status == 'sent') {
        await prefs.setBool(prefKey, true);
      }
      return result;
    } catch (e) {
      return SmsSendResult(status: 'failed', error: e.toString());
    }
  }
}
