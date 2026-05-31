import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  String? _error;
  bool _isIndexError = false;
  List<NotificationItem> _notifications = [];
  String? _eateryId;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryId = (profile?['eateryId'] ?? '').toString();

      if (eateryId.isEmpty) {
        setState(() {
          _error = 'No eatery associated with this account';
          _isLoading = false;
        });
        return;
      }

      _eateryId = eateryId;

      // Fetch all data sources in parallel
      final results = await Future.wait([
        _fetchStoredNotifications(eateryId),
        _fetchInventoryNotifications(eateryId),
        _fetchPayableNotifications(eateryId),
      ]);

      // Combine all notifications
      final allNotifications = <NotificationItem>[];
      for (final list in results) {
        allNotifications.addAll(list);
      }

      // Sort by createdAt/due date descending
      allNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _notifications = allNotifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString();
        String displayError;
        bool isIndexError = false;

        if (errorStr.contains('failed-precondition') &&
            errorStr.contains('index')) {
          displayError =
              'Database index required. Please create a composite index for eateryId + createdAt in Firebase Console.';
          isIndexError = true;
        } else {
          displayError = 'Failed to load notifications: $e';
        }

        setState(() {
          _error = displayError;
          _isLoading = false;
          _isIndexError = isIndexError;
        });
      }
    }
  }

  Future<List<NotificationItem>> _fetchStoredNotifications(
      String eateryId) async {
    try {
      QuerySnapshot snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('eateryId', isEqualTo: eateryId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get();
      } catch (e) {
        if (e.toString().contains('failed-precondition') ||
            e.toString().contains('index')) {
          snapshot = await FirebaseFirestore.instance
              .collection('notifications')
              .where('eateryId', isEqualTo: eateryId)
              .limit(100)
              .get();
        } else {
          rethrow;
        }
      }

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return NotificationItem(
          id: doc.id,
          title: data['title'] ?? 'Notification',
          body: data['body'] ?? '',
          type: data['type'] ?? 'general',
          isRead: data['isRead'] ?? false,
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          data: data,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<NotificationItem>> _fetchInventoryNotifications(
      String eateryId) async {
    try {
      final result = await ApiService.getInventoryItems();
      final items = result['data'] as List<dynamic>? ?? [];
      final notifications = <NotificationItem>[];

      for (final item in items) {
        final name = (item['name'] ?? 'Unknown Item').toString();
        final currentStock = (item['currentStock'] as num?)?.toDouble() ?? 0;
        final minStock = (item['minStock'] as num?)?.toDouble() ?? 0;
        final unit = (item['unit'] ?? '').toString();
        final id = (item['id'] ?? '').toString();

        if (currentStock <= 0) {
          // Out of stock notification
          notifications.add(NotificationItem(
            id: 'out_of_stock_$id',
            title: 'Out of Stock: $name',
            body:
                '$name is currently out of stock. Please restock immediately.',
            type: 'out_of_stock',
            isRead: false,
            createdAt: DateTime.now(),
            data: {'itemId': id, 'type': 'inventory', 'priority': 'high'},
          ));
        } else if (currentStock <= minStock && minStock > 0) {
          // Low stock notification
          notifications.add(NotificationItem(
            id: 'low_stock_$id',
            title: 'Low Stock: $name',
            body:
                '$name is running low. Current: $currentStock $unit (Min: $minStock $unit)',
            type: 'low_stock',
            isRead: false,
            createdAt: DateTime.now(),
            data: {'itemId': id, 'type': 'inventory', 'priority': 'medium'},
          ));
        }
      }

      return notifications;
    } catch (e) {
      return [];
    }
  }

  Future<List<NotificationItem>> _fetchPayableNotifications(
      String eateryId) async {
    try {
      final result = await ApiService.getPayables();
      final items = result['data'] as List<dynamic>? ?? [];
      final notifications = <NotificationItem>[];
      final now = DateTime.now();

      for (final item in items) {
        final name = (item['name'] ?? 'Unknown Bill').toString();
        final dueDateStr = item['dueDate']?.toString();
        final status = (item['status'] ?? 'unpaid').toString().toLowerCase();
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final id = (item['id'] ?? '').toString();

        if (dueDateStr == null || dueDateStr.isEmpty) continue;

        final dueDate = DateTime.tryParse(dueDateStr);
        if (dueDate == null) continue;

        final daysUntil = dueDate.difference(now).inDays;

        // Only notify for unpaid bills
        if (status != 'paid') {
          if (daysUntil < 0) {
            // Overdue
            notifications.add(NotificationItem(
              id: 'overdue_$id',
              title: 'Overdue Bill: $name',
              body: amount > 0
                  ? '$name is overdue by ${daysUntil.abs()} days. Amount: ₱${amount.toStringAsFixed(2)}'
                  : '$name is overdue by ${daysUntil.abs()} days. Variable amount.',
              type: 'bill_overdue',
              isRead: false,
              createdAt: dueDate,
              data: {'payableId': id, 'type': 'payable', 'priority': 'high'},
            ));
          } else if (daysUntil <= 3) {
            // Due soon (within 3 days)
            String dueText;
            if (daysUntil == 0) {
              dueText = 'today';
            } else if (daysUntil == 1) {
              dueText = 'tomorrow';
            } else {
              dueText = 'in $daysUntil days';
            }
            notifications.add(NotificationItem(
              id: 'due_soon_$id',
              title: 'Bill Due Soon: $name',
              body: amount > 0
                  ? '$name is due $dueText. Amount: ₱${amount.toStringAsFixed(2)}'
                  : '$name is due $dueText. Variable amount.',
              type: 'bill_due_soon',
              isRead: false,
              createdAt: dueDate,
              data: {'payableId': id, 'type': 'payable', 'priority': 'medium'},
            ));
          }
        }
      }

      return notifications;
    } catch (e) {
      return [];
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});

      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notificationId);
        if (index != -1) {
          _notifications[index] = NotificationItem(
            id: _notifications[index].id,
            title: _notifications[index].title,
            body: _notifications[index].body,
            type: _notifications[index].type,
            isRead: true,
            createdAt: _notifications[index].createdAt,
            data: _notifications[index].data,
          );
        }
      });
    } catch (e) {}
  }

  Future<void> _markAllAsRead() async {
    final unreadIds =
        _notifications.where((n) => !n.isRead).map((n) => n.id).toList();

    if (unreadIds.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in unreadIds) {
        final ref =
            FirebaseFirestore.instance.collection('notifications').doc(id);
        batch.update(
            ref, {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();

      setState(() {
        _notifications = _notifications
            .map((n) => NotificationItem(
                  id: n.id,
                  title: n.title,
                  body: n.body,
                  type: n.type,
                  isRead: true,
                  createdAt: n.createdAt,
                  data: n.data,
                ))
            .toList();
      });
    } catch (e) {}
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();

      setState(() {
        _notifications.removeWhere((n) => n.id == notificationId);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  IconData _getIconForType(String type) {
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
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _getColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'out_of_stock':
        return Colors.red;
      case 'low_stock':
      case 'inventory':
        return Colors.orange;
      case 'bill_overdue':
        return Colors.red;
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
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} hr ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            if (_unreadCount > 0)
              Text(
                '$_unreadCount unread',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _notifications.isEmpty
                  ? _buildEmptyState()
                  : _buildNotificationList(),
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
            Icon(
              isIndexError ? Icons.build_outlined : Icons.error_outline,
              size: 64,
              color:
                  isIndexError ? Colors.orange.shade400 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isIndexError
                  ? 'Database Setup Required'
                  : 'Error Loading Notifications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (isIndexError)
              Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Create Firestore Index'),
                          content: const Text(
                            'You need to create a composite index for:\n\n'
                            'Collection: notifications\n'
                            'Fields:\n'
                            '  - eateryId (Ascending)\n'
                            '  - createdAt (Descending)\n\n'
                            '1. Go to Firebase Console > Firestore Database > Indexes\n'
                            '2. Click "Add Index"\n'
                            '3. Select "notifications" collection\n'
                            '4. Add fields: eateryId (Ascending), createdAt (Descending)\n'
                            '5. Click Create (takes ~5 minutes)\n\n'
                            'After creating the index, click Retry below.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.build),
                    label: const Text('How to Fix'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadNotifications,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: _loadNotifications,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Notifications will appear here when important events occur, like low stock alerts or upcoming bills.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationList() {
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _buildNotificationTile(notification);
        },
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem notification) {
    final icon = _getIconForType(notification.type);
    final color = _getColorForType(notification.type);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNotification(notification.id),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight:
                notification.isRead ? FontWeight.normal : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: notification.isRead ? Colors.grey : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(notification.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
        onTap: () {
          if (!notification.isRead) {
            _markAsRead(notification.id);
          }
          _showNotificationDetail(notification);
        },
      ),
    );
  }

  void _showNotificationDetail(NotificationItem notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getIconForType(notification.type),
              color: _getColorForType(notification.type),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                notification.title,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 16),
            Text(
              'Received: ${DateFormat('MMM d, yyyy • h:mm a').format(notification.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (notification.data.containsKey('relatedId')) ...[
              const SizedBox(height: 8),
              Text(
                'Related ID: ${notification.data['relatedId']}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (notification.data['action'] != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Handle action navigation
              },
              child: const Text('View Details'),
            ),
        ],
      ),
    );
  }
}

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    required this.data,
  });
}
