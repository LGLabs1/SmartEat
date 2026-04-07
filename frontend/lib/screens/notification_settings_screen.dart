import 'package:flutter/material.dart';
import '../services/notification_service.dart';

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
  bool _masterEnabled = true;
  bool _lowStockEnabled = true;
  bool _billRemindersEnabled = true;
  bool _orderAlertsEnabled = true;
  int _billReminderDays = 3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    // Small delay to ensure values are loaded
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() {
        _masterEnabled = _notificationService.notificationsEnabled;
        _lowStockEnabled = _notificationService.lowStockEnabled;
        _billRemindersEnabled = _notificationService.billRemindersEnabled;
        _orderAlertsEnabled = _notificationService.orderAlertsEnabled;
        _billReminderDays = _notificationService.billReminderDays;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
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
      case 'billReminderDays':
        await _notificationService.setBillReminderDays(value as int);
        setState(() => _billReminderDays = value);
        break;
    }
  }

  Future<void> _testNotification(String type) async {
    final notificationService = NotificationService();

    switch (type) {
      case 'low_stock':
        await notificationService.showNotification(
          title: 'Test: Low Stock Alert',
          body: 'Whole Chicken is low on stock (2kg remaining)',
          payload: 'test_low_stock',
        );
        break;
      case 'bill':
        await notificationService.showNotification(
          title: 'Test: Upcoming Bill',
          body: 'Electricity bill is due in 2 days (₱2,500.00)',
          payload: 'test_bill',
        );
        break;
      case 'order':
        await notificationService.showNotification(
          title: 'Test: Pending Order',
          body: 'You have 3 pending orders awaiting action',
          payload: 'test_order',
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
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('Notification Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Master switch
                _buildSectionHeader('General'),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Enable Notifications',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Receive alerts for important events',
                    ),
                    value: _masterEnabled,
                    onChanged: (value) => _updateSetting('master', value),
                    secondary: Icon(
                      Icons.notifications_active,
                      color: _masterEnabled ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Notification categories
                _buildSectionHeader('Notification Types'),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Low Stock Alerts'),
                        subtitle: const Text(
                          'Notify when inventory items are running low',
                        ),
                        value: _masterEnabled && _lowStockEnabled,
                        onChanged: _masterEnabled
                            ? (value) => _updateSetting('lowStock', value)
                            : null,
                        secondary: const Icon(Icons.inventory_2_outlined),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Bill Payment Reminders'),
                        subtitle: const Text(
                          'Remind about upcoming bill payments',
                        ),
                        value: _masterEnabled && _billRemindersEnabled,
                        onChanged: _masterEnabled
                            ? (value) => _updateSetting('billReminders', value)
                            : null,
                        secondary: const Icon(Icons.receipt_long_outlined),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Order Alerts'),
                        subtitle: const Text(
                          'Notify about pending orders requiring attention',
                        ),
                        value: _masterEnabled && _orderAlertsEnabled,
                        onChanged: _masterEnabled
                            ? (value) => _updateSetting('orderAlerts', value)
                            : null,
                        secondary: const Icon(Icons.receipt_outlined),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Bill reminder settings
                _buildSectionHeader('Bill Reminder Settings'),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Remind me before due date:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _billReminderDays.toDouble(),
                                min: 1,
                                max: 7,
                                divisions: 6,
                                label: '$_billReminderDays days',
                                onChanged: _masterEnabled && _billRemindersEnabled
                                    ? (value) => setState(
                                        () => _billReminderDays = value.round(),
                                      )
                                    : null,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$_billReminderDays days',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Test notifications
                _buildSectionHeader('Test Notifications'),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('Test Low Stock Alert'),
                        trailing: const Icon(Icons.send, color: Colors.blue),
                        onTap: _masterEnabled
                            ? () => _testNotification('low_stock')
                            : null,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: const Text('Test Bill Reminder'),
                        trailing: const Icon(Icons.send, color: Colors.blue),
                        onTap: _masterEnabled
                            ? () => _testNotification('bill')
                            : null,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.receipt_outlined),
                        title: const Text('Test Order Alert'),
                        trailing: const Icon(Icons.send, color: Colors.blue),
                        onTap: _masterEnabled
                            ? () => _testNotification('order')
                            : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // FCM Token info (for debugging)
                if (_notificationService.fcmToken != null)
                  Card(
                    elevation: 0,
                    color: Colors.grey.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ExpansionTile(
                      title: const Text(
                        'Device Token (Advanced)',
                        style: TextStyle(fontSize: 14),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _notificationService.fcmToken!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
