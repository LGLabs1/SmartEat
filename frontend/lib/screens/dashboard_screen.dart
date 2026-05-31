import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/notification_trigger_manager.dart';
import '../services/sound_service.dart';
import '../widgets/skeleton_loaders.dart';
import 'pos_screen.dart';
import 'analytics_screen.dart';
import 'menu_screen.dart';
import 'inventory_screen.dart';
import 'staff_management_screen.dart';
import 'finance_screen.dart';
import 'chatbot_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class StaffHomeTab extends StatefulWidget {
  const StaffHomeTab({Key? key, required this.onNavigate}) : super(key: key);

  final ValueChanged<int> onNavigate;

  @override
  State<StaffHomeTab> createState() => _StaffHomeTabState();
}

class _StaffHomeTabState extends State<StaffHomeTab> {
  String _eateryName = '';
  Stream<List<Map<String, dynamic>>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    _initOrdersStream();
  }

  void _initOrdersStream() async {
    final profile = await context.read<AuthProvider>().getCurrentUserProfile();
    final eateryName = (profile?['eateryName'] ?? '').toString().trim();

    if (mounted) {
      setState(() {
        _eateryName = eateryName;
      });
    }

    final stream = await FirebaseService.getTodayOrdersStream();
    if (mounted) {
      setState(() {
        _ordersStream = stream;
      });
    }
  }

  void _showStaffMealDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const StaffMealDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async => _initOrdersStream(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildQuickActionsAndStats(context, orders),
              const SizedBox(height: 16),
              _buildTodayOrders(orders),
              const SizedBox(height: 16),
              _buildTopSellingItems(orders),
              const SizedBox(height: 16),
              _buildRecentActivity(orders),
              const SizedBox(height: 16),
              _buildRevenueStats(orders),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsAndStats(
      BuildContext context, List<Map<String, dynamic>> orders) {
    final pendingCount = orders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'pending';
    }).length;
    final completedCount = orders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'completed';
    }).length;

    final isNarrow = MediaQuery.of(context).size.width < 500;

    final quickActions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChip(
          icon: Icons.shopping_cart,
          label: 'POS',
          color: Colors.blue,
          onTap: () => widget.onNavigate(0),
          compact: true,
        ),
        _ActionChip(
          icon: Icons.restaurant_menu,
          label: 'Menu',
          color: Colors.teal,
          onTap: () => widget.onNavigate(2),
          compact: true,
        ),
        _ActionChip(
          icon: Icons.food_bank,
          label: 'Staff Meal',
          color: Colors.orange,
          onTap: () => _showStaffMealDialog(context),
          compact: true,
        ),
      ],
    );

    final statsRow = Row(
      children: [
        Expanded(
          child: _CompactStatCard(
            icon: Icons.receipt_outlined,
            label: 'Total',
            value: orders.length.toString(),
            color: Colors.indigo,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactStatCard(
            icon: Icons.schedule,
            label: 'Pending',
            value: pendingCount.toString(),
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactStatCard(
            icon: Icons.check_circle_outline,
            label: 'Done',
            value: completedCount.toString(),
            color: Colors.green,
          ),
        ),
      ],
    );

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  quickActions,
                  const Divider(height: 16),
                  statsRow,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: quickActions,
                  ),
                  const VerticalDivider(width: 16, thickness: 1),
                  Expanded(
                    flex: 3,
                    child: statsRow,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.storefront,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _eateryName.isEmpty
                        ? 'Quick access for staff'
                        : _eateryName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayOrders(List<Map<String, dynamic>> orders) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    color: Colors.grey.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Today\'s Orders',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                if (orders.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${orders.length} orders',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (orders.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No orders yet today',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...orders.take(10).map((order) {
                final id = (order['id'] ?? '').toString();
                final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final status = (order['status'] ?? '').toString().trim();
                final statusKey = status.toLowerCase();
                final itemsRaw = order['items'];
                final items = itemsRaw is List ? itemsRaw : const [];

                // Color coding based on status
                Color statusColor;
                Color statusBgColor;
                IconData statusIcon;

                switch (statusKey) {
                  case 'completed':
                    statusColor = Colors.green;
                    statusBgColor = Colors.green.withValues(alpha: 0.1);
                    statusIcon = Icons.check_circle;
                    break;
                  case 'pending':
                    statusColor = Colors.orange;
                    statusBgColor = Colors.orange.withValues(alpha: 0.1);
                    statusIcon = Icons.schedule;
                    break;
                  case 'rejected':
                  case 'voided':
                    statusColor = Colors.red;
                    statusBgColor = Colors.red.withValues(alpha: 0.1);
                    statusIcon = Icons.cancel;
                    break;
                  default:
                    statusColor = Colors.grey;
                    statusBgColor = Colors.grey.withValues(alpha: 0.1);
                    statusIcon = Icons.help_outline;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: id.isEmpty
                        ? null
                        : () {
                            _showOrderDetails(order);
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              statusIcon,
                              color: statusColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  id.isEmpty
                                      ? 'Order'
                                      : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${items.length} item${items.length != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  status.isEmpty ? 'Unknown' : status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSellingItems(List<Map<String, dynamic>> orders) {
    // Calculate top selling items from all orders
    final itemCounts = <String, Map<String, dynamic>>{};
    for (final order in orders) {
      final items = order['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        if (item is Map) {
          final name = (item['name'] ?? 'Unknown').toString();
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          if (itemCounts.containsKey(name)) {
            itemCounts[name]!['count'] =
                (itemCounts[name]!['count'] as int) + qty;
          } else {
            itemCounts[name] = {'name': name, 'count': qty};
          }
        }
      }
    }

    final sortedItems = itemCounts.values.toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    final topItems = sortedItems.take(5).toList();

    if (topItems.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up,
                    color: Colors.purple.shade400, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Top Selling Today',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...topItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final name = item['name'] as String;
              final count = item['count'] as int;
              final colors = [
                Colors.amber.shade400,
                Colors.grey.shade400,
                Colors.orange.shade300,
                Colors.blue.shade300,
                Colors.green.shade300,
              ];
              final rankColor =
                  colors[index < colors.length ? index : colors.length - 1];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count sold',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(List<Map<String, dynamic>> orders) {
    // Get orders completed in the last 2 hours
    final now = DateTime.now();
    final twoHoursAgo = now.subtract(const Duration(hours: 2));

    final recentCompleted = orders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'completed') return false;
      final createdAt = o['createdAt'];
      if (createdAt == null) return false;
      DateTime? orderTime;
      if (createdAt is Timestamp) {
        orderTime = createdAt.toDate();
      } else if (createdAt is DateTime) {
        orderTime = createdAt;
      }
      if (orderTime == null) return false;
      return orderTime.isAfter(twoHoursAgo);
    }).toList()
      ..sort((a, b) {
        final aTime = a['createdAt'] is Timestamp
            ? (a['createdAt'] as Timestamp).toDate()
            : a['createdAt'] as DateTime?;
        final bTime = b['createdAt'] is Timestamp
            ? (b['createdAt'] as Timestamp).toDate()
            : b['createdAt'] as DateTime?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

    if (recentCompleted.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.update, color: Colors.teal.shade400, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Last 2 hours',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...recentCompleted.take(5).map((order) {
              final id = (order['id'] ?? '').toString();
              final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
              final createdAt = order['createdAt'];
              String timeAgo = '';
              if (createdAt is Timestamp) {
                final dateTime = createdAt.toDate();
                final diff = now.difference(dateTime);
                if (diff.inMinutes < 60) {
                  timeAgo = '${diff.inMinutes}m ago';
                } else {
                  timeAgo = '${diff.inHours}h ago';
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green.shade500,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            id.isEmpty
                                ? 'Order Completed'
                                : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)} completed',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '₱${total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueStats(List<Map<String, dynamic>> orders) {
    final completedOrders = orders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'completed';
    }).toList();

    final totalRevenue = completedOrders.fold<double>(0, (sum, o) {
      return sum + ((o['totalAmount'] as num?)?.toDouble() ?? 0.0);
    });

    final pendingRevenue = orders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'pending';
    }).fold<double>(0, (sum, o) {
      return sum + ((o['totalAmount'] as num?)?.toDouble() ?? 0.0);
    });

    final avgOrderValue = completedOrders.isNotEmpty
        ? totalRevenue / completedOrders.length
        : 0.0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_money,
                    color: Colors.green.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Today\'s Revenue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _RevenueStatItem(
                    label: 'Completed Sales',
                    value: '₱${totalRevenue.toStringAsFixed(0)}',
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _RevenueStatItem(
                    label: 'Pending Sales',
                    value: '₱${pendingRevenue.toStringAsFixed(0)}',
                    icon: Icons.schedule,
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _RevenueStatItem(
                    label: 'Avg Order',
                    value: '₱${avgOrderValue.toStringAsFixed(0)}',
                    icon: Icons.calculate,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final id = (order['id'] ?? '').toString();
    final items = order['items'] as List<dynamic>? ?? [];
    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final status = (order['status'] ?? 'unknown').toString();
    final createdAt = order['createdAt'];
    final isPending = status.trim().toLowerCase() == 'pending';

    // Format the timestamp
    String? formattedDate;
    if (createdAt != null) {
      if (createdAt is Timestamp) {
        final dateTime = createdAt.toDate();
        formattedDate = _formatDateTime(dateTime);
      } else if (createdAt is DateTime) {
        formattedDate = _formatDateTime(createdAt);
      }
    }

    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(id.isEmpty
              ? 'Order Details'
              : 'Order #${id.substring(0, id.length > 8 ? 8 : id.length)}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: ${status.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Total: ₱${total.toStringAsFixed(2)}'),
                if (formattedDate != null) ...[
                  const SizedBox(height: 4),
                  Text('Created: $formattedDate'),
                ],
                const SizedBox(height: 16),
                const Text('Items:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final name = (item is Map
                      ? (item['name'] ?? 'Unknown').toString()
                      : 'Unknown');
                  final qty = (item is Map ? (item['quantity'] ?? 1) : 1);
                  final price = (item is Map
                      ? (item['price'] as num?)?.toDouble() ?? 0.0
                      : 0.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('$qty x $name'),
                        const Spacer(),
                        Text('₱${(price * qty).toStringAsFixed(2)}'),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            if (isPending) ...[
              // Complete button
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await ApiService.completeOrder(id);
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content: Text('Order completed successfully.')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Failed to complete order: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Complete'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
              // Edit button
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showEditOrderDialog(order);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue),
              ),
              // Void button
              FilledButton.icon(
                onPressed: () async {
                  final controller = TextEditingController();
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Void Order'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Reason (optional)',
                          hintText: 'Enter reason for voiding',
                        ),
                        maxLines: 2,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Void'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await ApiService.voidOrder(id, reason: controller.text);
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Order voided successfully.')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to void order: $e')),
                    );
                  } finally {
                    controller.dispose();
                  }
                },
                icon: const Icon(Icons.cancel),
                label: const Text('Void'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    final year = dateTime.year;
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year at $hour:$minute $period';
  }

  Future<void> _showEditOrderDialog(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;

    // Get current items
    final itemsRaw = order['items'] as List<dynamic>? ?? [];
    final currentItems = List<Map<String, dynamic>>.from(
      itemsRaw.where((item) => item is Map).cast<Map<String, dynamic>>(),
    );

    // Load available menu items
    List<Map<String, dynamic>> menuItems = [];
    try {
      final response = await ApiService.getMenuItems();
      if (response['data'] != null) {
        final items = response['data'] as List<dynamic>;
        menuItems = items
            .where((item) => item is Map)
            .cast<Map<String, dynamic>>()
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load menu: $e')),
        );
      }
      return;
    }

    // Track items to add
    final List<Map<String, dynamic>> itemsToAdd = [];
    double additionalTotal = 0.0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current items section
                    const Text(
                      'Current Items',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: currentItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          return Row(
                            children: [
                              Expanded(child: Text('$qty x $name')),
                              Text('₱${(price * qty).toStringAsFixed(2)}'),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 24),

                    // Add items section
                    const Text(
                      'Add Items',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: menuItems.length,
                        itemBuilder: (context, index) {
                          final item = menuItems[index];
                          final name = (item['name'] ?? 'Unknown').toString();
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          final itemId = (item['id'] ?? '').toString();

                          // Find if this item is already in itemsToAdd
                          final existingIndex = itemsToAdd.indexWhere(
                            (i) =>
                                (i['menuId'] ?? i['id'] ?? '').toString() ==
                                itemId,
                          );
                          final existingQty = existingIndex >= 0
                              ? (itemsToAdd[existingIndex]['quantity'] as num?)
                                      ?.toInt() ??
                                  0
                              : 0;

                          return ListTile(
                            dense: true,
                            title: Text(name),
                            subtitle: Text('₱${price.toStringAsFixed(2)}'),
                            trailing: existingQty > 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                                  ['quantity']
                                                              as num?)
                                                          ?.toInt() ??
                                                      1;
                                              if (currentQty <= 1) {
                                                itemsToAdd
                                                    .removeAt(existingIndex);
                                              } else {
                                                itemsToAdd[existingIndex]
                                                        ['quantity'] =
                                                    currentQty - 1;
                                              }
                                              additionalTotal -= price;
                                            }
                                          });
                                        },
                                      ),
                                      Text('$existingQty'),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                                  ['quantity']
                                                              as num?)
                                                          ?.toInt() ??
                                                      1;
                                              itemsToAdd[existingIndex]
                                                  ['quantity'] = currentQty + 1;
                                            }
                                            additionalTotal += price;
                                          });
                                        },
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    onPressed: () {
                                      setLocalState(() {
                                        itemsToAdd.add({
                                          'menuId': itemId,
                                          'name': name,
                                          'price': price,
                                          'quantity': 1,
                                        });
                                        additionalTotal += price;
                                      });
                                    },
                                  ),
                          );
                        },
                      ),
                    ),

                    // Additional total
                    if (itemsToAdd.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Additional Amount:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₱${additionalTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                if (itemsToAdd.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.save),
                    label: const Text('Add Items'),
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == true && itemsToAdd.isNotEmpty && mounted) {
      try {
        await ApiService.addItemsToOrder(orderId, itemsToAdd);
        // Refresh the page
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Items added to order successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _selectedIndexKey = 'dashboard_selected_index';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _isRoleLoading = true;
  String? _roleError;
  bool _isAdmin = false;
  bool _isApprovedStaff = true;
  bool _isApprovalRefreshing = false;
  bool _adminViewEnabled = true;
  bool _inventoryInDetailView = false;
  final GlobalKey<InventoryScreenState> _inventoryKey =
      GlobalKey<InventoryScreenState>();
  String _eateryName = '';
  String _eateryId = '';
  String _displayName = '';
  String? _lastLoadedUid;
  final ValueNotifier<String> _globalSearchQuery = ValueNotifier<String>('');
  final TextEditingController _globalSearchController = TextEditingController();
  final NotificationTriggerManager _notificationTriggers =
      NotificationTriggerManager();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  bool _sidebarVisible = true;
  bool _removalDialogShown = false;

  bool get _isAdminRole {
    return _isAdmin && _adminViewEnabled;
  }

  bool get _canSwitchDashboard {
    return _isAdmin;
  }

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
    _startUserDocListener();
    _notificationTriggers.startPeriodicChecks();
  }

  bool _sidebarInitialized = false;

  void _startUserDocListener() {
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.trim().isEmpty) return;

      _userDocSub?.cancel();
      _userDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((snap) async {
        if (!mounted) return;
        if (!snap.exists) return;

        final data = snap.data() ?? <String, dynamic>{};
        final removalMessage = (data['removalMessage'] ?? '').toString().trim();
        final removedAt = data['removedAt'];
        final removedFromEateryId =
            (data['removedFromEateryId'] ?? '').toString().trim();

        if (removalMessage.isEmpty) return;
        if (_removalDialogShown) return;

        _removalDialogShown = true;

        try {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return AlertDialog(
                title: const Text('Access Removed'),
                content: Text(removalMessage),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        } finally {
          if (!mounted) return;

          // Clear local role state to avoid any UI loops while logout happens.
          setState(() {
            _isRoleLoading = false;
            _roleError = null;
            _eateryId = '';
            _eateryName = '';
          });

          try {
            await context.read<AuthProvider>().logout();
          } catch (_) {}
        }

        // Best-effort cleanup of the message so the dialog doesn't keep re-appearing
        // when the user logs in again or when snapshot replays.
        try {
          if (removedFromEateryId.isNotEmpty || removedAt != null) {
            await FirebaseFirestore.instance.collection('users').doc(uid).set({
              'removalMessage': '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (_) {}
      });
    } catch (e) {}
  }

  Future<void> _initializeDashboard() async {
    await _loadRole();
    if (mounted) {
      await _loadSavedTabIndex();
    }
  }

  Future<void> _loadSavedTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_selectedIndexKey);
      if (savedIndex != null && mounted) {
        // Wait for role to be loaded first, then validate the saved index
        // _isAdmin is set by _loadRole() which runs in initState
        final maxTabs = _isAdmin ? 6 : 3;
        if (savedIndex >= 0 && savedIndex < maxTabs) {
          setState(() => _selectedIndex = savedIndex);
        }
      }
    } catch (e) {}
  }

  Future<void> _saveTabIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_selectedIndexKey, index);
    } catch (e) {}
  }

  @override
  void dispose() {
    _notificationTriggers.dispose();
    _globalSearchController.dispose();
    _globalSearchQuery.dispose();
    _userDocSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize sidebar visibility based on screen width (only once)
    if (!_sidebarInitialized) {
      final screenWidth = MediaQuery.of(context).size.width;
      _sidebarVisible = screenWidth >= 768;
      _sidebarInitialized = true;
    }
    // Handle user auth changes
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) {
      // User logged out, stop loading
      if (_isRoleLoading) {
        setState(() => _isRoleLoading = false);
      }
      return;
    }
    if (uid != _lastLoadedUid) {
      _lastLoadedUid = uid;
      _loadRole();
    }
  }

  Future<void> _loadRole({bool setLoadingState = true}) async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      // Turn off loading; AuthGate handles routing to login.
      if (setLoadingState) {
        setState(() => _isRoleLoading = false);
      }
      return;
    }

    if (setLoadingState) {
      setState(() {
        _isRoleLoading = true;
        _roleError = null;
      });
    }

    try {
      final profile = await context
          .read<AuthProvider>()
          .getCurrentUserProfile()
          .timeout(const Duration(seconds: 12));
      if (profile == null) {
        throw Exception('Profile not found');
      }
      final role = (profile['role'] ?? '').toString().trim().toLowerCase();
      final dynamic isAdminRaw = profile['isAdmin'];
      final bool isAdminFlag = isAdminRaw == true ||
          isAdminRaw == 1 ||
          (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
      final isAdmin = isAdminFlag || role == 'admin';

      final dynamic approvedRaw = profile['approved'];
      final bool approved = approvedRaw == null ? true : approvedRaw == true;
      final eateryName = (profile['eateryName'] ?? '').toString().trim();
      final eateryId = (profile['eateryId'] ?? '').toString().trim();
      final firstName = (profile['firstName'] ?? '').toString().trim();
      final lastName = (profile['lastName'] ?? '').toString().trim();
      final displayName = ('$firstName $lastName').trim();
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _isApprovedStaff = approved;
        _eateryName = eateryName;
        _eateryId = eateryId;
        _displayName = displayName;
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roleError =
            'Failed to load profile. Please check your connection and Firestore rules.\n\n$e';
        if (setLoadingState) {
          _isRoleLoading = false;
        }
      });
    }
  }

  Future<void> _refreshApprovalStatus() async {
    setState(() {
      _isApprovalRefreshing = true;
      _roleError = null;
    });
    try {
      await _loadRole(setLoadingState: false);
    } finally {
      if (!mounted) return;
      setState(() {
        _isApprovalRefreshing = false;
      });
    }
  }

  void _goToTab(int index) {
    if (!mounted) return;
    // Prevent navigation while role is loading
    if (_isRoleLoading) {
      return;
    }
    try {
      // Validate index against available tabs
      final isAdmin = _isAdminRole;
      final maxTabs = isAdmin ? 6 : 3;
      if (index < 0 || index >= maxTabs) {
        return;
      }
      setState(() => _selectedIndex = index);
      _saveTabIndex(index);
    } catch (e) {}
  }

  void _setAdminViewEnabled(bool enabled) {
    if (!mounted) return;
    // Prevent view switch while role is loading
    if (_isRoleLoading) {
      return;
    }
    try {
      setState(() {
        _adminViewEnabled = enabled;
        _selectedIndex = 0;
      });
      _saveTabIndex(0);
    } catch (e) {}
  }

  Future<void> _showGlobalSearchResults(String query) async {
    final results = await showDialog<List<_GlobalSearchResult>>(
      context: context,
      builder: (context) => _GlobalSearchDialog(query: query),
    );

    if (results != null && results.isNotEmpty) {
      final result = results.first;
      // Navigate based on result type
      switch (result.type) {
        case 'menu':
          _goToTab(_isAdminRole ? 1 : 2);
          break;
        case 'inventory':
          if (_isAdminRole) {
            _goToTab(2);
          }
          break;
        case 'order':
          _goToTab(0);
          break;
      }
    }
  }

  String _pageTitleForIndex(int index) {
    if (_isAdminRole) {
      switch (index) {
        case 0:
          return 'Home';
        case 1:
          return 'Menu';
        case 2:
          return 'Inventory';
        case 3:
          return 'Analytics Dashboard';
        case 4:
          return 'Finance';
        case 5:
          return 'Staff';
        default:
          return 'Smart Eat';
      }
    }

    switch (index) {
      case 0:
        return 'POS';
      case 1:
        return 'Home';
      case 2:
        return 'Menu';
      default:
        return 'Smart Eat';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRoleLoading) {
      return const SkeletonDashboard();
    }

    if (_roleError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Smart Eat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to load profile: $_roleError',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadRole,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isAdmin && !_isApprovedStaff) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Smart Eat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'Your account is pending admin approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask your admin to approve your account. Once approved, tap Refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isApprovalRefreshing ? null : _refreshApprovalStatus,
                      child: _isApprovalRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Refresh'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => context.read<AuthProvider>().logout(),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tabs = _isAdminRole
        ? <Widget>[
            DashboardHomeTab(
                key: const ValueKey('dashboard_home'), onNavigate: _goToTab),
            MenuScreen(
                key: const ValueKey('menu'),
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false),
            InventoryScreen(
              key: _inventoryKey,
              globalSearchQuery: _globalSearchQuery,
              showAppBar: false,
              onBackNeeded: () => setState(() => _inventoryInDetailView = true),
              onOpenDrawer: () =>
                  setState(() => _inventoryInDetailView = false),
            ),
            const AnalyticsScreen(
                key: ValueKey('analytics'), showAppBar: false),
            FinanceScreen(
              key: const ValueKey('finance'),
              globalSearchQuery: _globalSearchQuery,
              showAppBar: false,
              onNavigate: _goToTab,
            ),
            StaffManagementScreen(
              key: const ValueKey('staff'),
              globalSearchQuery: _globalSearchQuery,
              showAppBar: false,
            ),
          ]
        : <Widget>[
            const POSScreen(key: ValueKey('pos'), showAppBar: false),
            StaffHomeTab(
                key: const ValueKey('staff_home'), onNavigate: _goToTab),
            MenuScreen(
                key: const ValueKey('menu'),
                globalSearchQuery: _globalSearchQuery,
                showAppBar: false),
          ];

    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 0;
    }

    final isNarrowSearch = MediaQuery.of(context).size.width < 520;
    final searchHint = isNarrowSearch ? '' : 'Search';
    final pageTitle = _pageTitleForIndex(_selectedIndex);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            final showBackButton =
                _selectedIndex == 2 && _inventoryInDetailView;
            return IconButton(
              tooltip: showBackButton
                  ? 'Back'
                  : (_sidebarVisible ? 'Hide Menu' : 'Show Menu'),
              icon: Icon(showBackButton
                  ? Icons.arrow_back
                  : (_sidebarVisible ? Icons.menu_open : Icons.menu)),
              onPressed: _isRoleLoading
                  ? null
                  : () {
                      if (showBackButton) {
                        setState(() => _inventoryInDetailView = false);
                        _inventoryKey.currentState?.resetToGrid();
                      } else {
                        setState(() => _sidebarVisible = !_sidebarVisible);
                      }
                    },
            );
          },
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final maxSearchWidth = constraints.maxWidth >= 900
                ? 420.0
                : constraints.maxWidth >= 600
                    ? 320.0
                    : 200.0;
            final isNarrow = constraints.maxWidth < 520;

            Widget searchField(double maxWidth) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _globalSearchController,
                    onChanged: (v) => _globalSearchQuery.value = v,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        _showGlobalSearchResults(v.trim());
                      }
                    },
                    onTap: () {
                      if (_globalSearchQuery.value.trim().isNotEmpty) {
                        _showGlobalSearchResults(
                            _globalSearchQuery.value.trim());
                      }
                    },
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      suffixIcon: ValueListenableBuilder<String>(
                        valueListenable: _globalSearchQuery,
                        builder: (context, value, _) {
                          if (value.trim().isEmpty) return const SizedBox();
                          return IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _globalSearchController.clear();
                              _globalSearchQuery.value = '';
                            },
                            icon: const Icon(Icons.close, color: Colors.white),
                          );
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.18),
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            }

            final searchWidth = isNarrow
                ? (constraints.maxWidth >= 420
                    ? 180.0
                    : constraints.maxWidth >= 380
                        ? 160.0
                        : 140.0)
                : maxSearchWidth;

            final brandMaxWidth = isNarrow
                ? 130.0
                : constraints.maxWidth >= 900
                    ? 240.0
                    : 180.0;

            final brand = ConstrainedBox(
              constraints: BoxConstraints(maxWidth: brandMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Smart Eat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_eateryName.trim().isNotEmpty)
                    Text(
                      _eateryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                ],
              ),
            );

            final title = Text(
              pageTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            );

            return SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: brand,
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: brandMaxWidth + 12,
                      ),
                      child: title,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: searchField(searchWidth),
                  ),
                ],
              ),
            );
          },
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withBlue(
                      ((Theme.of(context).colorScheme.primary.b * 255.0)
                                  .round() +
                              40)
                          .clamp(0, 255),
                    ),
              ],
            ),
          ),
        ),
        elevation: 2,
        shadowColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'AI Assistant',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChatbotScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 768;

          // Wide screen: persistent sidebar that compresses content
          if (isWideScreen) {
            return Row(
              children: [
                if (_sidebarVisible) _buildSidebar(),
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(
                        index: _selectedIndex,
                        children: tabs,
                      ),
                      if (_isRoleLoading)
                        Container(
                          color: Colors.white.withValues(alpha: 0.8),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Narrow screen: overlay sidebar
          return Stack(
            children: [
              IndexedStack(
                index: _selectedIndex,
                children: tabs,
              ),
              if (_sidebarVisible)
                GestureDetector(
                  onTap: () => setState(() => _sidebarVisible = false),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              if (_sidebarVisible) _buildSidebar(),
              if (_isRoleLoading)
                Container(
                  color: Colors.white.withValues(alpha: 0.8),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    final email = context.read<AuthProvider>().user?.email ?? '';
    final roleLabel = _isAdmin ? 'Admin' : 'Staff';
    final sidebarWidth = 260.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.2),
                  child: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName.isNotEmpty
                            ? _displayName
                            : (email.isNotEmpty ? email : 'Account'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (_eateryName.isNotEmpty)
                        Text(
                          _eateryName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (_canSwitchDashboard)
                  ListTile(
                    leading: Icon(
                      _adminViewEnabled
                          ? Icons.swap_horiz
                          : Icons.admin_panel_settings_outlined,
                    ),
                    title: Text(
                      _adminViewEnabled
                          ? 'Switch to Main Dashboard'
                          : 'Switch to Admin Dashboard',
                    ),
                    onTap: () => _setAdminViewEnabled(!_adminViewEnabled),
                  ),
                if (_isAdminRole) ...[
                  _buildNavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Home',
                    index: 0,
                  ),
                  _buildNavItem(
                    icon: Icons.restaurant_menu,
                    label: 'Menu',
                    index: 1,
                  ),
                  _buildNavItem(
                    icon: Icons.inventory,
                    label: 'Inventory',
                    index: 2,
                  ),
                  _buildNavItem(
                    icon: Icons.analytics,
                    label: 'Analytics',
                    index: 3,
                  ),
                  _buildNavItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Finance',
                    index: 4,
                  ),
                  _buildNavItem(
                    icon: Icons.group_outlined,
                    label: 'Staff',
                    index: 5,
                  ),
                ] else ...[
                  _buildNavItem(
                    icon: Icons.shopping_cart,
                    label: 'POS',
                    index: 0,
                  ),
                  _buildNavItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    index: 1,
                  ),
                  _buildNavItem(
                    icon: Icons.restaurant_menu,
                    label: 'Menu',
                    index: 2,
                  ),
                ],
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () => Navigator.of(context).pushNamed('/settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title:
                      const Text('Logout', style: TextStyle(color: Colors.red)),
                  onTap: () => context.read<AuthProvider>().logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade600,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      onTap: () => _goToTab(index),
    );
  }
}

class DashboardHomeTab extends StatefulWidget {
  const DashboardHomeTab({Key? key, required this.onNavigate})
      : super(key: key);

  final ValueChanged<int> onNavigate;

  @override
  State<DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends State<DashboardHomeTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _todayOrders = const [];
  List<Map<String, dynamic>> _incompleteOrders = const [];
  List<Map<String, dynamic>> _lowStock = const [];
  List<Map<String, dynamic>> _payables = const [];
  List<Map<String, dynamic>> _expenses = const [];
  String _eateryName = '';
  String _completingOrderId = '';
  bool _isAdmin = false;
  bool _isApprovedStaff = true;

  // Notes state
  List<Map<String, dynamic>> _notes = [];
  static const String _notesKey = 'admin_notes';

  void initState() {
    super.initState();
    _loadDashboard();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = prefs.getString(_notesKey);
      if (notesJson != null && notesJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(notesJson);
        setState(() {
          _notes = List<Map<String, dynamic>>.from(decoded);
        });
      }
    } catch (e) {}
  }

  Future<void> _saveNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = jsonEncode(_notes);
      await prefs.setString(_notesKey, notesJson);
    } catch (e) {}
  }

  Future<void> _addNote(String header, String body) async {
    final newNote = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'header': header,
      'body': body,
      'createdAt': DateTime.now().toIso8601String(),
    };
    setState(() {
      _notes.add(newNote);
    });
    await _saveNotes();
  }

  Future<void> _updateNote(String id, String header, String body) async {
    setState(() {
      final index = _notes.indexWhere((note) => note['id'] == id);
      if (index != -1) {
        _notes[index]['header'] = header;
        _notes[index]['body'] = body;
      }
    });
    await _saveNotes();
  }

  Future<void> _deleteNote(String id) async {
    setState(() {
      _notes.removeWhere((note) => note['id'] == id);
    });
    await _saveNotes();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryName = (profile?['eateryName'] ?? '').toString().trim();
      final role = (profile?['role'] ?? '').toString().trim().toLowerCase();
      final dynamic isAdminRaw = profile?['isAdmin'];
      final bool isAdminFlag = isAdminRaw == true ||
          isAdminRaw == 1 ||
          (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
      final isAdmin = isAdminFlag || role == 'admin';
      final bool approved = profile?['approved'] != false;

      final results = await Future.wait([
        ApiService.getSummaryStats(),
        ApiService.getTodayOrders(),
        ApiService.getPendingOrders(limit: 50),
        ApiService.getLowStockItems(),
        ApiService.getPayables(),
        ApiService.getExpenses(),
      ]);

      final summary = results[0]['data'] as Map<String, dynamic>?;
      final orders =
          List<Map<String, dynamic>>.from(results[1]['data'] ?? const []);
      final pendingOrders =
          List<Map<String, dynamic>>.from(results[2]['data'] ?? const []);
      final lowStock =
          List<Map<String, dynamic>>.from(results[3]['data'] ?? const []);
      final payables =
          List<Map<String, dynamic>>.from(results[4]['data'] ?? const []);
      final expenses =
          List<Map<String, dynamic>>.from(results[5]['data'] ?? const []);

      // Filter incomplete orders (pending orders from before today)
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final incompleteOrders = pendingOrders.where((o) {
        final createdAt = _asDate(o['createdAt']);
        if (createdAt == null) return false;
        return createdAt.isBefore(todayStart);
      }).toList();

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _todayOrders = orders;
        _incompleteOrders = incompleteOrders;
        _lowStock = lowStock;
        _payables = payables;
        _expenses = expenses;
        _eateryName = eateryName;
        _isAdmin = isAdmin;
        _isApprovedStaff = approved;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _completeOrder(String orderId) async {
    if (orderId.isEmpty) return;
    setState(() => _completingOrderId = orderId);
    try {
      await ApiService.completeOrder(orderId);
      if (!mounted) return;
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order completed. Stocks updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      String message;
      if (e is FirebaseException) {
        final code = (e.code).toString();
        final details = (e.message ?? '').toString();
        message = details.trim().isEmpty
            ? 'Firebase error: $code'
            : 'Firebase error: $code — $details';
      } else {
        // Aggressive Flutter web error extraction
        dynamic current = e;
        String? bestMessage;
        for (int i = 0; i < 5; i++) {
          if (current is FirebaseException) {
            final code = (current.code).toString();
            final details = (current.message ?? '').toString();
            bestMessage = details.trim().isEmpty
                ? 'Firebase error: $code'
                : 'Firebase error: $code — $details';
            break;
          }
          try {
            // Try various properties that might contain the real error
            final next = current.error;
            final msg = current.message ??
                current.details ??
                current.code ??
                current.description;
            if (msg != null &&
                msg.toString().isNotEmpty &&
                !msg
                    .toString()
                    .contains('Dart exception thrown from converted Future')) {
              bestMessage = msg.toString();
            }
            if (next == null || next == current) break;
            current = next;
          } catch (_) {
            break;
          }
        }
        message = bestMessage ?? current.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete order: $message')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _completingOrderId = '');
    }
  }

  Future<void> _completeAllOrders() async {
    final pendingOrders = _todayOrders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'pending';
    }).toList();

    if (pendingOrders.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete All Orders'),
        content: Text(
          'Are you sure you want to complete all ${pendingOrders.length} pending orders?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _completingOrderId = 'all');
    int completedCount = 0;
    int failedCount = 0;

    for (final order in pendingOrders) {
      final id = (order['id'] ?? '').toString();
      if (id.isEmpty) continue;

      try {
        await ApiService.completeOrder(id);
        completedCount++;
      } catch (e) {
        failedCount++;
      }
    }

    if (!mounted) return;
    await _loadDashboard();

    if (!mounted) return;
    if (completedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Completed $completedCount orders${failedCount > 0 ? ', $failedCount failed' : ''}. Stocks updated.',
          ),
        ),
      );
    } else if (failedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete $failedCount orders.')),
      );
    }

    setState(() => _completingOrderId = '');
  }

  Future<void> _completeAllIncompleteOrders() async {
    if (_incompleteOrders.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete All Incomplete Orders'),
        content: Text(
          'Are you sure you want to complete all ${_incompleteOrders.length} incomplete orders?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _completingOrderId = 'incomplete_all');
    int completedCount = 0;
    int failedCount = 0;

    for (final order in _incompleteOrders) {
      final id = (order['id'] ?? '').toString();
      if (id.isEmpty) continue;

      try {
        await ApiService.completeOrder(id);
        completedCount++;
      } catch (e) {
        failedCount++;
      }
    }

    if (!mounted) return;
    await _loadDashboard();

    if (!mounted) return;
    if (completedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Completed $completedCount incomplete orders${failedCount > 0 ? ', $failedCount failed' : ''}. Stocks updated.',
          ),
        ),
      );
    } else if (failedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete $failedCount orders.')),
      );
    }

    setState(() => _completingOrderId = '');
  }

  Future<void> _showEditOrderDialog(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;

    // Get current items
    final itemsRaw = order['items'] as List<dynamic>? ?? [];
    final currentItems = List<Map<String, dynamic>>.from(
      itemsRaw.where((item) => item is Map).cast<Map<String, dynamic>>(),
    );

    // Track items to void (for partial void)
    final List<Map<String, dynamic>> itemsToVoid = [];

    // Load available menu items
    List<Map<String, dynamic>> menuItems = [];
    Map<String, List<Map<String, dynamic>>> categorizedMenuItems = {};
    String selectedCategory = 'All';

    try {
      final response = await ApiService.getMenuItems();
      if (response['data'] != null) {
        final items = response['data'] as List<dynamic>;
        menuItems = items
            .where((item) => item is Map)
            .cast<Map<String, dynamic>>()
            .toList();

        // Categorize menu items
        categorizedMenuItems['All'] = menuItems;
        for (final item in menuItems) {
          final category = (item['category'] ?? 'Other').toString();
          if (!categorizedMenuItems.containsKey(category)) {
            categorizedMenuItems[category] = [];
          }
          categorizedMenuItems[category]!.add(item);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load menu: $e')),
        );
      }
      return;
    }

    // Track items to add
    final List<Map<String, dynamic>> itemsToAdd = [];
    double additionalTotal = 0.0;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final categories = categorizedMenuItems.keys.toList();
            final displayItems = selectedCategory == 'All'
                ? menuItems
                : categorizedMenuItems[selectedCategory] ?? [];

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 550,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current items section with void buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Current Items',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        // Void All button
                        TextButton.icon(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Void Entire Order'),
                                content: const Text(
                                  'Are you sure you want to void this entire order? This will restore all stock.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Void Order'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              Navigator.of(context).pop({'action': 'void_all'});
                            }
                          },
                          icon: const Icon(Icons.delete_forever,
                              size: 18, color: Colors.red),
                          label: const Text('Void All',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: currentItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          final menuItemId =
                              (item['menuItemId'] ?? '').toString();

                          // Check if already marked for voiding
                          final voidIndex = itemsToVoid.indexWhere(
                            (v) =>
                                (v['menuItemId'] ?? '').toString() ==
                                menuItemId,
                          );
                          final voidQty = voidIndex >= 0
                              ? (itemsToVoid[voidIndex]['quantity'] as num?)
                                      ?.toInt() ??
                                  0
                              : 0;
                          final remainingQty = qty - voidQty;

                          if (remainingQty <= 0) {
                            return const SizedBox.shrink();
                          }

                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$remainingQty x $name'),
                                    if (voidQty > 0)
                                      Text(
                                        '${voidQty} voided',
                                        style: TextStyle(
                                          color: Colors.red.shade400,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                  '₱${(price * remainingQty).toStringAsFixed(2)}'),
                              const SizedBox(width: 8),
                              // Void item button
                              IconButton(
                                icon: Icon(Icons.remove_circle,
                                    size: 20, color: Colors.red.shade400),
                                onPressed: () async {
                                  final voidQuantity = await showDialog<int>(
                                    context: context,
                                    builder: (context) {
                                      int qtyToVoid = remainingQty;
                                      return AlertDialog(
                                        title: Text('Void $name'),
                                        content: StatefulBuilder(
                                          builder: (context, setQtyState) {
                                            return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text('Quantity to void:'),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.remove_circle),
                                                      onPressed: qtyToVoid > 1
                                                          ? () => setQtyState(
                                                              () => qtyToVoid--)
                                                          : null,
                                                    ),
                                                    Text('$qtyToVoid',
                                                        style: const TextStyle(
                                                            fontSize: 20)),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.add_circle),
                                                      onPressed: qtyToVoid <
                                                              remainingQty
                                                          ? () => setQtyState(
                                                              () => qtyToVoid++)
                                                          : null,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(0),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.of(context)
                                                    .pop(qtyToVoid),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Void'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (voidQuantity != null &&
                                      voidQuantity > 0) {
                                    setLocalState(() {
                                      if (voidIndex >= 0) {
                                        itemsToVoid[voidIndex]['quantity'] =
                                            (itemsToVoid[voidIndex]['quantity']
                                                        as num)
                                                    .toInt() +
                                                voidQuantity;
                                      } else {
                                        itemsToVoid.add({
                                          'menuItemId': menuItemId,
                                          'name': name,
                                          'quantity': voidQuantity,
                                          'price': price,
                                        });
                                      }
                                    });
                                  }
                                },
                                tooltip: 'Void item',
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 24),

                    // Add items section with category filter
                    Row(
                      children: [
                        const Text(
                          'Add Items',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCategory,
                              isDense: true,
                              isExpanded: true,
                              hint: const Text('Category'),
                              onChanged: (value) {
                                if (value != null) {
                                  setLocalState(() {
                                    selectedCategory = value;
                                  });
                                }
                              },
                              items: categories.map((cat) {
                                return DropdownMenuItem<String>(
                                  value: cat,
                                  child: Text(cat),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: displayItems.length,
                        itemBuilder: (context, index) {
                          final item = displayItems[index];
                          final name = (item['name'] ?? 'Unknown').toString();
                          final price =
                              (item['price'] as num?)?.toDouble() ?? 0.0;
                          final itemId = (item['id'] ?? '').toString();

                          // Find if this item is already in itemsToAdd
                          final existingIndex = itemsToAdd.indexWhere(
                            (i) =>
                                (i['menuId'] ?? i['id'] ?? '').toString() ==
                                itemId,
                          );
                          final existingQty = existingIndex >= 0
                              ? (itemsToAdd[existingIndex]['quantity'] as num?)
                                      ?.toInt() ??
                                  0
                              : 0;

                          return ListTile(
                            dense: true,
                            title: Text(name),
                            subtitle: Text('₱${price.toStringAsFixed(2)}'),
                            trailing: existingQty > 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                                  ['quantity']
                                                              as num?)
                                                          ?.toInt() ??
                                                      1;
                                              if (currentQty <= 1) {
                                                itemsToAdd
                                                    .removeAt(existingIndex);
                                              } else {
                                                itemsToAdd[existingIndex]
                                                        ['quantity'] =
                                                    currentQty - 1;
                                              }
                                              additionalTotal -= price;
                                            }
                                          });
                                        },
                                      ),
                                      Text('$existingQty'),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle,
                                            size: 20),
                                        onPressed: () {
                                          setLocalState(() {
                                            if (existingIndex >= 0) {
                                              final currentQty =
                                                  (itemsToAdd[existingIndex]
                                                                  ['quantity']
                                                              as num?)
                                                          ?.toInt() ??
                                                      1;
                                              itemsToAdd[existingIndex]
                                                  ['quantity'] = currentQty + 1;
                                            }
                                            additionalTotal += price;
                                          });
                                        },
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    onPressed: () {
                                      setLocalState(() {
                                        itemsToAdd.add({
                                          'menuId': itemId,
                                          'name': name,
                                          'price': price,
                                          'quantity': 1,
                                        });
                                        additionalTotal += price;
                                      });
                                    },
                                  ),
                          );
                        },
                      ),
                    ),

                    // Show void summary if items are marked for voiding
                    if (itemsToVoid.isNotEmpty) ...[
                      const Divider(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.delete_forever,
                                    size: 16, color: Colors.red.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Items to Void:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...itemsToVoid.map((v) {
                              final name = (v['name'] ?? 'Unknown').toString();
                              final qty = (v['quantity'] as num?)?.toInt() ?? 0;
                              final price =
                                  (v['price'] as num?)?.toDouble() ?? 0.0;
                              return Text(
                                '$qty x $name (₱${(price * qty).toStringAsFixed(2)})',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.red.shade700),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],

                    // Additional total
                    if (itemsToAdd.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Additional Amount:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₱${additionalTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop({'action': 'cancel'}),
                  child: const Text('Cancel'),
                ),
                if (itemsToVoid.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop({'action': 'void_items', 'items': itemsToVoid}),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Void Selected'),
                  ),
                if (itemsToAdd.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop({'action': 'add_items', 'items': itemsToAdd}),
                    icon: const Icon(Icons.save),
                    label: const Text('Add Items'),
                  ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result['action'] == 'cancel') return;

    // Handle void all order
    if (result['action'] == 'void_all') {
      try {
        await ApiService.voidOrder(orderId, reason: 'Voided from edit dialog');
        await _loadDashboard();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Order voided successfully. Stock restored.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to void order: $e')),
        );
      }
      return;
    }

    // Handle void items
    if (result['action'] == 'void_items') {
      final itemsToVoidList = result['items'] as List<Map<String, dynamic>>;
      try {
        await ApiService.voidOrderItems(orderId, itemsToVoidList,
            reason: 'Partial void from edit dialog');
        await _loadDashboard();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Items voided successfully. Stock restored.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to void items: $e')),
        );
      }
      return;
    }

    // Handle add items
    if (result['action'] == 'add_items') {
      final items = result['items'] as List<Map<String, dynamic>>;
      try {
        await ApiService.addItemsToOrder(orderId, items);
        await _loadDashboard();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Items added to order successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add items: $e')),
        );
      }
    }
  }

  void _showAllOrdersDialog(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> orders,
    required String emptyMessage,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.receipt_long_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(title)),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 500,
            child: orders.isEmpty
                ? Center(child: Text(emptyMessage))
                : ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final id = (order['id'] ?? '').toString();
                      final total =
                          (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                      final status = (order['status'] ?? 'unknown').toString();
                      final createdAt = _asDate(order['createdAt']);

                      String dateText = 'Unknown date';
                      if (createdAt != null) {
                        final daysAgo =
                            DateTime.now().difference(createdAt).inDays;
                        dateText = daysAgo == 0
                            ? 'Today'
                            : daysAgo == 1
                                ? 'Yesterday'
                                : '$daysAgo days ago';
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        leading: const Icon(Icons.receipt_outlined),
                        title: Text(
                          id.isEmpty
                              ? 'Order'
                              : 'Order #${id.substring(0, id.length > 8 ? 8 : id.length)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('$status • $dateText'),
                        trailing: Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: (_isAdmin || _isApprovedStaff)
                            ? () {
                                Navigator.of(context).pop();
                                _showOrderDetails(order);
                              }
                            : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    // Allow both admin and approved staff to view order details
    if (!_isAdmin && !_isApprovedStaff) return;

    String formatTimestamp(dynamic value) {
      if (value == null) return '';
      if (value is Timestamp) {
        final d = value.toDate();
        final hour = d.hour;
        final minute = d.minute.toString().padLeft(2, '0');
        final amPm = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final monthNames = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
        return '${monthNames[d.month - 1]} ${d.day}, ${d.year} at $displayHour:$minute $amPm';
      }
      return value.toString();
    }

    final id = (order['id'] ?? '').toString();
    final status = (order['status'] ?? '').toString();
    final paymentMethod = (order['paymentMethod'] ?? '').toString();
    final notes = (order['notes'] ?? '').toString();
    final rejectReason = (order['rejectReason'] ?? '').toString();
    final voidReason = (order['voidReason'] ?? '').toString();
    final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = formatTimestamp(order['createdAt']);
    final completedAt = formatTimestamp(order['completedAt']);
    final voidedAt = formatTimestamp(order['voidedAt']);
    final createdByName = (order['createdByName'] ?? '').toString();

    final itemsRaw = order['items'];
    final items = itemsRaw is List ? itemsRaw : const [];

    final lastAddedRaw = order['lastAddedItems'];
    final lastAdded = lastAddedRaw is List ? lastAddedRaw : const [];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            id.isEmpty
                ? 'Order Details'
                : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Status: $status',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Total: ₱${total.toStringAsFixed(2)}'),
                  if (paymentMethod.trim().isNotEmpty)
                    Text('Payment: $paymentMethod'),
                  if (createdAt.isNotEmpty) Text('Created: $createdAt'),
                  if (createdByName.isNotEmpty)
                    Text('Created by: $createdByName'),
                  if (completedAt.isNotEmpty) Text('Completed: $completedAt'),
                  if (notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Notes: $notes'),
                  ],
                  if (rejectReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Reject reason: $rejectReason',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (voidReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Void reason: $voidReason',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (voidedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Voided: $voidedAt'),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Text(
                      'No items',
                      style: TextStyle(color: Colors.grey.shade700),
                    )
                  else
                    ...items.map((raw) {
                      final it = raw is Map ? raw : const {};
                      final name = (it['name'] ?? '').toString();
                      final qtyRaw = it['quantity'];
                      final qty = qtyRaw is num
                          ? qtyRaw.toInt()
                          : int.tryParse(qtyRaw?.toString() ?? '') ?? 0;
                      final priceRaw = it['price'];
                      final price = priceRaw is num
                          ? priceRaw.toDouble()
                          : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;
                      final lineTotal = price * qty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name.isEmpty ? 'Item' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('x$qty'),
                            const SizedBox(width: 12),
                            Text('₱${lineTotal.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    }),
                  if (lastAdded.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Newly added items',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ...lastAdded.map((raw) {
                      final it = raw is Map ? raw : const {};
                      final name = (it['name'] ?? '').toString();
                      final qtyRaw = it['quantity'];
                      final qty = qtyRaw is num
                          ? qtyRaw.toInt()
                          : int.tryParse(qtyRaw?.toString() ?? '') ?? 0;
                      final priceRaw = it['price'];
                      final price = priceRaw is num
                          ? priceRaw.toDouble()
                          : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;
                      final lineTotal = price * qty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name.isEmpty ? 'Item' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('x$qty'),
                            const SizedBox(width: 12),
                            Text('₱${lineTotal.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (status.trim().toLowerCase() == 'pending') ...[
              // Complete Order button - available for both admin and staff
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await ApiService.completeOrder(id);
                    // Play success sound
                    await SoundService.playOrderCompleted();
                    if (!mounted) return;
                    await _loadDashboard();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Order completed successfully.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to complete order: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Complete Order'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
              // Edit Order button - only for admin
              if (_isAdmin)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showEditOrderDialog(order);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Order'),
                ),
              // Void button - available for both admin and staff
              if (_isAdmin || _isApprovedStaff)
                TextButton(
                  onPressed: () async {
                    final controller = TextEditingController();
                    try {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Void Order'),
                            content: SizedBox(
                              width: 520,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'This will mark the order as voided. Stocks will not be updated.',
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      labelText: 'Reason (optional)',
                                      border: OutlineInputBorder(),
                                    ),
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Void'),
                              ),
                            ],
                          );
                        },
                      );
                      if (confirmed != true) return;
                      await ApiService.voidOrder(id, reason: controller.text);
                      if (!mounted) return;
                      await _loadDashboard();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order voided.')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to void order: $e')),
                      );
                    } finally {
                      controller.dispose();
                    }
                  },
                  child: const Text(
                    'Void',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
            if (status.trim().toLowerCase() == 'rejected')
              TextButton(
                onPressed: () async {
                  try {
                    await ApiService.restoreOrderToPending(id);
                    if (!mounted) return;
                    await _loadDashboard();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Order restored to pending.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to restore order: $e')),
                    );
                  }
                },
                child: const Text('Restore to pending'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Failed to load dashboard: $_error',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadDashboard,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildKpis(context),
                    const SizedBox(height: 16),
                    _buildQuickActions(context),
                    const SizedBox(height: 16),
                    _buildFinanceOverview(context),
                    const SizedBox(height: 16),
                    _buildNotesCard(context),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildTodayOrders(context)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildLowStock(context)),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            _buildTodayOrders(context),
                            const SizedBox(height: 16),
                            _buildLowStock(context),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_incompleteOrders.isNotEmpty) ...[
                      _buildIncompleteOrders(context),
                    ],
                  ],
                ),
    );
  }

  Widget _buildKpis(BuildContext context) {
    final today = (_summary?['today'] as Map<String, dynamic>?) ?? const {};
    final orders = (today['orders'] as num?)?.toInt() ?? 0;
    final revenue = (today['revenue'] as num?)?.toDouble() ?? 0.0;
    final menuItems = (_summary?['menuItems'] as num?)?.toInt() ?? 0;
    final lowStockCount = _lowStock.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100
            ? 4
            : width >= 760
                ? 3
                : 2;

        final isPhoneNarrow = width < 420;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 2
                ? (isPhoneNarrow ? 1.35 : 1.55)
                : crossAxisCount == 3
                    ? 2.0
                    : 2.2,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            switch (index) {
              case 0:
                return _KpiCard(
                  title: 'Today\'s Sales',
                  value: '₱${revenue.toStringAsFixed(2)}',
                  icon: Icons.payments_outlined,
                  color: Colors.blue,
                );
              case 1:
                return _KpiCard(
                  title: 'Orders Today',
                  value: orders.toString(),
                  icon: Icons.receipt_long_outlined,
                  color: Colors.indigo,
                );
              case 2:
                return _KpiCard(
                  title: 'Menu Items',
                  value: menuItems.toString(),
                  icon: Icons.restaurant_menu,
                  color: Colors.teal,
                );
              default:
                return _KpiCard(
                  title: 'Low Stock',
                  value: lowStockCount.toString(),
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                );
            }
          },
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Management',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isWide = width >= 720;

                final primary = FilledButton.icon(
                  onPressed: () => widget.onNavigate(1),
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Menu Management'),
                );

                final secondary = Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(2),
                      icon: const Icon(Icons.inventory),
                      label: const Text('Inventory'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(3),
                      icon: const Icon(Icons.analytics),
                      label: const Text('Analytics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(4),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Finance'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onNavigate(5),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Staff'),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primary),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: secondary),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: primary),
                    const SizedBox(height: 12),
                    secondary,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceOverview(BuildContext context) {
    // Calculate upcoming bills (due within 7 days and unpaid)
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));

    final upcomingPayables = _payables.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      if (status == 'paid') return false;
      final dueDate = _asDate(p['dueDate']);
      if (dueDate == null) return false;
      return dueDate.isBefore(weekFromNow) &&
          dueDate.isAfter(now.subtract(const Duration(days: 1)));
    }).toList();

    upcomingPayables.sort((a, b) {
      final ad = _asDate(a['dueDate']);
      final bd = _asDate(b['dueDate']);
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    });

    // Calculate this month's expenses
    final monthStart = DateTime(now.year, now.month, 1);
    final monthlyExpenses = _expenses.where((e) {
      final date = _asDate(e['date']) ?? _asDate(e['createdAt']);
      if (date == null) return false;
      return date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
          date.isBefore(now.add(const Duration(days: 1)));
    }).toList();

    final totalMonthlyExpenses = monthlyExpenses.fold<double>(
      0,
      (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0.0),
    );

    // Count unpaid bills
    final unpaidCount = _payables.where((p) {
      final status = (p['status'] ?? '').toString().toLowerCase();
      return status != 'paid';
    }).length;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.green),
                      const SizedBox(width: 8),
                      const Text(
                        'Finance Overview',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          upcomingPayables.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onNavigate(4),
                  child: const Text('Open Finance'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // KPI Row
            Row(
              children: [
                Expanded(
                  child: _FinanceKpiItem(
                    label: 'Monthly Expenses',
                    value: '₱${totalMonthlyExpenses.toStringAsFixed(2)}',
                    icon: Icons.trending_down,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FinanceKpiItem(
                    label: 'Unpaid Bills',
                    value: unpaidCount.toString(),
                    icon: Icons.schedule_outlined,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FinanceKpiItem(
                    label: 'Upcoming Due',
                    value: upcomingPayables.length.toString(),
                    icon: Icons.calendar_today,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Upcoming bills list
            if (upcomingPayables.isEmpty)
              Text(
                'No bills due within 7 days.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ...upcomingPayables.take(3).map((p) {
                final name = (p['name'] ?? 'Unknown').toString();
                final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                final hasAmount =
                    (p['amount'] is num) && (p['amount'] as num) > 0;
                final due = _asDate(p['dueDate']);
                final frequency = (p['frequency'] ?? '').toString();

                String dueText = 'No due date';
                if (due != null) {
                  final daysUntil = due.difference(now).inDays;
                  if (daysUntil == 0) {
                    dueText = 'Due today';
                  } else if (daysUntil == 1) {
                    dueText = 'Due tomorrow';
                  } else {
                    dueText = 'Due in $daysUntil days';
                  }
                }

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$dueText${frequency.isEmpty ? '' : ' • $frequency'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  trailing: Text(
                    hasAmount ? '₱${amount.toStringAsFixed(2)}' : 'Variable',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: hasAmount ? null : Colors.grey,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  color: Colors.amber.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                if (_notes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_notes.length} note${_notes.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showAddNoteDialog(context),
                  icon: Icon(Icons.add_circle_outline,
                      color: Colors.amber.shade600),
                  iconSize: 24,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Add note',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_notes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No notes yet',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap + to add a note',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isVeryNarrow = constraints.maxWidth < 400;
                  final isNarrow = constraints.maxWidth < 600;
                  final crossAxisCount = isVeryNarrow ? 1 : (isNarrow ? 2 : 4);

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _notes.reversed.map((note) {
                      final header = note['header']?.toString() ?? 'Untitled';
                      final body = note['body']?.toString() ?? '';
                      final createdAt = DateTime.tryParse(
                              note['createdAt']?.toString() ?? '') ??
                          DateTime.now();
                      final dateStr =
                          '${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}/${createdAt.year}';
                      final timeStr =
                          '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

                      final bodyPreview = body.length > 50
                          ? '${body.substring(0, 50)}...'
                          : body;

                      final itemWidth =
                          (constraints.maxWidth - (crossAxisCount - 1) * 8) /
                              crossAxisCount;

                      return SizedBox(
                        width: itemWidth,
                        child: InkWell(
                          onTap: () => _showEditNoteDialog(context, note),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.sticky_note_2_outlined,
                                      color: Colors.amber.shade600,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        header,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '$dateStr $timeStr',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    bodyPreview,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddNoteDialog(BuildContext context) async {
    final headerController = TextEditingController();
    final bodyController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: headerController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter note title',
                border: OutlineInputBorder(),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(
                labelText: 'Content',
                hintText: 'Enter note content',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              minLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (headerController.text.trim().isNotEmpty) {
                _addNote(
                  headerController.text.trim(),
                  bodyController.text.trim(),
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditNoteDialog(
      BuildContext context, Map<String, dynamic> note) async {
    final headerController =
        TextEditingController(text: note['header']?.toString() ?? '');
    final bodyController =
        TextEditingController(text: note['body']?.toString() ?? '');
    final noteId = note['id']?.toString() ?? '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: headerController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter note title',
                border: OutlineInputBorder(),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(
                labelText: 'Content',
                hintText: 'Enter note content',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              minLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Note?'),
                  content:
                      const Text('Are you sure you want to delete this note?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                _deleteNote(noteId);
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            label: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (headerController.text.trim().isNotEmpty) {
                _updateNote(
                  noteId,
                  headerController.text.trim(),
                  bodyController.text.trim(),
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Widget _buildIncompleteOrders(BuildContext context) {
    // Calculate pending incomplete orders count for the Complete All button
    final pendingCount = _incompleteOrders.length;
    final canCompleteAll = _isAdmin && pendingCount > 0;
    const displayLimit = 10;
    final hasMore = _incompleteOrders.length > displayLimit;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.pending_actions_outlined, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text(
                        'Incomplete Orders',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _incompleteOrders.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canCompleteAll && _completingOrderId != 'incomplete_all')
                  TextButton.icon(
                    onPressed: _completeAllIncompleteOrders,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Complete All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  )
                else if (_completingOrderId == 'incomplete_all')
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Orders from previous days that need completion:',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ..._incompleteOrders.take(displayLimit).map((order) {
              final id = (order['id'] ?? '').toString();
              final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
              final createdAt = _asDate(order['createdAt']);
              final isCompleting = _completingOrderId == id;
              final isNarrow = MediaQuery.of(context).size.width < 420;

              String dateText = 'Unknown date';
              if (createdAt != null) {
                final daysAgo = DateTime.now().difference(createdAt).inDays;
                dateText = daysAgo == 1 ? 'Yesterday' : '$daysAgo days ago';
              }

              return ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 10,
                leading:
                    const Icon(Icons.receipt_long_outlined, color: Colors.red),
                title: Text(
                  id.isEmpty
                      ? 'Order'
                      : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Created: $dateText'),
                onTap: (_isAdmin || _isApprovedStaff)
                    ? () => _showOrderDetails(order)
                    : null,
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isNarrow ? 88 : 140,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('₱${total.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 28,
                        child: isNarrow
                            ? IconButton(
                                tooltip: 'Complete',
                                onPressed: isCompleting
                                    ? null
                                    : () => _completeOrder(id),
                                icon: isCompleting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle,
                                        color: Colors.green),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  height: 28,
                                  child: ElevatedButton(
                                    onPressed: isCompleting
                                        ? null
                                        : () => _completeOrder(id),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: isCompleting
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Complete',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (hasMore) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => _showAllOrdersDialog(
                    context,
                    title: 'All Incomplete Orders',
                    orders: _incompleteOrders,
                    emptyMessage: 'No incomplete orders.',
                  ),
                  icon: const Icon(Icons.expand_more),
                  label: Text('View All (${_incompleteOrders.length})'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLowStock(BuildContext context) {
    // Separate low stock and out of stock
    final lowStockItems = _lowStock.where((item) {
      final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
      return current > 0;
    }).toList();

    final outOfStockItems = _lowStock.where((item) {
      final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
      return current <= 0;
    }).toList();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange),
                      const SizedBox(width: 8),
                      const Text(
                        'Low Stock',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          lowStockItems.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onNavigate(2),
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (lowStockItems.isEmpty && outOfStockItems.isEmpty)
              Text(
                'All good — no stock issues.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else ...[
              // Out of Stock section
              if (outOfStockItems.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Out of Stock (${outOfStockItems.length})',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...outOfStockItems.take(3).map(
                    (item) => _buildStockItemTile(item, isOutOfStock: true)),
                if (outOfStockItems.length > 3) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+${outOfStockItems.length - 3} more',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // Low Stock section
              if (lowStockItems.isNotEmpty) ...[
                if (outOfStockItems.isNotEmpty) const Divider(height: 1),
                if (outOfStockItems.isNotEmpty) const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.trending_down, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Low Stock (${lowStockItems.length})',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...lowStockItems.take(3).map(
                    (item) => _buildStockItemTile(item, isOutOfStock: false)),
                if (lowStockItems.length > 3) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+${lowStockItems.length - 3} more',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockItemTile(Map<String, dynamic> item,
      {required bool isOutOfStock}) {
    final name = (item['name'] ?? 'Unknown').toString();
    final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
    final min = (item['minStock'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap: () => _showInventoryItemDetails(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOutOfStock ? Colors.red : Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isOutOfStock
                        ? 'Out of stock'
                        : 'Current: ${current.toStringAsFixed(1)}  •  Min: ${min.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: isOutOfStock ? Colors.red : Colors.orange.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  void _showInventoryItemDetails(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'Unknown').toString();
    final current = (item['currentStock'] as num?)?.toDouble() ?? 0;
    final min = (item['minStock'] as num?)?.toDouble() ?? 0;
    final unit = (item['unit'] ?? 'units').toString();
    final category = (item['category'] ?? 'Uncategorized').toString();
    final isOutOfStock = current <= 0;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: isOutOfStock ? Colors.red : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOutOfStock
                        ? Colors.red.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOutOfStock
                          ? Colors.red.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOutOfStock
                            ? Icons.error_outline
                            : Icons.warning_amber,
                        color: isOutOfStock ? Colors.red : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOutOfStock ? 'Out of Stock' : 'Low Stock Alert',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isOutOfStock
                                    ? Colors.red
                                    : Colors.orange.shade700,
                              ),
                            ),
                            Text(
                              isOutOfStock
                                  ? 'This item needs restocking immediately'
                                  : 'Current stock is below minimum level',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Category:', category),
                _buildDetailRow(
                    'Current Stock:', '${current.toStringAsFixed(1)} $unit'),
                _buildDetailRow(
                    'Minimum Stock:', '${min.toStringAsFixed(1)} $unit'),
                if (!isOutOfStock)
                  _buildDetailRow('Shortage:',
                      '${(min - current).toStringAsFixed(1)} $unit'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigate(2); // Navigate to Inventory
              },
              icon: const Icon(Icons.inventory, size: 18),
              label: const Text('View Inventory'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayOrders(BuildContext context) {
    // Calculate pending orders count for the Complete All button
    final pendingCount = _todayOrders.where((o) {
      final status = (o['status'] ?? '').toString().trim().toLowerCase();
      return status == 'pending';
    }).length;
    final canCompleteAll = _isAdmin && pendingCount > 0;
    const displayLimit = 10;
    final hasMore = _todayOrders.length > displayLimit;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Colors.indigo),
                      const SizedBox(width: 8),
                      const Text(
                        'Today\'s Orders',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _todayOrders.length.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canCompleteAll && _completingOrderId != 'all')
                  TextButton.icon(
                    onPressed: _completeAllOrders,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Complete All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  )
                else if (_completingOrderId == 'all')
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_todayOrders.isEmpty)
              Text(
                'No orders yet today.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ..._todayOrders.take(displayLimit).map((order) {
                final id = (order['id'] ?? '').toString();
                final total = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
                final status = (order['status'] ?? 'unknown').toString();
                final statusKey = status.trim().toLowerCase();
                final canComplete = _isAdmin && statusKey == 'pending';
                final isCompleting = _completingOrderId == id;
                final isNarrow = MediaQuery.of(context).size.width < 420;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 10,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    id.isEmpty
                        ? 'Order'
                        : 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(status),
                  onTap: (_isAdmin || _isApprovedStaff)
                      ? () => _showOrderDetails(order)
                      : null,
                  trailing: canComplete
                      ? ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isNarrow ? 88 : 140,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('₱${total.toStringAsFixed(2)}'),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 28,
                                child: isNarrow
                                    ? IconButton(
                                        tooltip: 'Complete',
                                        onPressed: isCompleting
                                            ? null
                                            : () => _completeOrder(id),
                                        icon: isCompleting
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.check_circle),
                                      )
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: SizedBox(
                                          height: 28,
                                          child: ElevatedButton(
                                            onPressed: isCompleting
                                                ? null
                                                : () => _completeOrder(id),
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            child: isCompleting
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Text(
                                                    'Complete',
                                                    style:
                                                        TextStyle(fontSize: 12),
                                                  ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        )
                      : Text('₱${total.toStringAsFixed(2)}'),
                );
              }),
            if (hasMore) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => _showAllOrdersDialog(
                    context,
                    title: 'All Today\'s Orders',
                    orders: _todayOrders,
                    emptyMessage: 'No orders today.',
                  ),
                  icon: const Icon(Icons.expand_more),
                  label: Text('View All (${_todayOrders.length})'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinanceKpiItem extends StatelessWidget {
  const _FinanceKpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isPhoneNarrow = MediaQuery.of(context).size.width < 420;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isPhoneNarrow ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: isPhoneNarrow ? 36 : 40,
              height: isPhoneNarrow ? 36 : 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: isPhoneNarrow ? 20 : 24,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isPhoneNarrow ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: isPhoneNarrow ? 12 : 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CompactStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueStatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _RevenueStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.blue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(compact ? 10 : 14),
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          border: Border.all(color: chipColor.withValues(alpha: 0.3)),
          color: chipColor.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: chipColor, size: compact ? 18 : 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 13 : 14,
                color: chipColor.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StaffMealDialog extends StatefulWidget {
  const StaffMealDialog({Key? key}) : super(key: key);

  @override
  State<StaffMealDialog> createState() => _StaffMealDialogState();
}

class _StaffMealDialogState extends State<StaffMealDialog> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _menuItems = [];
  final Map<String, int> _selectedItems = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMenuItems();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadMenuItems() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getMenuItems();
      if (response['data'] != null) {
        final items = (response['data'] as List)
            .where((item) => item['isAvailable'] == true)
            .toList();
        setState(() {
          _menuItems = List<Map<String, dynamic>>.from(items);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load menu: $e')),
        );
      }
    }
  }

  void _updateQuantity(String itemId, int delta) {
    setState(() {
      final current = _selectedItems[itemId] ?? 0;
      final newQty = current + delta;
      if (newQty <= 0) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems[itemId] = newQty;
      }
    });
  }

  Future<void> _submitMealOrder() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = context.read<AuthProvider>().user;
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();

      final items = _selectedItems.entries.map((entry) {
        final menuItem = _menuItems.firstWhere((i) => i['id'] == entry.key);
        return {
          'menuId': entry.key,
          'name': menuItem['name'],
          'quantity': entry.value,
          'price': menuItem['price'] ?? 0,
        };
      }).toList();

      await ApiService.createStaffMealOrder({
        'staffId': user?.uid,
        'staffName': profile?['firstName'] != null
            ? '${profile!['firstName']} ${profile['lastName'] ?? ''}'.trim()
            : user?.email ?? 'Unknown',
        'eateryId': profile?['eateryId'] ?? '',
        'eateryName': profile?['eateryName'] ?? '',
        'items': items,
        'notes': _notesController.text.trim(),
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meal order submitted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit order: $e')),
      );
    }
  }

  double get _totalCost {
    double total = 0;
    for (final entry in _selectedItems.entries) {
      final menuItem = _menuItems.firstWhere((i) => i['id'] == entry.key);
      final price = (menuItem['price'] as num?)?.toDouble() ?? 0;
      total += price * entry.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Group menu items by category
    final categories = <String, List<Map<String, dynamic>>>{};
    for (final item in _menuItems) {
      final category = item['category'] as String? ?? 'Other';
      categories.putIfAbsent(category, () => []).add(item);
    }
    final sortedCategories = categories.keys.toList()..sort();

    return AlertDialog(
      title: const Text('Staff Meal Order'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: _isLoading && _menuItems.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sortedCategories.length,
                      itemBuilder: (context, categoryIndex) {
                        final category = sortedCategories[categoryIndex];
                        final items = categories[category]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            ...items.map((item) {
                              final itemId = item['id'] ?? '';
                              final quantity = _selectedItems[itemId] ?? 0;
                              return ListTile(
                                dense: true,
                                title: Text(item['name'] ?? 'Unknown'),
                                subtitle: Text(
                                  '₱${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          _updateQuantity(itemId, -1),
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                    ),
                                    Text('$quantity'),
                                    IconButton(
                                      onPressed: () =>
                                          _updateQuantity(itemId, 1),
                                      icon: const Icon(Icons.add_circle_outline,
                                          size: 20),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₱${_totalCost.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Any special requests?',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitMealOrder,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit Order'),
        ),
      ],
    );
  }
}

// Global search result model
class _GlobalSearchResult {
  final String id;
  final String name;
  final String type;
  final String? category;
  final String? subtitle;
  final Map<String, dynamic>? data;

  _GlobalSearchResult({
    required this.id,
    required this.name,
    required this.type,
    this.category,
    this.subtitle,
    this.data,
  });
}

// Global search dialog
class _GlobalSearchDialog extends StatefulWidget {
  final String query;

  const _GlobalSearchDialog({Key? key, required this.query}) : super(key: key);

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  List<_GlobalSearchResult> _results = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = widget.query.toLowerCase();
      final results = <_GlobalSearchResult>[];

      // Search menu items
      try {
        final menuRes = await ApiService.getMenuItems();
        final menuItems =
            List<Map<String, dynamic>>.from(menuRes['data'] ?? []);
        for (final item in menuItems) {
          final name = (item['name'] ?? '').toString();
          final category = (item['category'] ?? '').toString();
          if (name.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: (item['id'] ?? '').toString(),
              name: name,
              type: 'menu',
              category: category,
              subtitle: '₱${(item['price'] ?? 0)}',
              data: item,
            ));
          }
        }
      } catch (_) {}

      // Search inventory items
      try {
        final invRes = await ApiService.getInventoryItems();
        final invItems = List<Map<String, dynamic>>.from(invRes['data'] ?? []);
        for (final item in invItems) {
          final name = (item['name'] ?? '').toString();
          if (name.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: (item['id'] ?? '').toString(),
              name: name,
              type: 'inventory',
              subtitle: 'Stock: ${(item['currentStock'] ?? 0)}',
              data: item,
            ));
          }
        }
      } catch (_) {}

      // Search orders
      try {
        final ordersRes = await ApiService.getTodayOrders();
        final orders = List<Map<String, dynamic>>.from(ordersRes['data'] ?? []);
        for (final order in orders) {
          final id = (order['id'] ?? '').toString();
          final items = order['items'] as List<dynamic>? ?? [];
          final hasMatch = items.any((it) {
            final itemName = (it is Map ? (it['name'] ?? '').toString() : '');
            return itemName.toLowerCase().contains(query);
          });
          if (hasMatch || id.toLowerCase().contains(query)) {
            results.add(_GlobalSearchResult(
              id: id,
              name: 'Order #${id.substring(0, id.length > 6 ? 6 : id.length)}',
              type: 'order',
              subtitle:
                  '₱${(order['totalAmount'] ?? 0)} • ${(order['status'] ?? 'unknown')}',
              data: order,
            ));
          }
        }
      } catch (_) {}

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _getTypeIcon(String type) {
    switch (type) {
      case 'menu':
        return const Icon(Icons.restaurant_menu, color: Colors.teal, size: 20);
      case 'inventory':
        return const Icon(Icons.inventory_2, color: Colors.blue, size: 20);
      case 'order':
        return const Icon(Icons.receipt_long, color: Colors.indigo, size: 20);
      default:
        return const Icon(Icons.search, size: 20);
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'menu':
        return 'Menu';
      case 'inventory':
        return 'Inventory';
      case 'order':
        return 'Order';
      default:
        return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'menu':
        return Colors.teal;
      case 'inventory':
        return Colors.blue;
      case 'order':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.search),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search: "${widget.query}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 48),
                        const SizedBox(height: 12),
                        Text('Error: $_error'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _performSearch,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                color: Colors.grey.shade400, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No results found for "${widget.query}"',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            leading: _getTypeIcon(result.type),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    result.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getTypeColor(result.type)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _getTypeColor(result.type)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _getTypeLabel(result.type),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _getTypeColor(result.type),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: result.subtitle != null
                                ? Text(
                                    result.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(context).pop([result]);
                            },
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
