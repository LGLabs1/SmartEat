import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';
import 'api_service.dart';

class NotificationRepository {
  static const _cachePrefix = 'smarteat_notifications_cache_v3_';

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
    return NotificationItem(
      id: (item['id'] ?? '').toString(),
      title: (item['title'] ?? 'Notification').toString(),
      body: (item['body'] ?? '').toString(),
      type: (item['type'] ?? 'general').toString(),
      source: (item['source'] ?? 'system').toString(),
      isRead: readByMap.isNotEmpty || legacyRead,
      createdAt: _parseDate(item['createdAt']) ?? DateTime.now(),
      data: item['data'] is Map
          ? Map<String, dynamic>.from(item['data'] as Map)
          : Map<String, dynamic>.from(item),
    );
  }

  NotificationItem _fromCache(Map<String, dynamic> item) {
    return NotificationItem(
      id: (item['id'] ?? '').toString(),
      title: (item['title'] ?? 'Notification').toString(),
      body: (item['body'] ?? '').toString(),
      type: (item['type'] ?? 'general').toString(),
      source: (item['source'] ?? 'system').toString(),
      isRead: item['isRead'] == true,
      createdAt: _parseDate(item['createdAt']) ?? DateTime.now(),
      data: item['data'] is Map
          ? Map<String, dynamic>.from(item['data'] as Map)
          : <String, dynamic>{},
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
        'data': item.data,
      };

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
