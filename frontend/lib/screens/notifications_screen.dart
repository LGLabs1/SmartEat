import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../theme.dart';
import '../utils/notification_visibility.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/smart_eat_header.dart';
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
    'Attendance',
    'Push',
  ];

  bool _isProfileLoading = true;
  bool _isWorking = false;
  String? _error;
  String _filter = 'All';
  String _eateryId = '';
  String _uid = '';
  bool _isAdmin = false;
  Stream<List<NotificationItem>>? _notificationStream;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  bool get _canDelete => _isAdmin;

  Future<void> _loadIdentity() async {
    setState(() {
      _isProfileLoading = true;
      _error = null;
    });
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();
      final uid = (profile?['uid'] ??
              profile?['id'] ??
              FirebaseAuth.instance.currentUser?.uid ??
              '')
          .toString()
          .trim();
      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      if (eateryId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'No eatery associated with this account';
          _isProfileLoading = false;
        });
        return;
      }

      final isAdmin = role == 'admin' ||
          profile?['isAdmin'] == true ||
          profile?['isAdmin'] == 'true' ||
          profile?['isAdmin'] == 1;
      if (!mounted) return;
      setState(() {
        _eateryId = eateryId;
        _uid = uid;
        _isAdmin = isAdmin;
        _isProfileLoading = false;
      });
      _resetStream();
      if (isAdmin) _runAdminSync(eateryId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load notifications: $e';
        _isProfileLoading = false;
      });
    }
  }

  void _runAdminSync(String eateryId) {
    Future.wait([
      _syncInventoryAlerts(eateryId),
      _syncPayableAlerts(eateryId),
    ]).then((_) {}, onError: (_) {});
  }

  void _resetStream() {
    if (_eateryId.isEmpty) return;
    _notificationStream = _watchStoredNotifications();
  }

  bool _isIndexError(dynamic error) {
    final text = error.toString();
    return text.contains('failed-precondition') || text.contains('index');
  }

  Query<Map<String, dynamic>> _notificationQuery({required bool ordered}) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('notifications')
        .where('eateryId', isEqualTo: _eateryId);
    if (ordered) {
      query = query.orderBy('createdAt', descending: true).limit(200);
    } else {
      query = query.limit(250);
    }
    return query;
  }

  Stream<List<NotificationItem>> _watchStoredNotifications() async* {
    try {
      await for (final snapshot
          in _notificationQuery(ordered: true).snapshots()) {
        yield _mapSnapshot(snapshot);
      }
    } catch (e) {
      if (!_isIndexError(e)) rethrow;
      await for (final snapshot
          in _notificationQuery(ordered: false).snapshots()) {
        yield _mapSnapshot(snapshot);
      }
    }
  }

  List<NotificationItem> _mapSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final items = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      final readByRaw = data['readBy'];
      final readBy = readByRaw is Map
          ? readByRaw.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final legacyRead = data['isRead'] == true;
      final isRead = _uid.isNotEmpty
          ? (readBy.containsKey(_uid) || (readBy.isEmpty && legacyRead))
          : legacyRead;
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
    String audience = 'admin',
    List<String> targetUids = const <String>[],
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
      'audience': audience,
      'targetUids': targetUids,
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
    } else if (existing.data()?['readBy'] is! Map) {
      payload['readBy'] = <String, dynamic>{};
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

  Future<void> _refresh() async {
    if (_eateryId.isEmpty) return;
    if (_isAdmin) _runAdminSync(_eateryId);
    if (!mounted) return;
    setState(() {
      _error = null;
      _resetStream();
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _markAsRead(NotificationItem notification) async {
    if (_uid.isEmpty || notification.isRead) return;
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notification.id)
          .set({
        'readBy': {_uid: FieldValue.serverTimestamp()},
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _markAllAsRead(List<NotificationItem> unread) async {
    if (_uid.isEmpty || unread.isEmpty) return;
    setState(() => _isWorking = true);
    try {
      for (var i = 0; i < unread.length; i += 400) {
        final chunk = unread.sublist(i, (i + 400).clamp(0, unread.length));
        final batch = FirebaseFirestore.instance.batch();
        for (final n in chunk) {
          batch.set(
            FirebaseFirestore.instance.collection('notifications').doc(n.id),
            {
              'readBy': {_uid: FieldValue.serverTimestamp()},
              'readAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark all as read: $e')),
      );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  List<NotificationItem> _applyFilter(List<NotificationItem> items) {
    final filtered = items.where((n) {
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
        case 'Attendance':
          return n.type == 'attendance' || n.source == 'attendance';
        case 'Push':
          return n.source == 'push' || n.type == 'push';
        case 'All':
        default:
          return true;
      }
    }).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

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
      case 'attendance':
        return Icons.access_time;
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
        return AppTheme.error;
      case 'low_stock':
      case 'inventory':
      case 'bill_due_soon':
        return AppTheme.warning;
      case 'bill':
      case 'payable':
        return AppTheme.sageBlue;
      case 'order':
        return AppTheme.sageSuccess;
      case 'attendance':
        return AppTheme.sageCyan;
      case 'staff':
        return AppTheme.sageAccent;
      case 'finance':
        return AppTheme.sageCyan;
      case 'push':
        return AppTheme.sageBlue;
      default:
        if (source == 'push') return AppTheme.sageBlue;
        return AppTheme.sageAccent;
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
    return Theme(
      data: AppTheme.dashboardTheme,
      child: StreamBuilder<List<NotificationItem>>(
        stream: _notificationStream,
        builder: (context, snapshot) {
          final visible = (snapshot.data ?? <NotificationItem>[])
              .where((n) => notificationVisibleToUser(
                    data: n.data,
                    uid: _uid,
                    isAdmin: _isAdmin,
                  ))
              .toList();
          final unread = visible.where((n) => !n.isRead).toList();
          final filtered = _applyFilter(visible);
          return Scaffold(
            backgroundColor: AppTheme.sageNavy,
            appBar: _buildAppBar(unread),
            body: Column(
              children: [
                _buildFilterBar(unread.length),
                if (_isWorking)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.sageAccent,
                  ),
                Expanded(
                  child: _isProfileLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _buildErrorState(_error)
                          : (snapshot.hasError && !snapshot.hasData)
                              ? _buildErrorState(snapshot.error)
                              : !snapshot.hasData
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : filtered.isEmpty
                                      ? _buildEmptyState(
                                          filteredBy: _filter,
                                          hasAny: visible.isNotEmpty,
                                        )
                                      : _buildNotificationList(filtered),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<NotificationItem> unread) {
    final unreadCount = unread.length;
    return SmartEatHeader(
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
            unreadCount > 0 ? '$unreadCount unread' : 'System and push alerts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      actions: [
        const SageHeaderButton(),
        if (unreadCount > 0)
          TextButton(
            onPressed: _isWorking ? null : () => _markAllAsRead(unread),
            child: const Text('Mark all read'),
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isProfileLoading ? null : _refresh,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildFilterBar(int unreadCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: AppTheme.sageNavy,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            final selected = _filter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: filter == 'Unread' && unreadCount > 0
                    ? Badge(
                        label: Text('$unreadCount'),
                        child: const Text('Unread'),
                      )
                    : Text(filter),
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
      color: AppTheme.sageAccent,
      backgroundColor: AppTheme.sagePanel,
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.pagePadding,
          8,
          AppTheme.pagePadding,
          24,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildNotificationTile(items[index]),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem notification) {
    final scheme = Theme.of(context).colorScheme;
    final icon = _getIconForType(notification.type, notification.source);
    final color = _getColorForType(notification.type, notification.source);
    final tile = Material(
      color:
          notification.isRead ? scheme.surface : color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: BorderSide(
            color: notification.isRead
                ? scheme.outline.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.35),
          ),
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _formatTime(notification.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppTheme.sageAccent,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
        onTap: () async {
          await _markAsRead(notification);
          if (mounted)
            _showNotificationDetail(notification.copyWith(isRead: true));
        },
      ),
    );

    if (!_canDelete) return tile;
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppTheme.error.withValues(alpha: 0.85),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(Icons.delete, color: scheme.onError),
      ),
      onDismissed: (_) => _deleteNotification(notification),
      child: tile,
    );
  }

  void _showNotificationDetail(NotificationItem notification) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIconForType(notification.type, notification.source),
                color:
                    _getColorForType(notification.type, notification.source)),
            const SizedBox(width: 12),
            Expanded(child: Text(notification.title)),
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
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Source: ${notification.source}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          if (notification.type == 'staff_approval' && _isAdmin)
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

  Widget _buildErrorState(Object? error) {
    final scheme = Theme.of(context).colorScheme;
    final isIndexError = error != null
        ? _isIndexError(error)
        : (_error?.contains('index') ?? false);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isIndexError ? Icons.build_outlined : Icons.error_outline,
                size: 64,
                color: isIndexError ? AppTheme.warning : scheme.error),
            const SizedBox(height: 16),
            Text(
              isIndexError
                  ? 'Notifications are getting set up'
                  : "We couldn't load notifications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isIndexError
                  ? 'Please try again in a moment. This usually settles right after setup.'
                  : 'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadIdentity,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required String filteredBy, required bool hasAny}) {
    final scheme = Theme.of(context).colorScheme;
    final isFiltered = filteredBy != 'All' || hasAny;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_outlined,
                size: 64, color: scheme.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No $filteredBy notifications'
                  : 'No notifications yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try another filter or pull to refresh.'
                  : "Updates for your eatery will appear here as things happen.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
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
