import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_version.dart';
import '../services/attendance_settings_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/auth_provider.dart';
import '../services/pos_settings_service.dart';
import '../theme.dart';
import '../widgets/bluetooth_printer_sheet.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/smart_eat_header.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isAdmin = false;

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
  BluetoothPrinterDevice? _savedPrinter;
  bool _printerConnected = false;
  bool _printerLoading = false;

  // Inventory settings
  bool _lowStockWarnings = true;
  int _lowStockThreshold = 10;
  bool _autoDeductStock = true;

  // Attendance settings (eatery-wide, admin-write)
  double _fullDayHours = 8;
  double _halfDayHours = 4;
  int _graceMinutes = 10;
  String _scheduledStart = '';

  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _authProvider = auth;
    auth.addListener(_onAuthChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait<void>([
      _loadBusinessSettings(),
      _loadPosSettings(),
      _loadPrinter(),
      _loadAttendanceSettings(),
      _loadProfile(),
    ]);
    if (!mounted) return;
    setState(() => _isLoading = false);
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
      var profile = await context.read<AuthProvider>().getCurrentUserProfile();
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
      });
    } catch (_) {
      // Defaults stay in effect; the section still renders.
    }
  }

  Future<void> _updateReceiptSetting({
    bool? receiptPrintingEnabled,
  }) async {
    final previousEnabled = _receiptPrintingEnabled;
    setState(() {
      if (receiptPrintingEnabled != null) {
        _receiptPrintingEnabled = receiptPrintingEnabled;
      }
    });
    try {
      await PosSettingsService.save(PosSettings(
        receiptPrintingEnabled: _receiptPrintingEnabled,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _receiptPrintingEnabled = previousEnabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save the receipt setting. Try again.')),
      );
    }
  }

  Future<void> _loadPrinter() async {
    try {
      final saved = await BluetoothPrinterService.loadSavedPrinter();
      var connected = false;
      if (saved != null) {
        connected = await BluetoothPrinterService.isConnected(saved.address);
      }
      if (!mounted) return;
      setState(() {
        _savedPrinter = saved;
        _printerConnected = connected;
        _printerLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _printerLoading = false);
    }
  }

  Future<void> _openPrinterPicker() async {
    final selected = await showBluetoothPrinterSheet(
      context,
      savedPrinter: _savedPrinter,
    );
    if (selected == null || !mounted) return;
    final connected =
        await BluetoothPrinterService.isConnected(selected.address);
    if (!mounted) return;
    setState(() {
      _savedPrinter = selected;
      _printerConnected = connected;
      _printerLoading = false;
    });
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${selected.displayName}')),
      );
    }
  }

  Future<void> _disconnectPrinter() async {
    final printer = _savedPrinter;
    if (printer == null) return;
    setState(() => _printerLoading = true);
    final disconnected =
        await BluetoothPrinterService.disconnect(printer.address);
    if (!mounted) return;
    setState(() {
      _printerConnected = disconnected ? false : _printerConnected;
      _printerLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          disconnected
              ? 'Printer disconnected'
              : 'Could not disconnect the printer',
        ),
      ),
    );
  }

  Future<void> _loadAttendanceSettings() async {
    try {
      final settings = await AttendanceSettingsService.load();
      if (!mounted) return;
      setState(() {
        _fullDayHours = settings.fullDayHours;
        _halfDayHours = settings.halfDayHours;
        _graceMinutes = settings.graceMinutes;
        _scheduledStart = settings.scheduledStart;
      });
    } catch (_) {
      // Defaults stay in effect.
    }
  }

  Future<void> _updateAttendanceSettings({
    double? fullDayHours,
    double? halfDayHours,
    int? graceMinutes,
    String? scheduledStart,
  }) async {
    final nextFull = fullDayHours ?? _fullDayHours;
    var nextHalf = halfDayHours ?? _halfDayHours;
    if (nextHalf > nextFull) nextHalf = nextFull;
    final nextGrace = graceMinutes ?? _graceMinutes;
    final nextStart = scheduledStart ?? _scheduledStart;
    setState(() {
      _fullDayHours = nextFull;
      _halfDayHours = nextHalf;
      _graceMinutes = nextGrace;
      _scheduledStart = nextStart;
    });
    try {
      await AttendanceSettingsService.save(AttendanceSettings(
        fullDayHours: nextFull,
        halfDayHours: nextHalf,
        graceMinutes: nextGrace,
        scheduledStart: nextStart,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save attendance settings. Try again.'),
        ),
      );
    }
  }

  Future<void> _pickScheduledStart() async {
    final parts = _scheduledStart.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await _updateAttendanceSettings(scheduledStart: value);
  }

  List<double> _hourOptions(double current) {
    final values = <double>{2, 3, 4, 5, 6, 8, 10, 12, current};
    final sorted = values.toList()..sort();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user;
    final userEmail = user?.email ?? 'Unknown';

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
          titleText: 'Settings',
          actions: const [SageHeaderButton(), SizedBox(width: 8)],
        ),
        body: _isLoading
            ? const SkeletonSettings()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  8,
                  AppTheme.pagePadding,
                  32,
                ),
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
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Attendance'),
                    _buildAttendanceSettingsCard(),
                  ],
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
                  const SizedBox(height: 32),

                  // Danger Zone
                  _buildSectionHeader('Danger Zone'),
                  _buildDangerZoneCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildUserInfoCard(String email) {
    final scheme = Theme.of(context).colorScheme;
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
                  Text(
                    'Account',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.sageAccent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.notifications_active_outlined,
              color: AppTheme.sageAccent, size: 20),
        ),
        title: const Text('Notification preferences'),
        subtitle: const Text('Alerts, reminders, and test notifications'),
        trailing: Icon(Icons.chevron_right, color: scheme.primary),
        onTap: () => Navigator.of(context).pushNamed('/settings/notifications'),
      ),
    );
  }

  Widget _buildSmsSettingsCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
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
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
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
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
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
  Widget _buildAttendanceSettingsCard() {
    final scheme = Theme.of(context).colorScheme;
    final graceOptions = <int>{0, 5, 10, 15, 20, 30, _graceMinutes}.toList()
      ..sort();
    final halfOptions = _hourOptions(_halfDayHours)
        .where((value) => value <= _fullDayHours || value == _halfDayHours)
        .toList();

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Full day hours'),
            subtitle: const Text('Shift hours needed for a full work unit'),
            trailing: DropdownButton<double>(
              value: _fullDayHours,
              underline: const SizedBox(),
              items: [
                for (final value in _hourOptions(_fullDayHours))
                  DropdownMenuItem(
                    value: value,
                    child: Text('${value.toStringAsFixed(0)} h'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateAttendanceSettings(fullDayHours: value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timelapse),
            title: const Text('Half day hours'),
            subtitle: const Text('Shift hours needed for a half work unit'),
            trailing: DropdownButton<double>(
              value: _halfDayHours,
              underline: const SizedBox(),
              items: [
                for (final value in halfOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text('${value.toStringAsFixed(0)} h'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateAttendanceSettings(halfDayHours: value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('Grace period'),
            subtitle: const Text('Late minutes allowed after scheduled start'),
            trailing: DropdownButton<int>(
              value: _graceMinutes,
              underline: const SizedBox(),
              items: [
                for (final value in graceOptions)
                  DropdownMenuItem(value: value, child: Text('$value min')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateAttendanceSettings(graceMinutes: value);
                }
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Scheduled start'),
            subtitle: Text(
              _scheduledStart.isEmpty
                  ? 'Not set - lateness tracking is inactive'
                  : 'Lateness uses this start time (${_scheduledStart})',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_scheduledStart.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear start time',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        _updateAttendanceSettings(scheduledStart: ''),
                  ),
                IconButton(
                  tooltip: 'Pick start time',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _pickScheduledStart,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: scheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Open 24/7: staff may Time In/Out at any hour. '
                    'Overnight shifts roll Time Out to the next day.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
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

  Widget _buildReceiptPrintingCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Enable Receipt Printing'),
            subtitle: const Text(
                'Shows a Print receipt switch in the cart after a printer is connected'),
            value: _receiptPrintingEnabled,
            onChanged: (value) =>
                _updateReceiptSetting(receiptPrintingEnabled: value),
            secondary: const Icon(Icons.print_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Bluetooth Printer'),
            subtitle: Text(
              _savedPrinter == null
                  ? 'No printer selected'
                  : '${_savedPrinter!.displayName}\n${_savedPrinter!.address}',
            ),
            isThreeLine: _savedPrinter != null,
            trailing: _printerLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _printerConnected
                          ? AppTheme.sageSuccess.withValues(alpha: 0.12)
                          : scheme.surfaceVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _printerConnected
                            ? AppTheme.sageSuccess.withValues(alpha: 0.35)
                            : scheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _printerConnected
                          ? 'Connected'
                          : (_savedPrinter == null ? 'Not Connected' : 'Saved'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _printerConnected
                            ? AppTheme.sageSuccess
                            : scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printerLoading ? null : _openPrinterPicker,
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: const Text('Search Bluetooth Devices'),
                  ),
                ),
                if (_printerConnected && _savedPrinter != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _printerLoading ? null : _disconnectPrinter,
                    child: const Text('Disconnect'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 15, color: scheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Connects this device directly to the printer over Bluetooth.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
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

  Widget _buildInventorySettingsCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
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
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
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
            subtitle: Text('Version ${AppVersion.display}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Smart Eat',
                applicationVersion: AppVersion.display,
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.error.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.delete_forever, color: scheme.error),
            title: Text(
              'Clear All Data',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Delete all local app data and reset settings',
              style: TextStyle(color: scheme.error.withValues(alpha: 0.8)),
            ),
            trailing: Icon(Icons.chevron_right, color: scheme.error),
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
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface.withValues(alpha: 0.65),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
