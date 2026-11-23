import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/notification_item.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/notification_badge_provider.dart';
import '../services/notification_repository.dart';
import '../services/notification_trigger_manager.dart';
import '../theme.dart';
import '../utils/notification_visibility.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/smart_eat_header.dart';
import 'admin_tab_index.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'staff_management_screen.dart';

String notificationDocId(String eateryId, String key) =>
    buildNotificationDocId(eateryId, key);

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

  final NotificationRepository _repository = NotificationRepository();
  Timer? _pollTimer;
  bool _isProfileLoading = true;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  String? _bannerError;
  String _filter = 'All';
  String _eateryId = '';
  String _uid = '';
  bool _isAdmin = false;
  bool _isManager = false;
  List<NotificationItem> _notifications = const <NotificationItem>[];
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _syncBadge(List<NotificationItem> items) {
    if (!mounted) return;
    context.read<NotificationBadgeProvider>().setCount(
          items.where((item) => !item.isRead && !item.ignored).length,
        );
  }

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
      final isManager = role == 'manager' || role == 'owner';
      if (!mounted) return;
      setState(() {
        _eateryId = eateryId;
        _uid = uid;
        _isAdmin = isAdmin;
        _isManager = isManager;
        _isProfileLoading = false;
      });
      _initializeFeed();
      _runSystemSync();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load notifications: $e';
        _isProfileLoading = false;
      });
    }
  }

  Future<void> _initializeFeed() async {
    final cached = await _repository.readCache(_uid);
    if (!mounted) return;
    setState(() {
      _notifications = cached;
      _hasLoaded = cached.isNotEmpty;
    });
    await _loadNotifications();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadNotifications(silent: true);
    });
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (_uid.isEmpty) return;
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final items = await _repository.fetch();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _hasLoaded = true;
        _bannerError = null;
        _isLoading = false;
      });
      _syncBadge(items);
      await _repository.writeCache(_uid, items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_hasLoaded) {
          _bannerError = 'Showing saved notifications. ${e.toString()}';
        } else {
          _error = e.toString();
        }
      });
    }
  }

  void _runSystemSync() {
    ApiService.syncSystemNotifications().catchError((_) => 0);
    NotificationTriggerManager().runImmediateCheck('all').catchError((_) {});
  }

  Future<void> _refresh() async {
    if (_eateryId.isEmpty) return;
    NotificationTriggerManager().runImmediateCheck('all').catchError((_) {});
    await ApiService.syncSystemNotifications().catchError((_) => 0);
    await _loadNotifications();
  }

  Future<void> _markAsRead(NotificationItem notification) async {
    if (_uid.isEmpty || notification.isRead) return;
    final previous = _notifications;
    final updated = previous
        .map((item) =>
            item.id == notification.id ? item.copyWith(isRead: true) : item)
        .toList();
    if (!mounted) return;
    setState(() => _notifications = updated);
    _syncBadge(updated);
    await _repository.writeCache(_uid, updated);
    try {
      await ApiService.markNotificationRead(notification.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifications = previous);
      await _repository.writeCache(_uid, previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _markAllAsRead(List<NotificationItem> unread) async {
    if (_uid.isEmpty || unread.isEmpty) return;
    final previous = _notifications;
    final ids = unread.map((item) => item.id).toSet();
    final updated = previous
        .map((item) =>
            ids.contains(item.id) ? item.copyWith(isRead: true) : item)
        .toList();
    setState(() {
      _isWorking = true;
      _notifications = updated;
    });
    _syncBadge(updated);
    await _repository.writeCache(_uid, updated);
    try {
      await ApiService.markAllNotificationsRead();
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifications = previous);
      await _repository.writeCache(_uid, previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark all as read: $e')),
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _updatePreference(
    NotificationItem notification, {
    bool? removed,
    bool? pinned,
    bool? ignored,
  }) async {
    final previous = _notifications;
    List<NotificationItem> updated;
    if (removed == true) {
      updated = previous.where((item) => item.id != notification.id).toList();
    } else {
      updated = previous
          .map(
            (item) => item.id == notification.id
                ? item.copyWith(
                    pinned: pinned ?? item.pinned,
                    ignored: ignored ?? item.ignored,
                  )
                : item,
          )
          .toList();
    }
    if (!mounted) return;
    setState(() => _notifications = updated);
    _syncBadge(updated);
    await _repository.writeCache(_uid, updated);
    try {
      await ApiService.updateNotificationPreference(
        notification.id,
        removed: removed,
        pinned: pinned,
        ignored: ignored,
      );
      if (!mounted) return;
      final label = removed == true
          ? 'Notification removed'
          : ignored == true
              ? 'Notification ignored'
              : ignored == false
                  ? 'Notification unignored'
                  : pinned == true
                      ? 'Notification pinned'
                      : 'Notification unpinned';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifications = previous);
      _syncBadge(previous);
      await _repository.writeCache(_uid, previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
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
    filtered.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
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
    final visible = _notifications
        .where((n) => notificationVisibleToUser(
              data: n.data,
              uid: _uid,
              isAdmin: _isAdmin,
              isManager: _isManager,
            ))
        .toList();
    final unread = visible.where((n) => !n.isRead).toList();
    final filtered = _applyFilter(visible);
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: _buildAppBar(unread),
        body: Column(
          children: [
            _buildFilterBar(unread.length),
            if (_bannerError != null)
              Container(
                width: double.infinity,
                color: AppTheme.warning.withValues(alpha: 0.16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  _bannerError!,
                  style: const TextStyle(color: AppTheme.warning),
                ),
              ),
            if (_isWorking || _isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppTheme.sageAccent,
              ),
            Expanded(
              child: _isProfileLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorState(_error)
                      : (_isLoading && !_hasLoaded)
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                              ? _buildEmptyState(
                                  filteredBy: _filter,
                                  hasAny: visible.isNotEmpty,
                                )
                              : _buildNotificationList(filtered),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<NotificationItem> unread) {
    final unreadCount = unread.length;
    return SmartEatHeader(
      titleText: 'Notifications',
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
    return Material(
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: TextStyle(
                  fontWeight:
                      notification.isRead ? FontWeight.w600 : FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (notification.pinned)
              Icon(Icons.push_pin, size: 16, color: AppTheme.warning),
          ],
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
            if (notification.ignored) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ignored',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
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
        trailing: PopupMenuButton<String>(
          tooltip: 'Edit notification',
          onSelected: (value) {
            switch (value) {
              case 'remove':
                _updatePreference(notification, removed: true);
                break;
              case 'pin':
                _updatePreference(notification,
                    pinned: !notification.pinned);
                break;
              case 'ignore':
                _updatePreference(notification,
                    ignored: !notification.ignored);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'remove',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Remove'),
                dense: true,
              ),
            ),
            PopupMenuItem<String>(
              value: 'pin',
              child: ListTile(
                leading: Icon(notification.pinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin),
                title: Text(notification.pinned ? 'Unpin' : 'Pin'),
                dense: true,
              ),
            ),
            PopupMenuItem<String>(
              value: 'ignore',
              child: ListTile(
                leading: Icon(notification.ignored
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined),
                title: Text(notification.ignored ? 'Unignore' : 'Ignore'),
                dense: true,
              ),
            ),
          ],
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.more_vert),
              if (!notification.isRead)
                Positioned(
                  right: 0,
                  top: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
        onTap: () async {
          await _markAsRead(notification);
          if (mounted)
            _showNotificationDetail(notification.copyWith(isRead: true));
        },
      ),
    );
  }

  void _showNotificationDetail(NotificationItem notification) {
    final scheme = Theme.of(context).colorScheme;
    final hasRoute = _sourceTarget(notification).isNotEmpty;
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notification.body),
              if (notification.details.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Details',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(notification.details.join(', ')),
              ],
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
              if (notification.ignored) ...[
                const SizedBox(height: 6),
                const Text(
                  'ignored',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (hasRoute)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _openSource(notification);
              },
              child: const Text('Open source'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  String _sourceTarget(NotificationItem notification) {
    final target = notification.route.isNotEmpty
        ? notification.route
        : (notification.data['target'] ?? notification.data['route'] ?? '')
            .toString();
    return target.trim().toLowerCase();
  }

  Future<void> _openSource(NotificationItem notification) async {
    final target = _sourceTarget(notification);
    Widget? destination;
    switch (target) {
      case 'staff':
      case 'staff_approval':
        destination = const StaffManagementScreen(initialTabIndex: 0);
        break;
      case 'attendance':
      case 'staff_attendance':
        destination = _isAdmin
            ? const StaffManagementScreen(initialTabIndex: 1)
            : const ProfileScreen();
        break;
      case 'inventory':
      case 'low_stock':
      case 'out_of_stock':
        destination = const DashboardScreen(
            initialTabIndex: AdminTabIndex.inventory);
        break;
      case 'finance':
      case 'payables':
      case 'bill_due_soon':
      case 'bill_overdue':
        destination =
            const DashboardScreen(initialTabIndex: AdminTabIndex.finance);
        break;
      case 'orders':
      case 'pending_orders':
        destination =
            const DashboardScreen(initialTabIndex: AdminTabIndex.orders);
        break;
      case 'dashboard':
        destination = const DashboardScreen();
        break;
    }
    if (destination == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<dynamic>(builder: (_) => destination!),
    );
  }

  Widget _buildErrorState(Object? error) {
    final scheme = Theme.of(context).colorScheme;
    final message = error?.toString() ?? 'Unknown notification service error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 64, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              "We couldn't load notifications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refresh,
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
