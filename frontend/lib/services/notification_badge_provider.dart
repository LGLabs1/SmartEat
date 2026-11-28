import 'package:flutter/foundation.dart';

import 'api_service.dart';

class NotificationBadgeProvider extends ChangeNotifier {
  static const Duration _refreshTtl = Duration(seconds: 30);

  int _unreadCount = 0;
  bool _refreshing = false;
  DateTime? _lastRefreshedAt;

  int get unreadCount => _unreadCount;

  void setCount(int count) {
    final next = count < 0 ? 0 : count;
    if (next == _unreadCount) return;
    _unreadCount = next;
    notifyListeners();
  }

  void decrement([int amount = 1]) {
    setCount(_unreadCount - (amount < 1 ? 1 : amount));
  }

  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    final last = _lastRefreshedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _refreshTtl) {
      return;
    }
    _refreshing = true;
    try {
      final items = await ApiService.fetchNotifications(limit: 400);
      final count = items
          .where((item) => item['isRead'] != true && item['ignored'] != true)
          .length;
      setCount(count);
      _lastRefreshedAt = DateTime.now();
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }
}
