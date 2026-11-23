import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/notification_visibility.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    final service = NotificationService();
    await service.persistPushNotification(message, background: true);
  } catch (_) {}
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const _pendingNotificationsKey = 'smarteat_pending_notifications_v2';
  static const _cachedEateryIdKey = 'smarteat_cached_eatery_id';
  static const _cachedNotificationUidKey = 'smarteat_cached_notification_uid';
  static const _pendingTtl = Duration(days: 7);

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? _preferencesUid;
  bool _initialized = false;
  bool _initializing = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;
  StreamSubscription<User?>? _authSubscription;
  bool _flushingPending = false;

  // Settings
  bool _notificationsEnabled = true;
  bool _lowStockEnabled = true;
  bool _billRemindersEnabled = true;
  bool _orderAlertsEnabled = true;
  bool _attendanceRemindersEnabled = true;
  int _billReminderDays = 3; // Days before due date to remind

  // Getters
  String? get fcmToken => _fcmToken;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get lowStockEnabled => _lowStockEnabled;
  bool get billRemindersEnabled => _billRemindersEnabled;
  bool get orderAlertsEnabled => _orderAlertsEnabled;
  bool get attendanceRemindersEnabled => _attendanceRemindersEnabled;
  int get billReminderDays => _billReminderDays;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    // Firebase Messaging and the local notifications plugin do not support
    // Windows/Linux desktop, so skip initialization there.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      await loadPreferences(force: true);
      _authSubscription ??=
          FirebaseAuth.instance.authStateChanges().listen((user) {
        unawaited(_handleAuthChanged(user));
      });
      _initialized = true;
      _initializing = false;
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
      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
      });

      // Set up local notifications for foreground messages
      await _setupLocalNotifications();

      // Set up foreground message handler
      _onMessageSubscription ??=
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Set up notification tap handler
      _onMessageOpenedAppSubscription ??=
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      await loadPreferences(force: true);
      await _flushPendingNotifications();
      _authSubscription ??=
          FirebaseAuth.instance.authStateChanges().listen((user) {
        unawaited(_handleAuthChanged(user));
      });
      _initialized = true;
    } catch (e) {
      // Don't rethrow - notifications are not critical to app function
    } finally {
      _initializing = false;
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
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? 'Smart Eat')
        .toString();
    final body = (notification?.body ?? message.data['body'] ?? '').toString();
    final messageId = message.messageId;

    await persistPushNotification(message);

    if (!_notificationsEnabled) return;
    if (title.isEmpty && body.isEmpty) return;

    await _showLocalNotification(
      id: messageId?.hashCode ?? DateTime.now().millisecond,
      title: title,
      body: body,
      payload: message.data.toString(),
    );
  }

  /// Handle notification tap when app is in background
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    await persistPushNotification(message, opened: true);
  }

  /// Handle local notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Navigation can be handled here based on payload
  }

  Future<void> persistPushNotification(
    RemoteMessage message, {
    bool opened = false,
    bool background = false,
  }) async {
    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? 'Smart Eat')
        .toString();
    final body = (notification?.body ?? message.data['body'] ?? '').toString();
    final type = (message.data['type'] ?? 'push').toString();
    final messageId = message.messageId;
    final targets = notificationStringList(message.data['targetUids']);
    final payload = Map<String, dynamic>.from(message.data);
    payload['type'] = type;
    final roles = notificationRolesFromPayload(payload);
    final eateryId = (message.data['eateryId'] ?? '').toString().trim();
    final dedupeKey = messageId != null && messageId.isNotEmpty
        ? 'push_$messageId'
        : 'push_${opened ? 'opened_' : ''}${DateTime.now().millisecondsSinceEpoch}';

    await persistFeedNotification(
      title: title,
      body: body,
      type: type,
      source: (message.data['source'] ?? 'push').toString(),
      audience: (message.data['audience'] ?? notificationDefaultAudience(type))
          .toString(),
      allowedRoles: roles,
      targetUids: targets,
      eateryId: eateryId.isEmpty ? null : eateryId,
      dedupeKey: dedupeKey,
      data: {
        ...message.data,
        'type': type,
        'allowedRoles': roles,
        if (messageId != null) 'messageId': messageId,
        'target': message.data['target'] ?? message.data['route'],
        if (opened) 'openedFromNotification': true,
        if (background) 'background': true,
      },
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final single = (value ?? '').toString().trim();
    return single.isEmpty ? const <String>[] : <String>[single];
  }

  Future<void> _handleAuthChanged(User? user) async {
    final previousUid = _preferencesUid;
    if (previousUid != user?.uid) {
      await _clearPendingNotificationsForUserChange(
        previousUid: previousUid,
        nextUid: user?.uid,
      );
      if (user == null) {
        _preferencesUid = null;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_cachedEateryIdKey);
          await prefs.remove(_cachedNotificationUidKey);
        } catch (_) {}
      } else {
        await loadPreferences(force: true);
      }
    }
    if (user != null) {
      await _flushPendingNotifications();
      unawaited(ApiService.syncSystemNotifications().catchError((_) => 0));
    }
  }

  Future<String?> _resolveEateryId({bool waitForAuth = true}) async {
    User? user = FirebaseAuth.instance.currentUser;
    final attempts = waitForAuth && user == null ? 10 : 1;
    for (var index = 0; index < attempts && user == null; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      user = FirebaseAuth.instance.currentUser;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedUid = (prefs.getString(_cachedNotificationUidKey) ?? '').trim();
    final cachedEateryId = (prefs.getString(_cachedEateryIdKey) ?? '').trim();

    if (user == null) {
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final eateryId = (doc.data()?['eateryId'] ?? '').toString().trim();
      if (eateryId.isNotEmpty) {
        await prefs.setString(_cachedEateryIdKey, eateryId);
        await prefs.setString(_cachedNotificationUidKey, user.uid);
        return eateryId;
      }
    } catch (_) {}

    if (cachedUid == user.uid && cachedEateryId.isNotEmpty) {
      return cachedEateryId;
    }
    return null;
  }

  Future<void> _queuePendingNotification({
    required String title,
    required String body,
    required String type,
    required String source,
    required String audience,
    required List<String> allowedRoles,
    required List<String> targetUids,
    required String? dedupeKey,
    required String? eateryId,
    required DateTime? createdAt,
    required Map<String, dynamic>? data,
    required bool preserveReadState,
  }) async {
    try {
      final ownerUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (ownerUid.isEmpty && (eateryId ?? '').trim().isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final queued = <String, dynamic>{
        'ownerUid': ownerUid,
        'title': title,
        'body': body,
        'type': type,
        'source': source,
        'audience': audience,
        'allowedRoles': allowedRoles,
        'targetUids': targetUids,
        'dedupeKey': dedupeKey,
        'eateryId': eateryId,
        'createdAt': createdAt?.toIso8601String(),
        'data': data ?? <String, dynamic>{},
        'preserveReadState': preserveReadState,
        'queuedAt': DateTime.now().toIso8601String(),
      };
      final encoded = jsonEncode(
        queued,
        toEncodable: (value) => value.toString(),
      );
      final pending =
          (prefs.getStringList(_pendingNotificationsKey) ?? <String>[])
              .toList();
      pending.add(encoded);
      while (pending.length > 100) {
        pending.removeAt(0);
      }
      await prefs.setStringList(_pendingNotificationsKey, pending);
    } catch (_) {}
  }

  Future<void> _clearPendingNotificationsForUserChange({
    required String? previousUid,
    required String? nextUid,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending =
          prefs.getStringList(_pendingNotificationsKey) ?? <String>[];
      if (pending.isEmpty) return;
      if (nextUid == null || nextUid.isEmpty || previousUid != nextUid) {
        final kept = pending.where((encoded) {
          try {
            final decoded = jsonDecode(encoded) as Map<String, dynamic>;
            final ownerUid = (decoded['ownerUid'] ?? '').toString().trim();
            return nextUid != null &&
                nextUid.isNotEmpty &&
                ownerUid.isNotEmpty &&
                ownerUid == nextUid;
          } catch (_) {
            return false;
          }
        }).toList();
        if (kept.isEmpty) {
          await prefs.remove(_pendingNotificationsKey);
        } else {
          await prefs.setStringList(_pendingNotificationsKey, kept);
        }
      }
    } catch (_) {}
  }

  Future<void> removePendingByDedupeKey(String dedupeKey) async {
    final key = dedupeKey.trim();
    if (key.isEmpty) return;
    await removeQueuedItem(
        (decoded) => (decoded['dedupeKey'] ?? '').toString().trim() == key);
  }

  Future<void> removeQueuedItem(
    bool Function(Map<String, dynamic> item) predicate,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending =
          prefs.getStringList(_pendingNotificationsKey) ?? <String>[];
      if (pending.isEmpty) return;
      final kept = <String>[];
      for (final encoded in pending) {
        try {
          final decoded = jsonDecode(encoded) as Map<String, dynamic>;
          if (predicate(decoded)) continue;
        } catch (_) {}
        kept.add(encoded);
      }
      if (kept.length == pending.length) return;
      if (kept.isEmpty) {
        await prefs.remove(_pendingNotificationsKey);
      } else {
        await prefs.setStringList(_pendingNotificationsKey, kept);
      }
    } catch (_) {}
  }

  bool _isQueuedItemExpired(Map<String, dynamic> decoded, DateTime now) {
    final queuedAtRaw = (decoded['queuedAt'] ?? '').toString().trim();
    final queuedAt = DateTime.tryParse(queuedAtRaw);
    if (queuedAt == null) return true;
    return now.difference(queuedAt) > _pendingTtl;
  }

  Future<void> _flushPendingNotifications() async {
    if (_flushingPending) return;
    _flushingPending = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final pending =
          prefs.getStringList(_pendingNotificationsKey) ?? <String>[];
      if (pending.isEmpty) return;

      final resolvedEateryId =
          (await _resolveEateryId(waitForAuth: false) ?? '').toString().trim();
      final now = DateTime.now();
      final saved = <String>{};
      final dropped = <String>{};
      for (final encoded in pending) {
        try {
          final decoded = jsonDecode(encoded) as Map<String, dynamic>;
          final ownerUid = (decoded['ownerUid'] ?? '').toString().trim();
          final payloadEateryId = (decoded['eateryId'] ?? '').toString().trim();
          final targetUids = _stringList(decoded['targetUids']);
          if (_isQueuedItemExpired(decoded, now) ||
              (ownerUid.isNotEmpty && ownerUid != user.uid) ||
              (ownerUid.isEmpty &&
                  (payloadEateryId.isEmpty ||
                      payloadEateryId != resolvedEateryId)) ||
              (targetUids.isNotEmpty && !targetUids.contains(user.uid))) {
            dropped.add(encoded);
            continue;
          }
          if (payloadEateryId.isNotEmpty &&
              resolvedEateryId.isNotEmpty &&
              payloadEateryId != resolvedEateryId) {
            dropped.add(encoded);
            continue;
          }
          final targetEateryId =
              payloadEateryId.isNotEmpty ? payloadEateryId : resolvedEateryId;
          if (targetEateryId.isEmpty) {
            continue;
          }

          final rawData = decoded['data'];
          final savedNotification = await _writeFeedNotification(
            title: (decoded['title'] ?? '').toString(),
            body: (decoded['body'] ?? '').toString(),
            type: (decoded['type'] ?? 'general').toString(),
            source: (decoded['source'] ?? 'system').toString(),
            audience: (decoded['audience'] ?? 'all').toString(),
            allowedRoles: notificationStringList(decoded['allowedRoles']),
            targetUids: targetUids,
            dedupeKey: (decoded['dedupeKey'] ?? '').toString(),
            eateryId: targetEateryId,
            resolvedEateryId: targetEateryId,
            createdAt: DateTime.tryParse(
              (decoded['createdAt'] ?? '').toString(),
            ),
            data: rawData is Map
                ? Map<String, dynamic>.from(rawData)
                : <String, dynamic>{},
            preserveReadState: decoded['preserveReadState'] == true,
          );
          if (savedNotification) {
            saved.add(encoded);
          }
        } catch (_) {
          dropped.add(encoded);
        }
      }

      if (saved.isEmpty && dropped.isEmpty) return;
      final latest = prefs.getStringList(_pendingNotificationsKey) ?? pending;
      final remaining = latest
          .where((item) => !saved.contains(item) && !dropped.contains(item))
          .toList();
      if (remaining.isEmpty) {
        await prefs.remove(_pendingNotificationsKey);
      } else {
        await prefs.setStringList(_pendingNotificationsKey, remaining);
      }
    } catch (_) {
    } finally {
      _flushingPending = false;
    }
  }

  Future<bool> persistFeedNotification({
    required String title,
    required String body,
    required String type,
    String source = 'system',
    String audience = 'all',
    List<String> allowedRoles = const <String>[],
    List<String> targetUids = const <String>[],
    String? dedupeKey,
    String? eateryId,
    DateTime? createdAt,
    Map<String, dynamic>? data,
    bool preserveReadState = false,
  }) async {
    final effectiveRoles = allowedRoles.isEmpty
        ? notificationRolesFor(
            audience: audience,
            type: type,
            targetUids: targetUids,
          )
        : allowedRoles;
    final saved = await _writeFeedNotification(
      title: title,
      body: body,
      type: type,
      source: source,
      audience: audience,
      allowedRoles: effectiveRoles,
      targetUids: targetUids,
      dedupeKey: dedupeKey,
      eateryId: eateryId,
      createdAt: createdAt,
      data: data,
      preserveReadState: preserveReadState,
    );
    if (saved) return true;
    await _queuePendingNotification(
      title: title,
      body: body,
      type: type,
      source: source,
      audience: audience,
      allowedRoles: effectiveRoles,
      targetUids: targetUids,
      dedupeKey: dedupeKey,
      eateryId: eateryId,
      createdAt: createdAt,
      data: data,
      preserveReadState: preserveReadState,
    );
    return false;
  }

  Future<bool> _writeFeedNotification({
    required String title,
    required String body,
    required String type,
    required String source,
    required String audience,
    required List<String> allowedRoles,
    required List<String> targetUids,
    required String? dedupeKey,
    required String? eateryId,
    String? resolvedEateryId,
    DateTime? createdAt,
    required Map<String, dynamic>? data,
    required bool preserveReadState,
  }) async {
    try {
      final providedEateryId = (eateryId ?? '').trim();
      final preResolvedEateryId = (resolvedEateryId ?? '').trim();
      final effectiveEateryId = preResolvedEateryId.isNotEmpty
          ? preResolvedEateryId
          : (providedEateryId.isNotEmpty
              ? providedEateryId
              : await _resolveEateryId());
      if (effectiveEateryId == null || effectiveEateryId.isEmpty) return false;
      final effectiveDedupeKey = (dedupeKey != null && dedupeKey.isNotEmpty)
          ? dedupeKey
          : '${source}_${type}_${DateTime.now().millisecondsSinceEpoch}';
      final effectiveAudience = audience.trim().isEmpty
          ? notificationDefaultAudience(type)
          : audience.trim();
      return await ApiService.recordSystemNotification({
        'eateryId': effectiveEateryId,
        'title': title,
        'body': body,
        'type': type,
        'source': source,
        'audience': effectiveAudience,
        'allowedRoles': allowedRoles,
        'targetUids': targetUids,
        'dedupeKey': effectiveDedupeKey,
        'createdAt': createdAt?.toIso8601String(),
        'data': data ?? <String, dynamic>{},
        'preserveReadState': preserveReadState,
      });
    } catch (_) {
      return false;
    }
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
    String audience = 'all',
    List<String> allowedRoles = const <String>[],
    List<String> targetUids = const <String>[],
    String? dedupeKey,
    bool preserveReadState = false,
    Map<String, dynamic>? data,
    bool persist = true,
  }) async {
    if (persist) {
      await persistFeedNotification(
        title: title,
        body: body,
        type: type,
        source: source,
        audience: audience,
        allowedRoles: allowedRoles,
        targetUids: targetUids,
        dedupeKey: dedupeKey,
        preserveReadState: preserveReadState,
        data: data ?? (payload == null ? null : {'payload': payload}),
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

  Future<void> loadPreferences({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!force && _preferencesUid == user.uid) return;
    await _loadPreferences();
    _preferencesUid = user.uid;
  }

  Future<void> _loadPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _notificationsEnabled = true;
    _lowStockEnabled = true;
    _billRemindersEnabled = true;
    _orderAlertsEnabled = true;
    _attendanceRemindersEnabled = true;
    _billReminderDays = 3;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      _notificationsEnabled = data['notificationsEnabled'] ?? true;
      _lowStockEnabled = data['lowStockEnabled'] ?? true;
      _billRemindersEnabled = data['billRemindersEnabled'] ?? true;
      _orderAlertsEnabled = data['orderAlertsEnabled'] ?? true;
      _attendanceRemindersEnabled = data['attendanceRemindersEnabled'] ?? true;
      _billReminderDays = data['billReminderDays'] ?? 3;
    } catch (_) {}
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
        'attendanceRemindersEnabled': _attendanceRemindersEnabled,
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

  Future<void> setAttendanceRemindersEnabled(bool enabled) async {
    _attendanceRemindersEnabled = enabled;
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
      showNotification(
        title: title,
        body: body,
        payload: payload,
        type: 'reminder',
        source: 'system',
        dedupeKey: 'scheduled_${id}_${scheduledDate.millisecondsSinceEpoch}',
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
    bool persist = true,
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
        audience: 'admin',
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
    bool persist = true,
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
        audience: 'admin',
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
  }

  /// Dispose
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription?.cancel();
    _onMessageOpenedAppSubscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
  }
}
