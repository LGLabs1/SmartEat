import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/smart_eat_header.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _masterEnabled = true;
  bool _lowStockEnabled = true;
  bool _billRemindersEnabled = true;
  bool _orderAlertsEnabled = true;
  bool _attendanceRemindersEnabled = true;
  int _billReminderDays = 3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    if (FirebaseAuth.instance.currentUser == null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _notificationService.loadPreferences(force: true);
    if (!mounted) return;
    setState(() {
      _masterEnabled = _notificationService.notificationsEnabled;
      _lowStockEnabled = _notificationService.lowStockEnabled;
      _billRemindersEnabled = _notificationService.billRemindersEnabled;
      _orderAlertsEnabled = _notificationService.orderAlertsEnabled;
      _attendanceRemindersEnabled =
          _notificationService.attendanceRemindersEnabled;
      _billReminderDays = _notificationService.billReminderDays;
      _isLoading = false;
    });
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    setState(() => _isSaving = true);
    try {
      switch (key) {
        case 'master':
          await _notificationService.setNotificationsEnabled(value as bool);
          setState(() => _masterEnabled = value);
          break;
        case 'lowStock':
          await _notificationService.setLowStockEnabled(value as bool);
          setState(() => _lowStockEnabled = value);
          break;
        case 'billReminders':
          await _notificationService.setBillRemindersEnabled(value as bool);
          setState(() => _billRemindersEnabled = value);
          break;
        case 'orderAlerts':
          await _notificationService.setOrderAlertsEnabled(value as bool);
          setState(() => _orderAlertsEnabled = value);
          break;
        case 'attendanceReminders':
          await _notificationService
              .setAttendanceRemindersEnabled(value as bool);
          setState(() => _attendanceRemindersEnabled = value);
          break;
        case 'billReminderDays':
          await _notificationService.setBillReminderDays(value as int);
          setState(() => _billReminderDays = value);
          break;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save preferences.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testNotification(String type) async {
    switch (type) {
      case 'low_stock':
        await _notificationService.showNotification(
          title: 'Test: Low Stock Alert',
          body: 'Whole Chicken is low on stock (2kg remaining)',
          payload: 'test_low_stock',
          type: 'low_stock',
          source: 'inventory',
          audience: 'admin',
          dedupeKey: 'test_low_stock_${DateTime.now().millisecondsSinceEpoch}',
        );
        break;
      case 'bill':
        await _notificationService.showNotification(
          title: 'Test: Upcoming Bill',
          body: 'Electricity bill is due in 2 days (\u20B1,500.00)',
          payload: 'test_bill',
          type: 'bill_due_soon',
          source: 'payable',
          audience: 'admin',
          dedupeKey: 'test_bill_${DateTime.now().millisecondsSinceEpoch}',
        );
        break;
      case 'order':
        await _notificationService.showNotification(
          title: 'Test: Pending Order',
          body: 'You have 3 pending orders awaiting action',
          payload: 'test_order',
          type: 'order',
          source: 'orders',
          audience: 'all',
          dedupeKey: 'test_order_${DateTime.now().millisecondsSinceEpoch}',
        );
        break;
      case 'attendance':
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        await _notificationService.showNotification(
          title: 'Test: Attendance Reminder',
          body: 'Your shift is about to start. Remember to Time In.',
          payload: 'test_attendance',
          type: 'attendance',
          source: 'attendance',
          audience: 'staff',
          targetUids: uid.isEmpty ? const <String>[] : <String>[uid],
          dedupeKey: 'test_attendance_${DateTime.now().millisecondsSinceEpoch}',
        );
        break;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test $type notification sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: SmartEatHeader(
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: const Text('Notification Settings'),
          actions: [
            const SageHeaderButton(),
            IconButton(
              tooltip: 'Reload preferences',
              onPressed: _isLoading ? null : _loadSettings,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.pagePadding,
                      8,
                      AppTheme.pagePadding,
                      32,
                    ),
                    children: [
                      _buildIntroCard(scheme),
                      const SizedBox(height: 20),
                      _buildSectionHeader('General'),
                      _buildCard([
                        _buildToggle(
                          icon: Icons.notifications_active_outlined,
                          title: 'Enable Notifications',
                          subtitle: 'Receive alerts for important events',
                          value: _masterEnabled,
                          onChanged: (value) => _updateSetting('master', value),
                          color: AppTheme.sageAccent,
                        ),
                      ]),
                      const SizedBox(height: 20),
                      _buildSectionHeader('Notification Types'),
                      _buildCard([
                        _buildToggle(
                          icon: Icons.inventory_2_outlined,
                          title: 'Low Stock Alerts',
                          subtitle:
                              'Notify when inventory items are running low',
                          value: _masterEnabled && _lowStockEnabled,
                          onChanged: _masterEnabled
                              ? (value) => _updateSetting('lowStock', value)
                              : null,
                          color: AppTheme.warning,
                        ),
                        _buildDivider(scheme),
                        _buildToggle(
                          icon: Icons.receipt_long_outlined,
                          title: 'Bill Payment Reminders',
                          subtitle: 'Remind about upcoming bill payments',
                          value: _masterEnabled && _billRemindersEnabled,
                          onChanged: _masterEnabled
                              ? (value) =>
                                  _updateSetting('billReminders', value)
                              : null,
                          color: AppTheme.sageBlue,
                        ),
                        _buildDivider(scheme),
                        _buildToggle(
                          icon: Icons.receipt_outlined,
                          title: 'Order Alerts',
                          subtitle:
                              'Notify about pending orders requiring attention',
                          value: _masterEnabled && _orderAlertsEnabled,
                          onChanged: _masterEnabled
                              ? (value) => _updateSetting('orderAlerts', value)
                              : null,
                          color: AppTheme.sageSuccess,
                        ),
                        _buildDivider(scheme),
                        _buildToggle(
                          icon: Icons.access_time,
                          title: 'Attendance Reminders',
                          subtitle:
                              'Remind staff to time in at shift start and time out after a full shift',
                          value: _attendanceRemindersEnabled,
                          onChanged: (value) =>
                              _updateSetting('attendanceReminders', value),
                          color: AppTheme.sageCyan,
                        ),
                      ]),
                      const SizedBox(height: 20),
                      _buildSectionHeader('Bill Reminder Settings'),
                      _buildCard([
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Remind me before due date',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _billReminderDays.toDouble(),
                                      min: 1,
                                      max: 7,
                                      divisions: 6,
                                      label: '$_billReminderDays days',
                                      activeColor: AppTheme.sageAccent,
                                      inactiveColor:
                                          scheme.outline.withValues(alpha: 0.4),
                                      onChanged: _masterEnabled &&
                                              _billRemindersEnabled
                                          ? (value) => _updateSetting(
                                              'billReminderDays', value.round())
                                          : null,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.sageAccent
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$_billReminderDays days',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.sageAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      _buildSectionHeader('Test Notifications'),
                      _buildCard([
                        _buildTestTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'Test Low Stock Alert',
                          onTap: _masterEnabled
                              ? () => _testNotification('low_stock')
                              : null,
                          color: AppTheme.warning,
                        ),
                        _buildDivider(scheme),
                        _buildTestTile(
                          icon: Icons.receipt_long_outlined,
                          title: 'Test Bill Reminder',
                          onTap: _masterEnabled
                              ? () => _testNotification('bill')
                              : null,
                          color: AppTheme.sageBlue,
                        ),
                        _buildDivider(scheme),
                        _buildTestTile(
                          icon: Icons.receipt_outlined,
                          title: 'Test Order Alert',
                          onTap: _masterEnabled
                              ? () => _testNotification('order')
                              : null,
                          color: AppTheme.sageSuccess,
                        ),
                        _buildDivider(scheme),
                        _buildTestTile(
                          icon: Icons.access_time,
                          title: 'Test Attendance Reminder',
                          onTap: _masterEnabled
                              ? () => _testNotification('attendance')
                              : null,
                          color: AppTheme.sageCyan,
                        ),
                      ]),
                      if (_notificationService.fcmToken != null) ...[
                        const SizedBox(height: 20),
                        _buildSectionHeader('Advanced'),
                        _buildCard([
                          ExpansionTile(
                            iconColor: AppTheme.sageAccent,
                            collapsedIconColor:
                                scheme.onSurface.withValues(alpha: 0.6),
                            title: const Text(
                              'Device Token',
                              style: TextStyle(fontSize: 14),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText(
                                  _notificationService.fcmToken!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ],
                    ],
                  ),
                  if (_isSaving)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppTheme.sageAccent,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildIntroCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.sageGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.notification_important_outlined,
                color: scheme.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay in the loop',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which alerts reach your device and the in-app feed.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(ColorScheme scheme) {
    return Divider(
      height: 1,
      color: scheme.outline.withValues(alpha: 0.18),
    );
  }

  Widget _buildToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required Color color,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildTestTile({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      trailing: Icon(Icons.send, color: scheme.primary, size: 18),
      onTap: onTap,
    );
  }
}
