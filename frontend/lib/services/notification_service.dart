import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  // Settings
  bool _notificationsEnabled = true;
  bool _lowStockEnabled = true;
  bool _billRemindersEnabled = true;
  bool _orderAlertsEnabled = true;
  int _billReminderDays = 3; // Days before due date to remind

  // Getters
  String? get fcmToken => _fcmToken;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get lowStockEnabled => _lowStockEnabled;
  bool get billRemindersEnabled => _billRemindersEnabled;
  bool get orderAlertsEnabled => _orderAlertsEnabled;
  int get billReminderDays => _billReminderDays;

  /// Initialize the notification service
  Future<void> initialize() async {
    // Firebase Messaging and the local notifications plugin do not support
    // Windows/Linux desktop, so skip initialization there.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }
    try {
      // Request permission (especially important for iOS)
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // Set up background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Get FCM token
      _fcmToken = await _messaging.getToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
      });

      // Set up local notifications for foreground messages
      await _setupLocalNotifications();

      // Set up foreground message handler
      _onMessageSubscription =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Set up notification tap handler
      _onMessageOpenedAppSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Load user preferences
      await _loadPreferences();
    } catch (e) {
      // Don't rethrow - notifications are not critical to app function
    }
  }

  /// Set up local notifications plugin
  Future<void> _setupLocalNotifications() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Create notification channels for Android
      const androidChannel = AndroidNotificationChannel(
        'smarteat_channel',
        'Smart Eat Notifications',
        description: 'Notifications for Smart Eat app',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    } catch (e) {
      // Continue without local notifications - not critical
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? 'Smart Eat')
        .toString();
    final body = (notification?.body ?? message.data['body'] ?? '').toString();
    final type = (message.data['type'] ?? 'push').toString();
    final messageId = message.messageId;

    persistFeedNotification(
      title: title,
      body: body,
      type: type,
      source: 'push',
      dedupeKey: messageId != null && messageId.isNotEmpty
          ? 'push_$messageId'
          : 'push_${DateTime.now().millisecondsSinceEpoch}',
      data: {
        ...message.data,
        if (messageId != null) 'messageId': messageId,
        'target': message.data['target'] ?? message.data['route'],
      },
    );

    if (!_notificationsEnabled) return;
    if (title.isEmpty && body.isEmpty) return;

    _showLocalNotification(
      id: messageId?.hashCode ?? DateTime.now().millisecond,
      title: title,
      body: body,
      payload: message.data.toString(),
    );
  }

  /// Handle notification tap when app is in background
  void _handleMessageOpenedApp(RemoteMessage message) {
    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? 'Smart Eat')
        .toString();
    final body = (notification?.body ?? message.data['body'] ?? '').toString();
    final type = (message.data['type'] ?? 'push').toString();
    final messageId = message.messageId;

    persistFeedNotification(
      title: title,
      body: body,
      type: type,
      source: 'push',
      dedupeKey: messageId != null && messageId.isNotEmpty
          ? 'push_$messageId'
          : 'push_opened_${DateTime.now().millisecondsSinceEpoch}',
      data: {
        ...message.data,
        if (messageId != null) 'messageId': messageId,
        'target': message.data['target'] ?? message.data['route'],
        'openedFromNotification': true,
      },
    );
  }

  /// Handle local notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Navigation can be handled here based on payload
  }

  String _safeDocId(String raw) {
    final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safe.isEmpty) return 'notif_${DateTime.now().millisecondsSinceEpoch}';
    return safe.length > 180 ? safe.substring(0, 180) : safe;
  }

  Future<String?> _resolveEateryId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final eateryId = (doc.data()?['eateryId'] ?? '').toString().trim();
      return eateryId.isEmpty ? null : eateryId;
    } catch (_) {
      return null;
    }
  }

  /// Writes a notification into the in-app feed.
  ///
  /// When [preserveReadState] is true the notification is only created if it
  /// does not already exist, so read state is never reset on repeat checks.
  Future<void> persistFeedNotification({
    required String title,
    required String body,
    required String type,
    String source = 'system',
    String? dedupeKey,
    String? eateryId,
    Map<String, dynamic>? data,
    bool preserveReadState = false,
  }) async {
    try {
      final resolvedEateryId = eateryId ?? await _resolveEateryId();
      if (resolvedEateryId == null || resolvedEateryId.isEmpty) return;
      final effectiveDedupeKey = (dedupeKey != null && dedupeKey.isNotEmpty)
          ? dedupeKey
          : '${source}_${type}_${DateTime.now().millisecondsSinceEpoch}';
      final docId = _safeDocId(effectiveDedupeKey);
      final ref =
          FirebaseFirestore.instance.collection('notifications').doc(docId);
      final payload = <String, dynamic>{
        'eateryId': resolvedEateryId,
        'title': title,
        'body': body,
        'type': type,
        'source': source,
        'dedupeKey': effectiveDedupeKey,
        'data': data ?? <String, dynamic>{},
        'isRead': false,
        'readBy': <String, dynamic>{},
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existing = await ref.get();
      if (existing.exists && preserveReadState) return;
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await ref.set(payload, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Show a local notification
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'smarteat_channel',
      'Smart Eat Notifications',
      channelDescription: 'Notifications for Smart Eat app',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  /// Show a local notification manually
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String type = 'general',
    String source = 'local',
    String? dedupeKey,
    bool persist = true,
  }) async {
    if (persist) {
      await persistFeedNotification(
        title: title,
        body: body,
        type: type,
        source: source,
        dedupeKey: dedupeKey,
        data: payload == null ? null : {'payload': payload},
      );
    }

    if (!_notificationsEnabled) return;

    await _showLocalNotification(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Load user preferences from Firestore
  Future<void> _loadPreferences() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      print('===== FIRESTORE REQUEST =====');
      print('Collection: user_preferences');
      print('Document: ${user.uid}');
      print('Operation: get');
      print('Current UID: ${user.uid}');
      print('Current eateryId: N/A');
      print('============================');

      final doc = await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        _notificationsEnabled = data['notificationsEnabled'] ?? true;
        _lowStockEnabled = data['lowStockEnabled'] ?? true;
        _billRemindersEnabled = data['billRemindersEnabled'] ?? true;
        _orderAlertsEnabled = data['orderAlertsEnabled'] ?? true;
        _billReminderDays = data['billReminderDays'] ?? 3;
      }
    } catch (e, stackTrace) {
      print('===== FIRESTORE ERROR =====');
      print('Code: ${e is FirebaseException ? e.code : 'N/A'}');
      print(
          'Message: ${e is FirebaseException ? e.message ?? 'N/A' : e.toString()}');
      print('Stack: $stackTrace');
      print('==========================');
    }
  }

  /// Save user preferences to Firestore
  Future<void> savePreferences() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(user.uid)
          .set({
        'notificationsEnabled': _notificationsEnabled,
        'lowStockEnabled': _lowStockEnabled,
        'billRemindersEnabled': _billRemindersEnabled,
        'orderAlertsEnabled': _orderAlertsEnabled,
        'billReminderDays': _billReminderDays,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {}
  }

  /// Update notification settings
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    await savePreferences();
  }

  Future<void> setLowStockEnabled(bool enabled) async {
    _lowStockEnabled = enabled;
    await savePreferences();
  }

  Future<void> setBillRemindersEnabled(bool enabled) async {
    _billRemindersEnabled = enabled;
    await savePreferences();
  }

  Future<void> setOrderAlertsEnabled(bool enabled) async {
    _orderAlertsEnabled = enabled;
    await savePreferences();
  }

  Future<void> setBillReminderDays(int days) async {
    _billReminderDays = days.clamp(1, 30);
    await savePreferences();
  }

  /// Subscribe to topics
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Schedule a local notification
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_notificationsEnabled) return;

    // Note: For background scheduling, you may need additional plugins
    // like workmanager for more reliable delivery
    final now = DateTime.now();
    if (scheduledDate.isBefore(now)) return;

    final delay = scheduledDate.difference(now);
    Timer(delay, () {
      _showLocalNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
      );
    });
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// Cancel specific notification
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  /// Show low stock notification
  Future<void> showLowStockNotification({
    required String itemName,
    required double currentStock,
    required double minStock,
    String? itemId,
    bool persist = false,
  }) async {
    final title = 'Low Stock Alert';
    final body =
        '$itemName is running low (Current: $currentStock, Min: $minStock)';
    if (persist) {
      await persistFeedNotification(
        title: title,
        body: body,
        type: 'low_stock',
        source: 'inventory',
        dedupeKey: itemId != null && itemId.isNotEmpty
            ? 'low_stock_$itemId'
            : 'low_stock_$itemName',
        data: {
          'itemName': itemName,
          'currentStock': currentStock,
          'minStock': minStock,
          if (itemId != null) 'itemId': itemId,
          'target': 'inventory',
        },
      );
    }

    if (!_notificationsEnabled || !_lowStockEnabled) return;

    await _showLocalNotification(
      id: 'low_stock_${itemId ?? itemName}'.hashCode,
      title: title,
      body: body,
      payload: 'inventory',
    );
  }

  /// Show order created notification for managers
  Future<void> showOrderCreatedNotification({
    required String orderId,
    required String creatorName,
    required double total,
    required int itemCount,
    bool persist = false,
  }) async {
    final title = 'New Order Created';
    final shortId = orderId.length > 6 ? orderId.substring(0, 6) : orderId;
    final body =
        '$creatorName created Order #$shortId - \u20B1${total.toStringAsFixed(2)} ($itemCount items)';
    if (persist) {
      await persistFeedNotification(
        title: title,
        body: body,
        type: 'order',
        source: 'orders',
        dedupeKey: 'order_created_$orderId',
        data: {
          'orderId': orderId,
          'creatorName': creatorName,
          'total': total,
          'itemCount': itemCount,
          'target': 'orders',
        },
      );
    }

    if (!_notificationsEnabled || !_orderAlertsEnabled) return;

    await _showLocalNotification(
      id: orderId.hashCode,
      title: title,
      body: body,
      payload: 'orders',
    );
  }

  /// Dispose
  void dispose() {
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
  }
}
