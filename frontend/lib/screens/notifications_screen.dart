import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_provider.dart';
import 'staff_management_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const List<String> _filters = <String>[
    'All',
    'Unread',
    'Inventory',
    'Bills',
    'Orders',
    'Push',
  ];

  bool _isLoading = true;
  bool _isWorking = false;
  String? _error;
  bool _isIndexError = false;
  String _filter = 'All';
  String? _uid;
  String _role = '';
  List<NotificationItem> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  bool get _canDelete => _role == 'admin';

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isIndexError = false;
    });

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      final uid = (profile?['uid'] ?? '').toString().trim();
      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();

      if (eateryId.isEmpty) {
        setState(() {
          _error = 'No eatery associated with this account';
          _isLoading = false;
        });
        return;
      }

      _uid = uid;
      _role = role;

      await Future.wait([
        _syncInventoryAlerts(eateryId),
        _syncPayableAlerts(eateryId),
      ]);

      final isAdmin = role == 'admin' || profile?['isAdmin'] == true;
      final notifications = (await _fetchStoredNotifications(eateryId, uid))
          .where((n) => isAdmin || n.type != 'staff_approval')
          .toList();
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final errorStr = e.toString();
      final isIndexError = errorStr.contains('failed-precondition') &&
          errorStr.contains('index');
      setState(() {
        _error = isIndexError
            ? 'Database index required. Please create a composite index for eateryId + createdAt in Firebase Console.'
            : 'Failed to load notifications: $e';
        _isLoading = false;
        _isIndexError = isIndexError;
      });
    }
  }

  String _safeDocId(String raw) {
    final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safe.isEmpty) return 'notif_${DateTime.now().millisecondsSinceEpoch}';
    return safe.length > 180 ? safe.substring(0, 180) : safe;
  }

  Future<void> _upsertNotification({
    required String docId,
    required String eateryId,
    required String title,
    required String body,
    required String type,
    required String source,
    required String dedupeKey,
    Map<String, dynamic>? data,
    DateTime? createdAt,
  }) async {
    final ref =
        FirebaseFirestore.instance.collection('notifications').doc(docId);
    final existing = await ref.get();
    final payload = <String, dynamic>{
      'eateryId': eateryId,
      'title': title,
      'body': body,
      'type': type,
      'source': source,
      'dedupeKey': dedupeKey,
      'data': data ?? <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
      'active': true,
      'resolvedAt': FieldValue.delete(),
    };
    if (!existing.exists) {
      payload['createdAt'] = createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt);
      payload['readBy'] = <String, dynamic>{};
      payload['isRead'] = false;
    }
    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> _resolveDocIfExists(String docId) async {
    final ref =
        FirebaseFirestore.instance.collection('notifications').doc(docId);
    final existing = await ref.get();
    if (!existing.exists) return;
    final data = Map<String, dynamic>.from(existing.data() as Map? ?? const {});
    if (data['active'] == false) return;
    await ref.set({
      'active': false,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncInventoryAlerts(String eateryId) async {
    try {
      final result = await ApiService.getInventoryItems();
      final items = result['data'] as List<dynamic>? ?? [];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] ?? '').toString();
        final name = (item['name'] ?? 'Unknown Item').toString();
        final currentStock = (item['currentStock'] as num?)?.toDouble() ?? 0;
        final minStock = (item['minStock'] as num?)?.toDouble() ?? 0;
        final unit = (item['unit'] ?? '').toString();
        if (id.isEmpty) continue;

        final outId = _safeDocId('out_of_stock_${eateryId}_$id');
        final lowId = _safeDocId('low_stock_${eateryId}_$id');

        if (currentStock <= 0) {
          await _upsertNotification(
            docId: outId,
            eateryId: eateryId,
            title: 'Out of Stock: $name',
            body:
                '$name is currently out of stock. Please restock immediately.',
            type: 'out_of_stock',
            source: 'inventory',
            dedupeKey: 'out_of_stock:$id',
            data: {
              'itemId': id,
              'itemName': name,
              'currentStock': currentStock,
              'minStock': minStock,
              'unit': unit,
              'target': 'inventory',
              'priority': 'high'
            },
          );
          await _resolveDocIfExists(lowId);
        } else if (currentStock <= minStock && minStock > 0) {
          await _upsertNotification(
            docId: lowId,
            eateryId: eateryId,
            title: 'Low Stock: $name',
            body:
                '$name is running low. Current: $currentStock $unit (Min: $minStock $unit)',
            type: 'low_stock',
            source: 'inventory',
            dedupeKey: 'low_stock:$id',
            data: {
              'itemId': id,
              'itemName': name,
              'currentStock': currentStock,
              'minStock': minStock,
              'unit': unit,
              'target': 'inventory',
              'priority': 'medium'
            },
          );
          await _resolveDocIfExists(outId);
        } else {
          await _resolveDocIfExists(outId);
          await _resolveDocIfExists(lowId);
        }
      }
    } catch (_) {}
  }

  Future<void> _syncPayableAlerts(String eateryId) async {
    try {
      final result = await ApiService.getPayables();
      final items = result['data'] as List<dynamic>? ?? [];
      final now = DateTime.now();
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] ?? '').toString();
        final name = (item['name'] ?? 'Unknown Bill').toString();
        final dueDateStr = item['dueDate']?.toString();
        final status = (item['status'] ?? 'unpaid').toString().toLowerCase();
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        if (id.isEmpty) continue;

        final overdueId = _safeDocId('bill_overdue_${eateryId}_$id');
        final dueSoonId = _safeDocId('bill_due_soon_${eateryId}_$id');

        if (status == 'paid' || dueDateStr == null || dueDateStr.isEmpty) {
          await _resolveDocIfExists(overdueId);
          await _resolveDocIfExists(dueSoonId);
          continue;
        }
        final dueDate = DateTime.tryParse(dueDateStr);
        if (dueDate == null) {
          await _resolveDocIfExists(overdueId);
          await _resolveDocIfExists(dueSoonId);
          continue;
        }
        final daysUntil = dueDate.difference(now).inDays;
        final amountText = amount > 0
            ? ' Amount: \u20B1${amount.toStringAsFixed(2)}'
            : ' Variable amount.';
        if (daysUntil < 0) {
          await _upsertNotification(
            docId: overdueId,
            eateryId: eateryId,
            title: 'Overdue Bill: $name',
            body: '$name is overdue by ${daysUntil.abs()} days.$amountText',
            type: 'bill_overdue',
            source: 'payable',
            dedupeKey: 'bill_overdue:$id',
            createdAt: dueDate,
            data: {
              'payableId': id,
              'payableName': name,
              'amount': amount,
              'dueDate': dueDate.toIso8601String(),
              'target': 'payables',
              'priority': 'high'
            },
          );
          await _resolveDocIfExists(dueSoonId);
        } else if (daysUntil <= 3) {
          final dueText = daysUntil == 0
              ? 'today'
              : daysUntil == 1
                  ? 'tomorrow'
                  : 'in $daysUntil days';
          await _upsertNotification(
            docId: dueSoonId,
            eateryId: eateryId,
            title: 'Bill Due Soon: $name',
            body: '$name is due $dueText.$amountText',
            type: 'bill_due_soon',
            source: 'payable',
            dedupeKey: 'bill_due_soon:$id',
            createdAt: dueDate,
            data: {
              'payableId': id,
              'payableName': name,
              'amount': amount,
              'dueDate': dueDate.toIso8601String(),
              'daysUntil': daysUntil,
              'target': 'payables',
              'priority': 'medium'
            },
          );
          await _resolveDocIfExists(overdueId);
        } else {
          await _resolveDocIfExists(overdueId);
          await _resolveDocIfExists(dueSoonId);
        }
      }
    } catch (_) {}
  }

  Future<List<NotificationItem>> _fetchStoredNotifications(
      String eateryId, String uid) async {
    QuerySnapshot snapshot;
    try {
      snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('eateryId', isEqualTo: eateryId)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
    } catch (e) {
      if (e.toString().contains('failed-precondition') ||
          e.toString().contains('index')) {
        snapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('eateryId', isEqualTo: eateryId)
            .limit(250)
            .get();
      } else {
        rethrow;
      }
    }

    final items = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final readByRaw = data['readBy'];
      final readBy = readByRaw is Map
          ? readByRaw.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final legacyRead = data['isRead'] == true;
      final isRead =
          uid.isNotEmpty ? (readBy.containsKey(uid) || legacyRead) : legacyRead;
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ??
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          (data['resolvedAt'] as Timestamp?)?.toDate() ??
          DateTime.now();
      return NotificationItem(
        id: doc.id,
        title: (data['title'] ?? 'Notification').toString(),
        body: (data['body'] ?? '').toString(),
        type: (data['type'] ?? 'general').toString(),
        source:
            (data['source'] ?? data['data']?['source'] ?? 'system').toString(),
        isRead: isRead,
        createdAt: createdAt,
        data: data,
      );
    }).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> _markAsRead(NotificationItem notification) async {
    if (_uid == null || _uid!.isEmpty || notification.isRead) return;
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notification.id)
          .set({
        'readBy': {_uid!: FieldValue.serverTimestamp()},
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => n.id == notification.id ? n.copyWith(isRead: true) : n)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    if (_uid == null || _uid!.isEmpty) return;
    final unread = _notifications.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    setState(() => _isWorking = true);
    try {
      final chunks = <List<NotificationItem>>[];
      for (var i = 0; i < unread.length; i += 400) {
        chunks.add(unread.sublist(i, (i + 400).clamp(0, unread.length)));
      }
      for (final chunk in chunks) {
        final batch = FirebaseFirestore.instance.batch();
        for (final n in chunk) {
          final ref =
              FirebaseFirestore.instance.collection('notifications').doc(n.id);
          batch.set(
              ref,
              {
                'readBy': {_uid!: FieldValue.serverTimestamp()},
                'isRead': true,
                'readAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }
        await batch.commit();
      }
      if (!mounted) return;
      setState(() {
        _notifications =
            _notifications.map((n) => n.copyWith(isRead: true)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to mark all as read: $e')));
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteNotification(NotificationItem notification) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notification.id)
          .delete();
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((n) => n.id == notification.id);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      await _loadNotifications();
    }
  }

  List<NotificationItem> get _filteredNotifications {
    final items = _notifications.where((n) {
      switch (_filter) {
        case 'Unread':
          return !n.isRead;
        case 'Inventory':
          return n.type == 'low_stock' ||
              n.type == 'out_of_stock' ||
              n.source == 'inventory';
        case 'Bills':
          return n.type == 'bill_due_soon' ||
              n.type == 'bill_overdue' ||
              n.source == 'payable' ||
              n.type == 'bill' ||
              n.type == 'payable';
        case 'Orders':
          return n.type == 'order' || n.source == 'orders';
        case 'Push':
          return n.source == 'push' || n.type == 'push';
        case 'All':
        default:
          return true;
      }
    }).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  IconData _getIconForType(String type, String source) {
    switch (type.toLowerCase()) {
      case 'out_of_stock':
        return Icons.error_outline;
      case 'low_stock':
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'bill_overdue':
        return Icons.warning_amber_outlined;
      case 'bill_due_soon':
      case 'bill':
      case 'payable':
        return Icons.receipt_long_outlined;
      case 'order':
        return Icons.receipt_outlined;
      case 'staff':
        return Icons.person_outline;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'push':
        return Icons.notifications_active_outlined;
      default:
        if (source == 'push') return Icons.notifications_active_outlined;
        return Icons.notifications_outlined;
    }
  }

  Color _getColorForType(String type, String source) {
    switch (type.toLowerCase()) {
      case 'out_of_stock':
      case 'bill_overdue':
        return Colors.red;
      case 'low_stock':
      case 'inventory':
      case 'bill_due_soon':
        return Colors.orange;
      case 'bill':
      case 'payable':
        return Colors.blue;
      case 'order':
        return Colors.green;
      case 'staff':
        return Colors.purple;
      case 'finance':
        return Colors.teal;
      case 'push':
        return Colors.indigo;
      default:
        if (source == 'push') return Colors.indigo;
        return Colors.grey;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop())
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            Text(
              _unreadCount > 0
                  ? '$_unreadCount unread'
                  : 'System and push alerts',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _isWorking ? null : _markAllAsRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white)),
            ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadNotifications,
              tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          if (_isWorking) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : filtered.isEmpty
                        ? _buildEmptyState(filteredBy: _filter)
                        : _buildNotificationList(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            final selected = _filter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter),
                selected: selected,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNotificationList(List<NotificationItem> items) {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _buildNotificationTile(items[index]),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem notification) {
    final icon = _getIconForType(notification.type, notification.source);
    final color = _getColorForType(notification.type, notification.source);
    final tile = ListTile(
      tileColor:
          notification.isRead ? Colors.white : color.withValues(alpha: 0.04),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
            fontWeight:
                notification.isRead ? FontWeight.w500 : FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            notification.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: notification.isRead
                    ? Colors.grey.shade700
                    : Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(_formatTime(notification.createdAt),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
      trailing: notification.isRead
          ? null
          : Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: Colors.blue, borderRadius: BorderRadius.circular(5))),
      onTap: () async {
        await _markAsRead(notification);
        if (mounted)
          _showNotificationDetail(notification.copyWith(isRead: true));
      },
    );

    if (!_canDelete) return tile;
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => _deleteNotification(notification),
      child: tile,
    );
  }

  void _showNotificationDetail(NotificationItem notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIconForType(notification.type, notification.source),
                color:
                    _getColorForType(notification.type, notification.source)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(notification.title,
                    style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 16),
            Text(
                'Received: ${DateFormat('MMM d, yyyy h:mm a').format(notification.createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Text('Source: ${notification.source}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          if (notification.type == 'staff_approval' && _role == 'admin')
            FilledButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => const StaffManagementScreen(),
                  ),
                );
              },
              child: const Text('Open Staff'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final isIndexError = _isIndexError || (_error?.contains('index') ?? false);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isIndexError ? Icons.build_outlined : Icons.error_outline,
                size: 64,
                color: isIndexError
                    ? Colors.orange.shade400
                    : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
                isIndexError
                    ? 'Database Setup Required'
                    : 'Error Loading Notifications',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadNotifications, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required String filteredBy}) {
    final isFiltered = filteredBy != 'All';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
                isFiltered
                    ? 'No $filteredBy notifications'
                    : 'No notifications yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try another filter or pull to refresh.'
                  : 'System alerts and push notifications will appear here when important events occur.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final String source;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.source,
    required this.isRead,
    required this.createdAt,
    required this.data,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    String? source,
    bool? isRead,
    DateTime? createdAt,
    Map<String, dynamic>? data,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      source: source ?? this.source,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
    );
  }
}
