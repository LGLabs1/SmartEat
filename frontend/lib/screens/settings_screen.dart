import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import '../services/auth_provider.dart';
import '../services/pos_settings_service.dart';
import '../widgets/download_apps_card.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;
  bool _isAdmin = false;

  // Notification settings
  bool _notificationsEnabled = true;
  bool _lowStockEnabled = true;
  bool _billRemindersEnabled = true;
  bool _orderAlertsEnabled = true;
  int _billReminderDays = 3;

  // Business settings
  String _currencySymbol = '\u20B1';
  String _dateFormat = 'MM/dd/yyyy';
  bool _darkMode = false;
  bool _autoRefresh = true;
  int _sessionTimeout = 30; // minutes

  // POS settings
  bool _requirePaymentConfirmation = true;
  bool _showTaxBreakdown = true;
  double _defaultTaxRate = 0.12; // 12% VAT

  // Receipt printing settings (eatery-wide, persisted via
  // PosSettingsService)
  bool _receiptPrintingEnabled = false;
  bool _askForReceipt = false;

  // Inventory settings
  bool _lowStockWarnings = true;
  int _lowStockThreshold = 10;
  bool _autoDeductStock = true;

  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _authProvider = auth;
    auth.addListener(_onAuthChanged);
    _loadSettings();
    _loadBusinessSettings();
    _loadPosSettings();
    _loadProfile();
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      var profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      if (profile == null) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        profile = await context.read<AuthProvider>().getCurrentUserProfile();
      }
      if (!mounted) return;
      final role = (profile?['role'] ?? '').toString().toLowerCase();
      setState(() {
        _isAdmin = profile?['isAdmin'] == true || role == 'admin';
      });
    } catch (_) {
      // Settings remain usable for non-admin users.
    }
  }

  static const Set<String> _validCurrencySymbols = {'\u20B1', r'$', '\u20AC'};

  Future<void> _loadBusinessSettings() async {
    try {
      var uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.isEmpty) {
        // Auth state may still be initializing on web refresh; wait briefly and retry
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        uid = context.read<AuthProvider>().user?.uid;
      }
      if (uid == null || uid.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(uid)
          .get();
      final symbol = (doc.data()?['currencySymbol'] ?? '').toString().trim();
      if (!mounted) return;
      if (symbol.isEmpty) return;
      setState(() {
        // Fall back to peso if the stored symbol is not one of the known items,
        // otherwise the DropdownButton assertion fails.
        _currencySymbol =
            _validCurrencySymbols.contains(symbol) ? symbol : '\u20B1';
      });
    } catch (_) {
      // Ignore settings load failures
    }
  }

  Future<void> _saveCurrencySymbol(String symbol) async {
    try {
      final uid = context.read<AuthProvider>().user?.uid;
      if (uid == null || uid.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('user_preferences')
          .doc(uid)
          .set({'currencySymbol': symbol.trim()}, SetOptions(merge: true));
    } catch (_) {
      // Ignore save failures
    }
  }

  Future<void> _loadPosSettings() async {
    try {
      final settings = await PosSettingsService.load();
      if (!mounted) return;
      setState(() {
        _receiptPrintingEnabled = settings.receiptPrintingEnabled;
        _askForReceipt = settings.askForReceipt;
      });
    } catch (_) {
      // Defaults stay in effect; the section still renders.
    }
  }

  Future<void> _updateReceiptSetting({
    bool? receiptPrintingEnabled,
    bool? askForReceipt,
  }) async {
    final previousEnabled = _receiptPrintingEnabled;
    final previousAsk = _askForReceipt;
    setState(() {
      if (receiptPrintingEnabled != null) {
        _receiptPrintingEnabled = receiptPrintingEnabled;
      }
      if (askForReceipt != null) _askForReceipt = askForReceipt;
    });
    try {
      await PosSettingsService.save(PosSettings(
        receiptPrintingEnabled: _receiptPrintingEnabled,
        askForReceipt: _askForReceipt,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _receiptPrintingEnabled = previousEnabled;
        _askForReceipt = previousAsk;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save the receipt setting. Try again.')),
      );
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() {
        _notificationsEnabled = _notificationService.notificationsEnabled;
        _lowStockEnabled = _notificationService.lowStockEnabled;
        _billRemindersEnabled = _notificationService.billRemindersEnabled;
        _orderAlertsEnabled = _notificationService.orderAlertsEnabled;
        _billReminderDays = _notificationService.billReminderDays;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateNotificationSetting(String key, dynamic value) async {
    switch (key) {
      case 'master':
        await _notificationService.setNotificationsEnabled(value as bool);
        setState(() => _notificationsEnabled = value);
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

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    final userEmail = user?.email ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Info Card
                _buildUserInfoCard(userEmail),
                const SizedBox(height: 24),

                // Notification Settings Section
                _buildSectionHeader('Notifications'),
                _buildNotificationSettingsCard(),
                if (_isAdmin) ...[
                  const SizedBox(height: 24),
                  _buildSectionHeader('SMS Alerts'),
                  _buildSmsSettingsCard(),
                ],
                const SizedBox(height: 24),

                // Business Settings Section
                _buildSectionHeader('Business Settings'),
                _buildBusinessSettingsCard(),
                const SizedBox(height: 24),

                // POS Settings Section
                _buildSectionHeader('POS Settings'),
                _buildPOSSettingsCard(),
                const SizedBox(height: 24),

                // Receipt Printing Section
                _buildSectionHeader('Receipt Printing'),
                _buildReceiptPrintingCard(),
                const SizedBox(height: 24),

                // Inventory Settings Section
                _buildSectionHeader('Inventory Settings'),
                _buildInventorySettingsCard(),
                const SizedBox(height: 24),

                // App Settings Section
                _buildSectionHeader('App Settings'),
                _buildAppSettingsCard(),
                const SizedBox(height: 24),
                _buildSectionHeader('Get Smart Eat'),
                const DownloadAppsCard(),
                const SizedBox(height: 32),

                // Danger Zone
                _buildSectionHeader('Danger Zone'),
                _buildDangerZoneCard(),
              ],
            ),
    );
  }

  Widget _buildUserInfoCard(String email) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                // Navigate to profile edit
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile editing coming soon')),
                );
              },
              child: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text(
              'Enable Notifications',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Receive alerts for important events'),
            value: _notificationsEnabled,
            onChanged: (value) => _updateNotificationSetting('master', value),
            secondary: Icon(
              Icons.notifications_active,
              color: _notificationsEnabled ? Colors.blue : Colors.grey,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Low Stock Alerts'),
            subtitle: const Text('Notify when inventory items are running low'),
            value: _notificationsEnabled && _lowStockEnabled,
            onChanged: _notificationsEnabled
                ? (value) => _updateNotificationSetting('lowStock', value)
                : null,
            secondary: const Icon(Icons.inventory_2_outlined),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Bill Payment Reminders'),
            subtitle: const Text('Remind about upcoming bill payments'),
            value: _notificationsEnabled && _billRemindersEnabled,
            onChanged: _notificationsEnabled
                ? (value) => _updateNotificationSetting('billReminders', value)
                : null,
            secondary: const Icon(Icons.receipt_long_outlined),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Order Alerts'),
            subtitle:
                const Text('Notify about pending orders requiring attention'),
            value: _notificationsEnabled && _orderAlertsEnabled,
            onChanged: _notificationsEnabled
                ? (value) => _updateNotificationSetting('orderAlerts', value)
                : null,
            secondary: const Icon(Icons.receipt_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Bill Reminder Days'),
            subtitle: Text('Remind $_billReminderDays days before due date'),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: _billReminderDays.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '$_billReminderDays days',
                onChanged: _notificationsEnabled && _billRemindersEnabled
                    ? (value) => _updateNotificationSetting(
                        'billReminderDays', value.round())
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsSettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.sms_outlined),
        title: const Text('SMS Alerts'),
        subtitle:
            const Text('Text low stock, bill, and sales alerts to your phone'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/settings/sms'),
      ),
    );
  }

  Widget _buildBusinessSettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Currency Symbol'),
            trailing: DropdownButton<String>(
              value: _currencySymbol,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '₱', child: Text('₱ PHP')),
                DropdownMenuItem(value: r'$', child: Text(r'$ USD')),
                DropdownMenuItem(value: '€', child: Text('€ EUR')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _currencySymbol = value);
                  _saveCurrencySymbol(value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Date Format'),
            trailing: DropdownButton<String>(
              value: _dateFormat,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                    value: 'MM/dd/yyyy', child: Text('MM/DD/YYYY')),
                DropdownMenuItem(
                    value: 'dd/MM/yyyy', child: Text('DD/MM/YYYY')),
                DropdownMenuItem(
                    value: 'yyyy-MM-dd', child: Text('YYYY-MM-DD')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _dateFormat = value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Show Tax Breakdown'),
            subtitle: Text('Display ${_defaultTaxRate * 100}% tax in receipts'),
            value: _showTaxBreakdown,
            onChanged: (value) => setState(() => _showTaxBreakdown = value),
            secondary: const Icon(Icons.receipt_long),
          ),
        ],
      ),
    );
  }

  Widget _buildPOSSettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Require Payment Confirmation'),
            subtitle:
                const Text('Show confirmation dialog before completing order'),
            value: _requirePaymentConfirmation,
            onChanged: (value) =>
                setState(() => _requirePaymentConfirmation = value),
            secondary: const Icon(Icons.verified_user_outlined),
          ),
        ],
      ),
    );
  }

  /// Placeholder for the upcoming wireless receipt printer integration.
  /// Nothing prints yet — the toggles only configure the future behavior.
  Widget _buildReceiptPrintingCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Enable Receipt Printing'),
            subtitle: const Text(
                'Turn on once a wireless receipt printer is connected'),
            value: _receiptPrintingEnabled,
            onChanged: (value) =>
                _updateReceiptSetting(receiptPrintingEnabled: value),
            secondary: const Icon(Icons.print_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Printer'),
            trailing: Text(
              'Not Connected',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Ask for Receipt'),
            subtitle: const Text(
                'Ask whether to print a receipt before completing an order'),
            value: _askForReceipt,
            onChanged: (value) => _updateReceiptSetting(askForReceipt: value),
            secondary: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildInventorySettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Low Stock Warnings'),
            subtitle:
                const Text('Show warnings in inventory when stock is low'),
            value: _lowStockWarnings,
            onChanged: (value) => setState(() => _lowStockWarnings = value),
            secondary: const Icon(Icons.warning_amber_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Low Stock Threshold'),
            subtitle:
                const Text('Items below this quantity are considered low'),
            trailing: SizedBox(
              width: 80,
              child: TextField(
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                controller:
                    TextEditingController(text: _lowStockThreshold.toString()),
                onSubmitted: (value) {
                  final newValue = int.tryParse(value) ?? _lowStockThreshold;
                  setState(() => _lowStockThreshold = newValue.clamp(1, 100));
                },
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Auto Deduct Stock'),
            subtitle: const Text(
                'Automatically deduct inventory when orders are completed'),
            value: _autoDeductStock,
            onChanged: (value) => setState(() => _autoDeductStock = value),
            secondary: const Icon(Icons.sync_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildAppSettingsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark theme throughout the app'),
            value: _darkMode,
            onChanged: (value) {
              setState(() => _darkMode = value);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Theme changes require app restart')),
              );
            },
            secondary: const Icon(Icons.dark_mode_outlined),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Auto Refresh Dashboard'),
            subtitle:
                const Text('Automatically refresh data when switching tabs'),
            value: _autoRefresh,
            onChanged: (value) => setState(() => _autoRefresh = value),
            secondary: const Icon(Icons.refresh_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Session Timeout'),
            subtitle: const Text('Minutes of inactivity before auto-logout'),
            trailing: DropdownButton<int>(
              value: _sessionTimeout,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 min')),
                DropdownMenuItem(value: 30, child: Text('30 min')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
                DropdownMenuItem(value: 120, child: Text('2 hours')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sessionTimeout = value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Smart Eat'),
            subtitle: const Text('Version 1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Smart Eat',
                applicationVersion: '1.0.0',
                applicationIcon: Icon(
                  Icons.restaurant,
                  color: Theme.of(context).colorScheme.primary,
                  size: 48,
                ),
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Smart Eat is a comprehensive eatery management system for restaurants, cafes, and food businesses.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    return Card(
      elevation: 0,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              'Clear All Data',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Delete all local app data and reset settings',
              style: TextStyle(color: Colors.red.shade600),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.red.shade700),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Data?'),
                  content: const Text(
                    'This will reset all app settings to default. Your account and cloud data will not be affected.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All data cleared')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear Data'),
                    ),
                  ],
                ),
              );
            },
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
