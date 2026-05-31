import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
    if (!_notificationsEnabled) return;

    final notification = message.notification;
    if (notification == null) return;

    _showLocalNotification(
      id: message.messageId?.hashCode ?? DateTime.now().millisecond,
      title: notification.title ?? 'Smart Eat',
      body: notification.body ?? '',
      payload: message.data.toString(),
    );
  }

  /// Handle notification tap when app is in background
  void _handleMessageOpenedApp(RemoteMessage message) {
    // Navigation can be handled here based on message data
  }

  /// Handle local notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Navigation can be handled here based on payload
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
  }) async {
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
    } catch (e) {}
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
  }) async {
    if (!_notificationsEnabled || !_lowStockEnabled) return;

    await _showLocalNotification(
      id: 'low_stock_$itemName'.hashCode,
      title: 'Low Stock Alert',
      body: '$itemName is running low (Current: $currentStock, Min: $minStock)',
      payload: 'inventory',
    );
  }

  /// Show order created notification for managers
  Future<void> showOrderCreatedNotification({
    required String orderId,
    required String creatorName,
    required double total,
    required int itemCount,
  }) async {
    if (!_notificationsEnabled || !_orderAlertsEnabled) return;

    await _showLocalNotification(
      id: orderId.hashCode,
      title: 'New Order Created',
      body:
          '$creatorName created Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)} - ₱${total.toStringAsFixed(2)} ($itemCount items)',
      payload: 'orders',
    );
  }

  /// Dispose
  void dispose() {
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
  }
}
