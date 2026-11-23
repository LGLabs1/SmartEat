import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';
import '../services/api_service.dart';
import '../utils/attendance_utils.dart';
import 'attendance_settings_service.dart';
import 'firebase_service.dart';
import 'sms_service.dart';

/// Handles periodic notification checks for various system events
class NotificationTriggerManager {
  static final NotificationTriggerManager _instance =
      NotificationTriggerManager._internal();
  factory NotificationTriggerManager() => _instance;
  NotificationTriggerManager._internal();

  final NotificationService _notificationService = NotificationService();
  Timer? _periodicCheckTimer;
  StreamSubscription<User?>? _authSubscription;

  // Track last notification times to avoid spam
  final Map<String, DateTime> _lastNotifications = {};
  final Map<String, List<String>> _notifiedItemIds = {};

  /// Start periodic checks once auth is ready (every 30 minutes while active)
  void startPeriodicChecks() {
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        stopPeriodicChecks();
        return;
      }
      _startForSignedInUser();
    });
  }

  void _startForSignedInUser() {
    _runAllChecks();
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _runAllChecks(),
    );
  }

  /// Stop periodic checks
  void stopPeriodicChecks() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }

  /// Run all notification checks
  Future<void> _runAllChecks() async {
    final profile = await _loadCurrentProfile();
    final isAdmin = _profileIsAdmin(profile);

    await Future.wait([
      _checkPendingOrders(),
      if (isAdmin) _checkLowStock(),
      if (isAdmin) _checkUpcomingBills(),
    ]);
    try {
      await _checkAttendanceReminders(profile);
    } catch (_) {}
    // SMS app-open catch-up (independent of local notification settings)
    try {
      await _checkSmsDailyCatchUp();
    } catch (_) {}
    // In-app pending staff approval feed (independent of local settings)
    try {
      await _checkPendingStaffApprovals();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadCurrentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  bool _profileIsAdmin(Map<String, dynamic>? profile) {
    final role = (profile?['role'] ?? '').toString().toLowerCase();
    return profile?['isAdmin'] == true ||
        profile?['isAdmin'] == 'true' ||
        profile?['isAdmin'] == 1 ||
        role == 'admin';
  }

  String _dateKey(DateTime date) => attendanceYmd(date);

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
      if (!_profileIsAdmin(profile)) return;
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      if (eateryId.isEmpty) return;

      final pendingSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('eateryId', isEqualTo: eateryId)
          .get();

      for (final doc in pendingSnap.docs) {
        final data = doc.data();
        if (_profileIsAdmin(data) || data['approved'] != false) continue;
        final name = _displayName(data);
        await _notificationService.persistFeedNotification(
          title: 'New staff awaiting approval',
          body: '$name has joined your eatery and needs approval.',
          type: 'staff_approval',
          source: 'staff',
          audience: 'admin',
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

  /// Reminds the signed-in user to time in at their scheduled start and to
  /// time out after a full shift. Each reminder is deduped per user per day.
  Future<void> _checkAttendanceReminders([
    Map<String, dynamic>? profile,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final data = profile ?? await _loadCurrentProfile();
    if (data == null) return;
    final eateryId = (data['eateryId'] ?? '').toString().trim();
    if (eateryId.isEmpty) return;

    try {
      final settings = await AttendanceSettingsService.loadForEatery(eateryId);
      final attendance = await FirebaseService.getTodayAttendance(
        eateryId: eateryId,
        uid: user.uid,
      );
      final now = DateTime.now();
      final dateKey = _dateKey(now);
      final timeIn = attendance?['timeIn'];
      final timeOut = attendance?['timeOut'];
      final workUnit = attendance?['workUnit'];
      final encodedWithoutClock = timeIn == null &&
          attendance != null &&
          (attendance['present'] == true || (workUnit is num && workUnit > 0));

      final scheduledStart =
          attendanceScheduledStartFor(now, settings.scheduledStart);
      if (timeIn == null && !encodedWithoutClock && scheduledStart != null) {
        final due = scheduledStart.add(
          Duration(minutes: settings.graceMinutes),
        );
        if (!now.isBefore(due)) {
          await _notificationService.showNotification(
            title: 'Time In Reminder',
            body:
                'Your shift was scheduled to start at ${formatAttendanceClock(scheduledStart)}. Tap Time In when you begin.',
            payload: 'attendance',
            type: 'attendance',
            source: 'attendance',
            audience: 'staff',
            targetUids: <String>[user.uid],
            dedupeKey: 'attendance_start_${user.uid}_$dateKey',
            preserveReadState: true,
            data: {
              'target': 'profile',
              'attendanceUid': user.uid,
              'date': dateKey,
            },
          );
        }
      }

      if (timeIn != null && timeOut == null) {
        final startedAt = attendanceAsDateTime(timeIn);
        if (startedAt != null) {
          final elapsed = now.difference(startedAt);
          final fullShift = Duration(
            minutes: (settings.fullDayHours * 60).round(),
          );
          if (!elapsed.isNegative && elapsed >= fullShift) {
            await _notificationService.showNotification(
              title: 'Time Out Reminder',
              body:
                  'You have been on shift for ${formatAttendanceDuration(elapsed)}. Remember to Time Out when you finish.',
              payload: 'attendance',
              type: 'attendance',
              source: 'attendance',
              audience: 'staff',
              targetUids: <String>[user.uid],
              dedupeKey: 'attendance_end_${user.uid}_$dateKey',
              preserveReadState: true,
              data: {
                'target': 'profile',
                'attendanceUid': user.uid,
                'date': dateKey,
              },
            );
          }
        }
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
      if (!_profileIsAdmin(profile)) return;
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      if (eateryId.isEmpty) return;
      await SmsService.sendBillReminders(eateryId: eateryId);
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

      final itemDetails = newItems
          .map(
            (item) => <String, dynamic>{
              'id': (item['id'] ?? '').toString(),
              'name': (item['name'] ?? 'Unknown item').toString(),
              'quantity': item['quantity'] ?? item['currentQuantity'] ?? 0,
              'threshold': item['reorderPoint'] ?? item['minStock'] ?? 0,
            },
          )
          .toList();
      final itemNames = itemDetails
          .map((item) => item['name'].toString())
          .where((name) => name.isNotEmpty)
          .toList();
      final message = itemNames.length == 1
          ? '${itemNames.first} is low on stock.'
          : '${itemNames.join(', ')} are low on stock.';

      await _notificationService.showNotification(
        title: 'Low Stock Alert',
        body: message,
        payload: 'low_stock',
        type: 'low_stock',
        source: 'inventory',
        audience: 'admin',
        dedupeKey: 'low_stock_alert_${_dateKey(now)}_${now.hour}',
        data: <String, dynamic>{
          'items': itemDetails,
          'itemNames': itemNames,
          'details': itemNames,
          'target': 'inventory',
          'route': 'inventory',
          'ignoreKey': 'low_stock_alert',
        },
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
      type: 'bill_overdue',
      source: 'payable',
      audience: 'admin',
      dedupeKey: 'bill_overdue_alert_${_dateKey(now)}',
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
      type: 'bill_due_soon',
      source: 'payable',
      audience: 'admin',
      dedupeKey: 'bill_due_soon_alert_${_dateKey(now)}',
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
        type: 'order',
        source: 'orders',
        audience: 'all',
        dedupeKey:
            'pending_orders_${_dateKey(now)}_${now.hour}_${now.minute ~/ 30}',
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
      case 'attendance':
        await _checkAttendanceReminders();
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
