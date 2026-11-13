import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/sms_settings_service.dart';

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;

  String? _eateryId;
  String? _uid;
  String? _error;
  SmsSettings _settings = const SmsSettings();
  SmsAdminContact? _contact;
  SmsLogEntry? _latestLog;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    var uid = auth.user?.uid;
    if ((uid == null || uid.isEmpty)) {
      // Auth state may still be initializing on web refresh; wait briefly and retry
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      final authRetry = context.read<AuthProvider>();
      uid = authRetry.user?.uid;
    }
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'You must be signed in to manage SMS alerts.';
      });
      return;
    }

    try {
      final profile = await auth.getCurrentUserProfile();
      final role = (profile?['role'] ?? '').toString().toLowerCase();
      final isAdmin = profile?['isAdmin'] == true || role == 'admin';
      final eateryId = (profile?['eateryId'] ?? '').toString().trim();

      if (!isAdmin) {
        setState(() {
          _isLoading = false;
          _error = 'Only an admin can manage SMS alerts.';
        });
        return;
      }

      if (eateryId.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'Your profile is not linked to an eatery.';
        });
        return;
      }

      final settings = await SmsSettingsService.loadSettings(eateryId);
      final contact = await SmsSettingsService.loadAdminContact(eateryId);

      SmsLogEntry? latestLog;
      try {
        latestLog = await SmsSettingsService.loadLatestLog(eateryId);
      } catch (_) {
        latestLog = null;
      }

      if (!mounted) return;
      setState(() {
        _uid = uid;
        _eateryId = eateryId;
        _settings = settings;
        _contact = contact;
        _latestLog = latestLog;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _update(SmsSettings next) {
    setState(() => _settings = next);
  }

  Future<void> _save() async {
    final eateryId = _eateryId;
    final uid = _uid;
    if (eateryId == null || uid == null) return;

    setState(() => _isSaving = true);
    try {
      await SmsSettingsService.saveSettings(
        eateryId: eateryId,
        uid: uid,
        settings: _settings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendTest() async {
    setState(() => _isTesting = true);
    try {
      await SmsSettingsService.sendTestSms(_eateryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test SMS sent to the admin number')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Test failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
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
        title: const Text('SMS Alerts'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildRecipientCard(),
                    const SizedBox(height: 16),
                    _buildMasterCard(),
                    const SizedBox(height: 16),
                    _buildAlertsCard(),
                    const SizedBox(height: 16),
                    _buildTestCard(),
                    const SizedBox(height: 24),
                    _buildSaveButton(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sms_failed_outlined,
                size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientCard() {
    final contact = _contact;
    final masked = contact?.maskedPhone ?? 'Not set';
    final hasPhone = contact?.hasPhone ?? false;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          hasPhone ? Icons.phone_android : Icons.phone_disabled,
          color: hasPhone ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        title: const Text('Alert recipient'),
        subtitle: Text(
          hasPhone
              ? '$masked (admin profile)'
              : 'Add a mobile number to your admin profile first',
        ),
      ),
    );
  }

  Widget _buildMasterCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: SwitchListTile(
        title: const Text(
          'Enable SMS Alerts',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Send text alerts to the admin mobile number'),
        value: _settings.enabled,
        onChanged: (value) => _update(_settings.copyWith(enabled: value)),
        secondary: Icon(
          Icons.sms_outlined,
          color: _settings.enabled ? Colors.blue : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildAlertsCard() {
    final enabled = _settings.enabled;

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
            title: const Text('Low Stock Alerts'),
            subtitle:
                const Text('Text when an item crosses its low stock level'),
            value: _settings.lowStockEnabled,
            onChanged: enabled
                ? (value) => _update(_settings.copyWith(lowStockEnabled: value))
                : null,
            secondary: const Icon(Icons.inventory_2_outlined),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Bill Reminders'),
            subtitle: const Text('Reminder for bills due soon (checked on app open)'),
            value: _settings.billRemindersEnabled,
            onChanged: enabled
                ? (value) =>
                    _update(_settings.copyWith(billRemindersEnabled: value))
                : null,
            secondary: const Icon(Icons.receipt_long_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Bill Reminder Days'),
            subtitle: Text(
              'Remind up to ${_settings.billReminderDays} '
              'day${_settings.billReminderDays == 1 ? '' : 's'} before due',
            ),
            enabled: enabled && _settings.billRemindersEnabled,
            trailing: SizedBox(
              width: 130,
              child: Slider(
                value: _settings.billReminderDays.toDouble(),
                min: 1,
                max: 14,
                divisions: 13,
                label: '${_settings.billReminderDays} days',
                onChanged: enabled && _settings.billRemindersEnabled
                    ? (value) => _update(
                          _settings.copyWith(billReminderDays: value.round()),
                        )
                    : null,
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Daily Sales Summary'),
            subtitle: const Text('Daily summary (sent on app open)'),
            value: _settings.dailySummaryEnabled,
            onChanged: enabled
                ? (value) =>
                    _update(_settings.copyWith(dailySummaryEnabled: value))
                : null,
            secondary: const Icon(Icons.insights_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard() {
    final log = _latestLog;
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
            leading: const Icon(Icons.outgoing_mail),
            title: const Text('Send Test SMS'),
            subtitle: const Text('Send a one-off message to verify delivery'),
            trailing: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            onTap: _isTesting ? null : _sendTest,
          ),
          if (log != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                log.status == 'sent'
                    ? Icons.check_circle_outline
                    : log.status == 'failed'
                        ? Icons.error_outline
                        : Icons.hourglass_empty,
                color: log.status == 'sent'
                    ? Colors.green
                    : log.status == 'failed'
                        ? Colors.red
                        : Colors.orange,
              ),
              title: Text('Last ${log.type.replaceAll('_', ' ')}'),
              subtitle: Text(
                log.status == 'failed' && (log.error?.isNotEmpty ?? false)
                    ? log.error!
                    : 'Status: ${log.status}'
                        '${log.createdAt != null ? ' • ${_formatTime(log.createdAt!)}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
