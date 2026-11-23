import 'package:flutter/foundation.dart';

import 'api_service.dart';

class NotificationBadgeProvider extends ChangeNotifier {
  int _unreadCount = 0;
  bool _refreshing = false;

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

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final items = await ApiService.fetchNotifications(limit: 400);
      final count = items
          .where((item) => item['isRead'] != true && item['ignored'] != true)
          .length;
      setCount(count);
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }
}
