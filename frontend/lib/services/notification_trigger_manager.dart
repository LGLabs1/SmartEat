import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';
import '../services/api_service.dart';
import 'sms_service.dart';

/// Handles periodic notification checks for various system events
class NotificationTriggerManager {
  static final NotificationTriggerManager _instance =
      NotificationTriggerManager._internal();
  factory NotificationTriggerManager() => _instance;
  NotificationTriggerManager._internal();

  final NotificationService _notificationService = NotificationService();
  Timer? _periodicCheckTimer;

  // Track last notification times to avoid spam
  final Map<String, DateTime> _lastNotifications = {};
  final Map<String, List<String>> _notifiedItemIds = {};

  /// Start periodic checks (runs every 30 minutes when app is active)
  void startPeriodicChecks() {
    if (FirebaseAuth.instance.currentUser == null) {
      print('===== FIRESTORE STARTUP GUARD =====');
      print('Notification triggers skipped because auth user is null.');
      print('Current UID: ${FirebaseAuth.instance.currentUser?.uid ?? 'N/A'}');
      print('===================================');
      return;
    }

    // Initial check
    _runAllChecks();

    // Periodic check every 30 minutes
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _runAllChecks(),
    );
  }

  /// Stop periodic checks
  void stopPeriodicChecks() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }

  /// Run all notification checks
  Future<void> _runAllChecks() async {
    if (_notificationService.notificationsEnabled) {
      await Future.wait([
        _checkLowStock(),
        _checkUpcomingBills(),
        _checkPendingOrders(),
      ]);
    }
    // SMS app-open catch-up (independent of local notification settings)
    try {
      await _checkSmsDailyCatchUp();
    } catch (_) {}
    // In-app pending staff approval feed (independent of local settings)
    try {
      await _checkPendingStaffApprovals();
    } catch (_) {}
  }

  /// Create one in-app notification per unapproved staff member in the
  /// admin's eatery. Existing notifications keep their read state.
  Future<void> _checkPendingStaffApprovals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final profile = userSnap.data();
      final role = (profile?['role'] ?? '').toString().toLowerCase();
      final isAdmin = profile?['isAdmin'] == true || role == 'admin';
      if (!isAdmin) return;
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      if (eateryId.isEmpty) return;

      final pendingSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('eateryId', isEqualTo: eateryId)
          .get();

      for (final doc in pendingSnap.docs) {
        final data = doc.data();
        final staffRole = (data['role'] ?? '').toString().toLowerCase();
        final staffIsAdmin = data['isAdmin'] == true || staffRole == 'admin';
        if (staffIsAdmin || data['approved'] != false) continue;
        final name = _displayName(data);
        await _notificationService.persistFeedNotification(
          title: 'New staff awaiting approval',
          body: '$name has joined your eatery and needs approval.',
          type: 'staff_approval',
          source: 'staff',
          eateryId: eateryId,
          dedupeKey: 'pending_staff_${doc.id}',
          preserveReadState: true,
          data: {
            'staffUid': doc.id,
            'staffName': name,
            'target': 'staff',
          },
        );
      }
    } catch (_) {}
  }

  String _displayName(Map<String, dynamic> data) {
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    final name = (data['name'] ?? data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    return email.isNotEmpty ? email : 'A new staff member';
  }

  Future<void> _checkSmsDailyCatchUp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final profile = userSnap.data();
      final role = (profile?['role'] ?? '').toString().toLowerCase();
      final isAdmin = profile?['isAdmin'] == true || role == 'admin';
      if (!isAdmin) return;
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      if (eateryId.isEmpty) return;
      await SmsService.sendBillReminders(eateryId: eateryId);
      await SmsService.sendDailySummary(eateryId: eateryId);
    } catch (_) {}
  }

  /// Check for low stock items and notify
  Future<void> _checkLowStock() async {
    if (!_notificationService.lowStockEnabled) return;

    try {
      final response = await ApiService.getLowStockItems();
      final items = response['data'] as List<dynamic>? ?? [];

      if (items.isEmpty) return;

      final now = DateTime.now();
      final lastCheckKey = 'low_stock';
      final lastCheck = _lastNotifications[lastCheckKey];

      // Only notify once per hour for low stock
      if (lastCheck != null && now.difference(lastCheck).inMinutes < 60) {
        return;
      }

      // Filter items we haven't notified about yet
      final notifiedIds = _notifiedItemIds[lastCheckKey] ?? [];
      final newItems = items.where((item) {
        final id = item['id']?.toString() ?? '';
        return id.isNotEmpty && !notifiedIds.contains(id);
      }).toList();

      if (newItems.isEmpty) {
        // Reset if all items have been notified (new check cycle)
        if (notifiedIds.length >= items.length) {
          _notifiedItemIds[lastCheckKey] = [];
        }
        return;
      }

      // Build notification message
      final count = newItems.length;
      final firstItem = newItems.first['name']?.toString() ?? 'Unknown item';
      final message = count == 1
          ? '$firstItem is low on stock'
          : '$firstItem and ${count - 1} other items are low on stock';

      await _notificationService.showNotification(
        title: 'Low Stock Alert',
        body: message,
        payload: 'low_stock',
      );

      // Track notified items
      _notifiedItemIds[lastCheckKey] = [
        ...notifiedIds,
        ...newItems.map((i) => i['id'].toString()),
      ];
      _lastNotifications[lastCheckKey] = now;
    } catch (e) {}
  }

  /// Check for upcoming bills and notify
  Future<void> _checkUpcomingBills() async {
    if (!_notificationService.billRemindersEnabled) return;

    try {
      final response = await ApiService.getPayables();
      final bills = response['data'] as List<dynamic>? ?? [];

      if (bills.isEmpty) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final reminderDays = _notificationService.billReminderDays;
      final reminderDate = now.add(Duration(days: reminderDays));

      // Separate overdue and upcoming bills
      final overdueBills = <dynamic>[];
      final upcomingBills = <dynamic>[];

      for (final bill in bills) {
        final status = (bill['status'] ?? '').toString().toLowerCase();
        if (status == 'paid') continue;

        final dueDate = _parseDate(bill['dueDate']);
        if (dueDate == null) continue;

        final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);

        if (dueDay.isBefore(today)) {
          // Overdue
          overdueBills.add(bill);
        } else if (dueDay.isBefore(reminderDate.add(const Duration(days: 1)))) {
          // Due soon (within reminder window)
          upcomingBills.add(bill);
        }
      }

      // Check and notify for overdue bills (higher priority)
      if (overdueBills.isNotEmpty) {
        await _notifyOverdueBills(overdueBills, now);
      }

      if (upcomingBills.isNotEmpty) {
        await _notifyUpcomingBills(upcomingBills, now);
      }
    } catch (e) {}
  }

  /// Send notifications for overdue bills
  Future<void> _notifyOverdueBills(
      List<dynamic> overdueBills, DateTime now) async {
    final lastCheckKey = 'overdue_bills';
    final lastCheck = _lastNotifications[lastCheckKey];

    // Notify once per day for overdue bills
    if (lastCheck != null && now.difference(lastCheck).inHours < 24) {
      return;
    }

    // Sort by most overdue first
    overdueBills.sort((a, b) {
      final aDate = _parseDate(a['dueDate']) ?? now;
      final bDate = _parseDate(b['dueDate']) ?? now;
      return aDate.compareTo(bDate);
    });

    final mostOverdue = overdueBills.first;
    final billName = mostOverdue['name']?.toString() ?? 'Bill';
    final dueDate = _parseDate(mostOverdue['dueDate']);
    final daysOverdue = dueDate != null
        ? now
            .difference(DateTime(dueDate.year, dueDate.month, dueDate.day))
            .inDays
        : 0;

    final amount = mostOverdue['amount'];
    final amountText =
        amount != null && amount > 0 ? ' (₱${amount.toStringAsFixed(2)})' : '';

    final message = overdueBills.length == 1
        ? '$billName is $daysOverdue days overdue$amountText. Tap to pay now.'
        : '$billName is $daysOverdue days overdue$amountText and ${overdueBills.length - 1} other bills are overdue.';

    await _notificationService.showNotification(
      title: 'Overdue Bill Alert',
      body: message,
      payload: 'bill_overdue',
    );

    _lastNotifications[lastCheckKey] = now;
  }

  /// Send notifications for upcoming bills
  Future<void> _notifyUpcomingBills(
      List<dynamic> upcomingBills, DateTime now) async {
    final lastCheckKey = 'upcoming_bills';
    final lastCheck = _lastNotifications[lastCheckKey];

    // Only notify once per day for upcoming bills
    if (lastCheck != null && now.difference(lastCheck).inHours < 24) {
      return;
    }

    // Get earliest due bill
    upcomingBills.sort((a, b) {
      final aDate = _parseDate(a['dueDate']) ?? now;
      final bDate = _parseDate(b['dueDate']) ?? now;
      return aDate.compareTo(bDate);
    });

    final earliestBill = upcomingBills.first;
    final billName = earliestBill['name']?.toString() ?? 'Bill';
    final dueDate = _parseDate(earliestBill['dueDate']);
    final daysUntil = dueDate?.difference(now).inDays ?? 0;

    String timeText;
    if (daysUntil == 0) {
      timeText = 'today';
    } else if (daysUntil == 1) {
      timeText = 'tomorrow';
    } else {
      timeText = 'in $daysUntil days';
    }

    final amount = earliestBill['amount'];
    final amountText =
        amount != null && amount > 0 ? ' (₱${amount.toStringAsFixed(2)})' : '';

    final message = upcomingBills.length == 1
        ? '$billName is due $timeText$amountText'
        : '$billName due $timeText and ${upcomingBills.length - 1} other bills upcoming';

    await _notificationService.showNotification(
      title: 'Bill Due Soon',
      body: message,
      payload: 'bill_due_soon',
    );

    _lastNotifications[lastCheckKey] = now;
  }

  /// Check for pending orders and notify (mainly for admin/staff)
  Future<void> _checkPendingOrders() async {
    if (!_notificationService.orderAlertsEnabled) return;

    try {
      final response = await ApiService.getTodayOrders();
      final orders = response['data'] as List<dynamic>? ?? [];

      if (orders.isEmpty) return;

      // Count pending orders
      final pendingOrders = orders.where((order) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        return status == 'pending' || status == 'preparing';
      }).toList();

      if (pendingOrders.isEmpty) return;

      final now = DateTime.now();
      final lastCheckKey = 'pending_orders';
      final lastCheck = _lastNotifications[lastCheckKey];

      // Only notify every 30 minutes for pending orders
      if (lastCheck != null && now.difference(lastCheck).inMinutes < 30) {
        return;
      }

      final count = pendingOrders.length;
      final message = count == 1
          ? 'You have 1 pending order awaiting action'
          : 'You have $count pending orders awaiting action';

      await _notificationService.showNotification(
        title: 'Pending Orders',
        body: message,
        payload: 'pending_orders',
      );

      _lastNotifications[lastCheckKey] = now;
    } catch (e) {}
  }

  /// Parse date from various formats
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      // Try parsing ISO 8601
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Manual trigger for immediate checks (can be called from UI)
  Future<void> runImmediateCheck(String type) async {
    switch (type) {
      case 'low_stock':
        await _checkLowStock();
        break;
      case 'upcoming_bills':
        await _checkUpcomingBills();
        break;
      case 'pending_orders':
        await _checkPendingOrders();
        break;
      case 'pending_staff':
        await _checkPendingStaffApprovals();
        break;
      default:
        await _runAllChecks();
    }
  }

  /// Clear notification history (useful for testing or user reset)
  void clearNotificationHistory() {
    _lastNotifications.clear();
    _notifiedItemIds.clear();
  }

  /// Dispose
  void dispose() {
    stopPeriodicChecks();
  }
}
