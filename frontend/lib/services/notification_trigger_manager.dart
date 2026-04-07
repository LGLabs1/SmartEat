import 'dart:async';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';
import '../services/api_service.dart';

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

  /// Start periodic checks (runs every 15 minutes when app is active)
  void startPeriodicChecks() {
    // Initial check
    _runAllChecks();

    // Periodic check every 15 minutes
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(minutes: 15),
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
    debugPrint('Running notification checks...');

    if (!_notificationService.notificationsEnabled) return;

    await Future.wait([
      _checkLowStock(),
      _checkUpcomingBills(),
      _checkPendingOrders(),
    ]);
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
      if (lastCheck != null &&
          now.difference(lastCheck).inMinutes < 60) {
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

      debugPrint('Low stock notification sent: $message');
    } catch (e) {
      debugPrint('Error checking low stock: $e');
    }
  }

  /// Check for upcoming bills and notify
  Future<void> _checkUpcomingBills() async {
    if (!_notificationService.billRemindersEnabled) return;

    try {
      final response = await ApiService.getPayables();
      final bills = response['data'] as List<dynamic>? ?? [];

      if (bills.isEmpty) return;

      final now = DateTime.now();
      final reminderDays = _notificationService.billReminderDays;
      final reminderDate = now.add(Duration(days: reminderDays));

      // Find bills due within the reminder window
      final upcomingBills = bills.where((bill) {
        final status = (bill['status'] ?? '').toString().toLowerCase();
        if (status == 'paid') return false;

        final dueDate = _parseDate(bill['dueDate']);
        if (dueDate == null) return false;

        // Due between now and reminder date
        return dueDate.isAfter(now.subtract(const Duration(days: 1))) &&
            dueDate.isBefore(reminderDate.add(const Duration(days: 1)));
      }).toList();

      if (upcomingBills.isEmpty) return;

      final lastCheckKey = 'upcoming_bills';
      final lastCheck = _lastNotifications[lastCheckKey];

      // Only notify once per day for bills
      if (lastCheck != null &&
          now.difference(lastCheck).inHours < 24) {
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
      final amountText = amount != null && amount > 0
          ? ' (₱${amount.toStringAsFixed(2)})'
          : '';

      final message = upcomingBills.length == 1
          ? '$billName is due $timeText$amountText'
          : '$billName due $timeText and ${upcomingBills.length - 1} other bills upcoming';

      await _notificationService.showNotification(
        title: 'Upcoming Bill',
        body: message,
        payload: 'upcoming_bills',
      );

      _lastNotifications[lastCheckKey] = now;
      debugPrint('Bill notification sent: $message');
    } catch (e) {
      debugPrint('Error checking upcoming bills: $e');
    }
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
      if (lastCheck != null &&
          now.difference(lastCheck).inMinutes < 30) {
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
      debugPrint('Pending orders notification sent: $message');
    } catch (e) {
      debugPrint('Error checking pending orders: $e');
    }
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
