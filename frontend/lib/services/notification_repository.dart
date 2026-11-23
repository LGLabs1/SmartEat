import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';
import 'api_service.dart';

class NotificationRepository {
  static const _cachePrefix = 'smarteat_notifications_cache_v4_';

  Future<List<NotificationItem>> fetch() async {
    final items = await ApiService.fetchNotifications();
    return items.map(_fromApi).toList();
  }

  Future<List<NotificationItem>> readCache(String uid) async {
    if (uid.isEmpty) return const <NotificationItem>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString('$_cachePrefix$uid');
      if (encoded == null || encoded.isEmpty) return const <NotificationItem>[];
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <NotificationItem>[];
      return decoded
          .whereType<Map>()
          .map((item) => _fromCache(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const <NotificationItem>[];
    }
  }

  Future<void> writeCache(String uid, List<NotificationItem> items) async {
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        items.take(400).map(_toCache).toList(growable: false),
      );
      await prefs.setString('$_cachePrefix$uid', encoded);
    } catch (_) {}
  }

  NotificationItem _fromApi(Map<String, dynamic> item) {
    final readBy = item['readBy'];
    final readByMap = readBy is Map
        ? readBy.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final legacyRead = item['isRead'] == true && readByMap.isEmpty;
    final payload = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'] as Map)
        : <String, dynamic>{};
    return NotificationItem(
      id: (item['id'] ?? '').toString(),
      title: (item['title'] ?? 'Notification').toString(),
      body: (item['body'] ?? '').toString(),
      type: (item['type'] ?? 'general').toString(),
      source: (item['source'] ?? 'system').toString(),
      isRead: readByMap.isNotEmpty || legacyRead,
      createdAt: _parseDate(item['createdAt']) ?? DateTime.now(),
      route: (item['route'] ?? payload['route'] ?? payload['target'] ?? '')
          .toString(),
      ignoreKey:
          (item['ignoreKey'] ?? payload['ignoreKey'] ?? item['dedupeKey'] ?? '')
              .toString(),
      pinned: item['pinned'] == true,
      ignored: item['ignored'] == true,
      details: _detailsFrom(payload),
      data: payload,
    );
  }

  NotificationItem _fromCache(Map<String, dynamic> item) {
    final payload = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'] as Map)
        : <String, dynamic>{};
    final itemRoute = (item['route'] ?? '').toString();
    return NotificationItem(
      id: (item['id'] ?? '').toString(),
      title: (item['title'] ?? 'Notification').toString(),
      body: (item['body'] ?? '').toString(),
      type: (item['type'] ?? 'general').toString(),
      source: (item['source'] ?? 'system').toString(),
      isRead: item['isRead'] == true,
      createdAt: _parseDate(item['createdAt']) ?? DateTime.now(),
      route: itemRoute.isNotEmpty
          ? itemRoute
          : (payload['route'] ?? payload['target'] ?? '').toString(),
      ignoreKey: (item['ignoreKey'] ?? payload['ignoreKey'] ?? '').toString(),
      pinned: item['pinned'] == true,
      ignored: item['ignored'] == true,
      details: _detailsFrom(payload),
      data: payload,
    );
  }

  Map<String, dynamic> _toCache(NotificationItem item) => <String, dynamic>{
        'id': item.id,
        'title': item.title,
        'body': item.body,
        'type': item.type,
        'source': item.source,
        'isRead': item.isRead,
        'createdAt': item.createdAt.toIso8601String(),
        'route': item.route,
        'ignoreKey': item.ignoreKey,
        'pinned': item.pinned,
        'ignored': item.ignored,
        'data': item.data,
      };

  List<String> _detailsFrom(Map<String, dynamic> payload) {
    final direct = payload['details'];
    if (direct is List) {
      return direct
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final names = payload['itemNames'];
    if (names is List) {
      return names
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final items = payload['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((item) => (item['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
