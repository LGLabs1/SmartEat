import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/staff/data/staff_service.dart';
import '../features/staff/widgets/staff_attendance_calendar.dart';
import '../services/attendance_settings_service.dart';
import '../services/auth_provider.dart';
import '../services/firebase_service.dart';
import '../services/notification_badge_provider.dart';
import '../theme.dart';
import '../utils/attendance_utils.dart';
import '../utils/phone_utils.dart';
import '../utils/staff_utils.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/smart_eat_header.dart';
import 'staff_management_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key, this.onOpenTeamAttendance}) : super(key: key);

  final VoidCallback? onOpenTeamAttendance;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _eateryData;
  AttendanceSettings _settings = const AttendanceSettings();

  bool _isLoading = true;
  bool _isLoadingAttendance = false;
  bool _isRecording = false;
  String? _loadError;

  List<Map<String, dynamic>> _attendanceRecords = [];
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _openShift;
  DateTime _selectedMonth = DateTime.now();

  Timer? _clockTimer;
  final ValueNotifier<int> _clockTick = ValueNotifier<int>(0);

  Stream<QuerySnapshot<Map<String, dynamic>>>? _teamUsersStream;
  String _teamUsersStreamKey = '';
  Stream<QuerySnapshot<Map<String, dynamic>>>? _teamAttendanceStream;
  String _teamAttendanceStreamKey = '';

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _positionController = TextEditingController();

  bool get _isAdmin => _profile != null && isAdminUser(_profile!);

  String get _eateryId => (_profile?['eateryId'] ?? '').toString().trim();

  String get _uid =>
      (_profile?['uid'] ?? _profile?['id'] ?? '').toString().trim();

  User? get _authUser =>
      context.read<AuthProvider>().user ?? FirebaseAuth.instance.currentUser;

  String get _effectiveUid {
    if (_uid.isNotEmpty) return _uid;
    return _authUser?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _clockTick.value++;
    });
    _loadProfile();
    context.read<NotificationBadgeProvider>().refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isAdmin) {
      _loadAttendance();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _clockTick.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final authUser = authProvider.user ?? FirebaseAuth.instance.currentUser;
      var profile = await authProvider.getCurrentUserProfile();
      if (profile == null && authUser != null) {
        profile = await FirebaseService.getUserProfile(authUser.uid);
      }

      final profileWithUid = profile != null
          ? {...profile, 'uid': authUser?.uid ?? profile['uid'] ?? ''}
          : null;

      if (!mounted) return;
      setState(() {
        _profile = profileWithUid;
        _isLoading = false;
        _updateControllers();
      });

      final eateryId = (profileWithUid?['eateryId'] ?? '').toString().trim();
      Map<String, dynamic>? eateryData;
      if (eateryId.isNotEmpty) {
        try {
          eateryData = await FirebaseService.getEatery(eateryId);
        } catch (_) {
          eateryData = null;
        }
      }

      final settings = eateryId.isEmpty
          ? const AttendanceSettings()
          : await AttendanceSettingsService.loadForEatery(
              eateryId,
              forceRefresh: true,
            );

      if (!mounted) return;
      setState(() {
        _eateryData = eateryData;
        _settings = settings;
      });

      if (!isAdminUser(profileWithUid ?? const {})) {
        await _loadAttendance();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load profile. Pull down to retry.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    }
  }

  void _updateControllers() {
    var firstName = _profile?['firstName']?.toString().trim() ?? '';
    var lastName = _profile?['lastName']?.toString().trim() ?? '';
    if (firstName.isEmpty && lastName.isEmpty) {
      final storedName = _humanizeDisplayName(
        (_profile?['name'] ?? _profile?['displayName'] ?? '').toString(),
      );
      if (storedName.isNotEmpty) {
        final parts = storedName
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
        firstName = parts.isEmpty ? '' : parts.first;
        lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }
    _firstNameController.text = firstName;
    _lastNameController.text = lastName;
    _phoneController.text = PhoneUtils.formatPhMobile(_profilePhone(_profile));
    _positionController.text = _profile?['position']?.toString() ?? '';
  }

  String _profilePhone(Map<String, dynamic>? profile) {
    final phone = (profile?['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return (profile?['phoneNumber'] ?? '').toString().trim();
  }

  Future<void> _loadAttendance() async {
    final eateryId = _eateryId;
    final uid = _effectiveUid;
    if (eateryId.isEmpty || uid.isEmpty) {
      if (mounted) setState(() => _isLoadingAttendance = false);
      return;
    }

    setState(() => _isLoadingAttendance = true);

    var records = <Map<String, dynamic>>[];
    try {
      records = await FirebaseService.getStaffAttendanceForMonth(
        eateryId: eateryId,
        uid: uid,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );
    } catch (_) {
      records = [];
    }

    Map<String, dynamic>? today;
    try {
      today = await FirebaseService.getTodayAttendance(
        eateryId: eateryId,
        uid: uid,
      );
    } catch (_) {
      today = null;
    }

    Map<String, dynamic>? open;
    if (today != null && attendanceIsOpen(today)) {
      open = today;
    } else {
      try {
        open = await StaffService.findOpenShift(
          eateryId: eateryId,
          uid: uid,
        );
      } catch (_) {
        open = null;
      }
    }

    if (!mounted) return;
    setState(() {
      _attendanceRecords = records;
      _todayAttendance = today;
      _openShift = open;
      _isLoadingAttendance = false;
    });
  }

  Future<bool> _saveProfileValues({
    required String firstName,
    required String lastName,
    required String phone,
    required String position,
  }) async {
    final uid = _authUser?.uid;
    if (uid == null) return false;

    final rawPhone = phone.trim();
    final normalizedPhone =
        rawPhone.isEmpty ? '' : PhoneUtils.normalizePhMobile(rawPhone);
    if (rawPhone.isNotEmpty && normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid mobile number')),
      );
      return false;
    }

    try {
      final role = _profile?['role']?.toString() ?? 'staff';
      final fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
      final updateData = <String, dynamic>{
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'name': fullName,
        'phone': normalizedPhone ?? '',
        'phoneNumber': normalizedPhone ?? '',
        'position': position.trim(),
      };

      if (role == 'admin' && _eateryId.isNotEmpty) {
        await FirebaseService.updateAdminProfileInEatery(
          _eateryId,
          uid,
          updateData,
        );
      }
      await FirebaseService.updateUser(uid, updateData);
      if (fullName.isNotEmpty) {
        await _authUser?.updateDisplayName(fullName);
      }

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      await _loadProfile();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
      return false;
    }
  }

  Future<void> _openEditSheet() async {
    final first = TextEditingController(text: _firstNameController.text);
    final last = TextEditingController(text: _lastNameController.text);
    final phone = TextEditingController(text: _phoneController.text);
    final position = TextEditingController(text: _positionController.text);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        var saving = false;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit_outlined),
                        const SizedBox(width: 8),
                        Text(
                          'Edit profile',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: first,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: last,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '+63 xxx xxx xxxx',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: position,
                      decoration: const InputDecoration(
                        labelText: 'Position',
                        prefixIcon: Icon(Icons.work_outline),
                        hintText: 'e.g. Cashier, Cook, Manager',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    setLocal(() => saving = true);
                                    final ok = await _saveProfileValues(
                                      firstName: first.text,
                                      lastName: last.text,
                                      phone: phone.text,
                                      position: position.text,
                                    );
                                    if (!sheetContext.mounted) return;
                                    if (ok) {
                                      Navigator.of(sheetContext).pop();
                                    } else {
                                      setLocal(() => saving = false);
                                    }
                                  },
                            icon: saving
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.check, size: 18),
                            label: Text(saving ? 'Saving...' : 'Save changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    first.dispose();
    last.dispose();
    phone.dispose();
    position.dispose();
  }

  Future<void> _recordTimeIn() async {
    if (_isRecording) return;
    final eateryId = _eateryId;
    final uid = _effectiveUid;
    if (eateryId.isEmpty || uid.isEmpty) {
      _showClockError(
        'Your profile is not linked to an eatery yet. Ask your admin to approve or re-add your account.',
      );
      return;
    }
    setState(() => _isRecording = true);
    try {
      final updated = await StaffService.clockIn(
        eateryId: eateryId,
        uid: uid,
        settings: _settings,
      );
      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _openShift = updated;
        _isRecording = false;
      });
      await _loadAttendance();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Time In recorded. Have a great shift!'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _recordTimeOut() async {
    if (_isRecording) return;
    final eateryId = _eateryId;
    final uid = _effectiveUid;
    if (eateryId.isEmpty || uid.isEmpty) {
      _showClockError(
        'Your profile is not linked to an eatery yet. Ask your admin to approve or re-add your account.',
      );
      return;
    }

    final active = _openShift;
    if (active == null) {
      _showClockError('No open shift found. Tap Time In to start.');
      return;
    }
    final duration = attendanceOpenShiftDuration(active['timeIn']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End this shift?'),
        content: Text(
          'You have been on shift for ${formatAttendanceDuration(duration)}. '
          'Time Out will be recorded now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Time Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRecording = true);
    try {
      final updated = await StaffService.clockOut(
        eateryId: eateryId,
        uid: uid,
        settings: _settings,
      );
      if (!mounted) return;
      setState(() {
        _todayAttendance = updated;
        _openShift = null;
        _isRecording = false;
      });
      await _loadAttendance();
      if (!mounted) return;
      final status = attendanceRecordStatus(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Time Out recorded. ${attendanceStatusLabel(status)} logged.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _showClockError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  Future<void> _changePassword() async {
    final email = _email == 'No email' ? '' : _email;
    if (email.isEmpty) return;
    try {
      await FirebaseService.sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send reset email: $e')),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  String get _fullName {
    final first = _profile?['firstName']?.toString().trim() ?? '';
    final last = _profile?['lastName']?.toString().trim() ?? '';
    final combined = _humanizeDisplayName('$first $last');
    if (combined.isNotEmpty) return combined;

    final storedName = _humanizeDisplayName(
      (_profile?['name'] ?? _profile?['displayName'] ?? '').toString(),
    );
    if (storedName.isNotEmpty) return storedName;

    final authUser = _authUser;
    final authName = _humanizeDisplayName(authUser?.displayName ?? '');
    if (authName.isNotEmpty) return authName;

    final email = (_profile?['email'] ?? authUser?.email ?? '').toString();
    final emailName = _humanizeDisplayName(email);
    return emailName.isEmpty ? 'No name' : emailName;
  }

  String _humanizeDisplayName(String value) {
    var name = value.trim();
    if (name.isEmpty) return '';
    if (name.contains('@')) {
      name = name.split('@').first;
    }
    if (name.isEmpty) return '';
    final uniformCase =
        name == name.toLowerCase() || name == name.toUpperCase();
    if (uniformCase &&
        !name.contains(' ') &&
        (name.contains('.') || name.contains('_') || name.contains('-'))) {
      final parts = name
          .split(RegExp(r'[._-]+'))
          .where((part) => part.isNotEmpty)
          .map((part) {
        final lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      });
      return parts.join(' ');
    }
    return name;
  }

  DateTime? get _accountCreatedAt {
    final fromProfile = attendanceAsDateTime(_profile?['createdAt']);
    if (fromProfile != null) return fromProfile;
    return _authUser?.metadata.creationTime;
  }

  String get _email {
    final storedEmail = _profile?['email']?.toString().trim() ?? '';
    if (storedEmail.isNotEmpty) return storedEmail;
    final authEmail = _authUser?.email?.trim() ?? '';
    return authEmail.isEmpty ? 'No email' : authEmail;
  }

  String get _roleDisplay {
    final role = _profile?['role']?.toString() ?? 'staff';
    if (_isAdmin || role == 'admin') return 'Administrator';
    return 'Staff Member';
  }

  String _initials() => staffInitials(_fullName);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: SmartEatHeader(
          titleText: 'Profile',
          showBackButton: true,
          actions: [
            const SageHeaderButton(),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: _loadProfile,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppTheme.contentMaxWidth,
                        ),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppTheme.pagePadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeaderCard(),
                              const SizedBox(height: 16),
                              if (_eateryId.isEmpty) ...[
                                _buildEateryNotLinkedState(),
                                const SizedBox(height: 16),
                              ] else if (_isAdmin) ...[
                                _buildAdminMonitorCard(),
                                const SizedBox(height: 16),
                              ] else ...[
                                ValueListenableBuilder<int>(
                                  valueListenable: _clockTick,
                                  builder: (context, _, __) =>
                                      _buildShiftClockCard(),
                                ),
                                const SizedBox(height: 16),
                                StaffAttendanceCalendar(
                                  records: _attendanceRecords,
                                  selectedMonth: _selectedMonth,
                                  isLoading: _isLoadingAttendance,
                                  openShift: _openShift,
                                  onMonthChanged: (month) {
                                    setState(() => _selectedMonth = month);
                                    _loadAttendance();
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              _buildPersonalInfoCard(),
                              const SizedBox(height: 16),
                              _buildEateryCard(),
                              const SizedBox(height: 16),
                              _buildActionsCard(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Something went wrong',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEateryNotLinkedState() {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Eatery not connected yet',
      subtitle: "We're finishing your setup",
      icon: Icons.link_off_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storefront_outlined,
              size: 42, color: scheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            "Your account isn't linked to an eatery yet.",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'If you just created an eatery, refresh in a moment. If you joined a team, ask your team owner to approve your account.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final scheme = Theme.of(context).colorScheme;
    final summary = attendanceMonthSummary(_attendanceRecords);

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.sageGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.onPrimary.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(
                          icon: _isAdmin
                              ? Icons.admin_panel_settings_outlined
                              : Icons.badge_outlined,
                          label: _roleDisplay,
                        ),
                        if ((_profile?['position'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          _Pill(
                            icon: Icons.work_outline,
                            label: _profile!['position'].toString().trim(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _email,
                      style: TextStyle(
                        color: scheme.onPrimary.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: _openEditSheet,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.18),
                  foregroundColor: scheme.onPrimary,
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if (!_isAdmin) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    label: 'Full days',
                    value: '${summary.present}',
                  ),
                ),
                Expanded(
                  child: _HeaderStat(
                    label: 'Half days',
                    value: '${summary.half}',
                  ),
                ),
                Expanded(
                  child: _HeaderStat(
                    label: 'Hours',
                    value: formatAttendanceHours(summary.hours),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftClockCard() {
    final scheme = Theme.of(context).colorScheme;
    final active = _openShift;
    final onShift = active != null && attendanceIsOpen(active);
    final today = _todayAttendance;
    final completedToday = today != null &&
        today['timeOut'] != null &&
        today['timeOut'] != active?['timeOut'];
    final encodedNoShift = today != null &&
        today['timeIn'] == null &&
        today['timeOut'] == null &&
        (today['workUnit'] is num || today['present'] == true);
    final needsReview = today?['needsReview'] == true ||
        attendanceRecordStatus(today ?? const {}) == attendanceIncomplete;

    final shiftStart =
        active != null ? attendanceAsDateTime(active['timeIn']) : null;
    final liveDuration =
        onShift ? attendanceOpenShiftDuration(active['timeIn']) : Duration.zero;
    final completedDuration = today != null
        ? attendanceShiftDuration(today['timeIn'], today['timeOut'])
        : null;
    final target = Duration(
      minutes: (_settings.fullDayHours * 60).round(),
    );
    final progress = target.inMinutes <= 0
        ? 0.0
        : (onShift
                ? liveDuration.inMinutes / target.inMinutes
                : (completedDuration?.inMinutes ?? 0) / target.inMinutes)
            .clamp(0.0, 1.0)
            .toDouble();

    String headline;
    String subline;
    if (onShift) {
      headline = 'On shift';
      subline = shiftStart == null
          ? 'Shift in progress'
          : 'Started ${formatAttendanceClock(shiftStart)}';
    } else if (encodedNoShift) {
      headline = 'Encoded by admin';
      subline = attendanceStatusLabel(attendanceRecordStatus(today));
    } else if (completedToday) {
      headline = 'Shift complete';
      subline = completedDuration == null
          ? 'Time out recorded'
          : formatAttendanceDuration(completedDuration);
    } else {
      headline = 'Not on shift';
      subline = _settings.scheduledStart.isEmpty
          ? 'Tap Time In when you start'
          : 'Scheduled start ${_settings.scheduledStart}';
    }

    return _SectionCard(
      title: 'Shift clock',
      subtitle: _settings.scheduledStart.isEmpty
          ? 'Flexible schedule - open 24/7'
          : 'Scheduled start ${_settings.scheduledStart}',
      icon: Icons.timer_outlined,
      trailing: _StatusChip(
        label: onShift
            ? 'Live'
            : completedToday
                ? 'Done'
                : needsReview
                    ? 'Review'
                    : 'Idle',
        color: onShift
            ? scheme.primary
            : completedToday
                ? AppTheme.success
                : needsReview
                    ? AppTheme.warning
                    : scheme.outline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subline,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                    ),
                  ],
                ),
              ),
              if (onShift)
                Text(
                  formatAttendanceDuration(liveDuration),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                )
              else if (completedDuration != null)
                Text(
                  formatAttendanceDuration(completedDuration),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.success,
                  ),
                ),
            ],
          ),
          if (active?['late'] == true) ...[
            const SizedBox(height: 10),
            _StatusChip(
              label: 'Late ${active!['lateMinutes'] ?? 0}m',
              color: AppTheme.warning,
              icon: Icons.schedule,
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatAttendanceDuration(onShift ? liveDuration : (completedDuration ?? Duration.zero))} of ${formatAttendanceHours(_settings.fullDayHours)} for a full day',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _isRecording || completedToday || encodedNoShift
                ? null
                : (onShift ? _recordTimeOut : _recordTimeIn),
            icon: _isRecording
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : Icon(onShift ? Icons.logout : Icons.login),
            label: Text(
              completedToday
                  ? 'Shift complete'
                  : onShift
                      ? 'Time Out'
                      : 'Time In',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: onShift ? AppTheme.error : scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
          ),
          if (needsReview) ...[
            const SizedBox(height: 12),
            _InlineNotice(
              icon: Icons.rate_review_outlined,
              color: AppTheme.warning,
              message:
                  'This shift needs admin review. Ask your admin to fix the missing Time Out.',
            ),
          ],
          if (encodedNoShift) ...[
            const SizedBox(height: 12),
            _InlineNotice(
              icon: Icons.verified_outlined,
              color: scheme.primary,
              message: 'Attendance for today was encoded by an admin.',
            ),
          ],
          const SizedBox(height: 16),
          _CheckpointRow(
            label: 'Time In',
            value: today != null
                ? formatAttendanceClock(today['timeIn'])
                : formatAttendanceClock(active?['timeIn']),
            done: (today?['timeIn'] ?? active?['timeIn']) != null,
          ),
          const SizedBox(height: 8),
          _CheckpointRow(
            label: 'Time Out',
            value: formatAttendanceClock(today?['timeOut']),
            done: today?['timeOut'] != null,
          ),
          if (attendanceLegacySummary(today ?? const {}).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              attendanceLegacySummary(today!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case attendancePresent:
        return AppTheme.success;
      case attendanceHalfDay:
      case attendanceIncomplete:
        return AppTheme.warning;
      case attendanceInProgress:
        return AppTheme.primary;
      case attendanceShort:
      case attendanceAbsent:
      default:
        return AppTheme.error;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _teamUsersFor(String eateryId) {
    if (_teamUsersStream == null || _teamUsersStreamKey != eateryId) {
      _teamUsersStreamKey = eateryId;
      _teamUsersStream = StaffService.usersStream(eateryId);
    }
    return _teamUsersStream!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _teamAttendanceFor(
    String eateryId,
    String startKey,
    String endKey,
  ) {
    final key = '$eateryId|$startKey|$endKey';
    if (_teamAttendanceStream == null || _teamAttendanceStreamKey != key) {
      _teamAttendanceStreamKey = key;
      _teamAttendanceStream = StaffService.recentAttendanceStream(
        eateryId,
        startKey: startKey,
        endKey: endKey,
      );
    }
    return _teamAttendanceStream!;
  }

  Widget _buildAdminMonitorCard() {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayKey = attendanceYmd(today);
    final startKey = attendanceYmd(today.subtract(const Duration(days: 2)));

    if (_eateryId.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Team attendance',
      subtitle: 'Live shift monitor',
      icon: Icons.groups_outlined,
      trailing: IconButton(
        tooltip: 'Open attendance',
        onPressed: () {
          final callback = widget.onOpenTeamAttendance;
          if (callback != null) {
            callback();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const StaffManagementScreen(initialTabIndex: 1),
            ),
          );
        },
        icon: const Icon(Icons.open_in_new, size: 20),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _teamAttendanceFor(_eateryId, startKey, todayKey),
        builder: (context, attSnap) {
          if (attSnap.hasError) {
            return Text(
              'Failed to load attendance: ${attSnap.error}',
              style: TextStyle(color: scheme.error),
            );
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _teamUsersFor(_eateryId),
            builder: (context, userSnap) {
              if (userSnap.hasError) {
                return Text(
                  'Failed to load staff: ${userSnap.error}',
                  style: TextStyle(color: scheme.error),
                );
              }
              if (!attSnap.hasData || !userSnap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final staff = <String, Map<String, dynamic>>{};
              for (final doc in userSnap.data!.docs) {
                final data = doc.data();
                if (!isAdminUser(data)) staff[doc.id] = data;
              }

              final records =
                  attSnap.data!.docs.map((doc) => doc.data()).toList();
              final todayRecords = records
                  .where((r) => (r['date'] ?? '').toString() == todayKey)
                  .toList();
              final openRecords = records.where(attendanceIsOpen).toList();
              final summary = attendanceTeamSummary(
                staffUids: staff.keys,
                todayRecords: todayRecords,
                openRecords: openRecords,
                todayKey: todayKey,
              );

              final todayByUid = <String, Map<String, dynamic>>{};
              for (final record in todayRecords) {
                final uid = (record['uid'] ?? '').toString().trim();
                if (uid.isNotEmpty) todayByUid[uid] = record;
              }
              final openByUid = <String, Map<String, dynamic>>{};
              for (final record in openRecords) {
                final uid = (record['uid'] ?? '').toString().trim();
                if (uid.isNotEmpty) openByUid[uid] = record;
              }

              final uids = staff.keys.toList()
                ..sort((a, b) {
                  final aOpen = openByUid.containsKey(a) ? 0 : 1;
                  final bOpen = openByUid.containsKey(b) ? 0 : 1;
                  if (aOpen != bOpen) return aOpen - bOpen;
                  return staffDisplayName(staff[a]!, a).toLowerCase().compareTo(
                        staffDisplayName(staff[b]!, b).toLowerCase(),
                      );
                });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MonitorStat(
                          label: 'On shift',
                          value: '${summary.onShift}',
                          color: AppTheme.primary,
                        ),
                      ),
                      Expanded(
                        child: _MonitorStat(
                          label: 'Completed',
                          value: '${summary.completed}',
                          color: AppTheme.success,
                        ),
                      ),
                      Expanded(
                        child: _MonitorStat(
                          label: 'Review',
                          value: '${summary.needsReview}',
                          color: AppTheme.warning,
                        ),
                      ),
                      Expanded(
                        child: _MonitorStat(
                          label: 'No record',
                          value: '${summary.missing}',
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (uids.isEmpty)
                    Text(
                      'No staff accounts yet.',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    )
                  else
                    ...uids.take(6).map((uid) {
                      final data = staff[uid]!;
                      final open = openByUid[uid];
                      final record = todayByUid[uid];
                      final name = staffDisplayName(data, uid);
                      String status;
                      Color color;
                      if (open != null) {
                        status =
                            'On shift since ${formatAttendanceClock(open['timeIn'])}';
                        color = AppTheme.primary;
                      } else if (record?['needsReview'] == true ||
                          attendanceRecordStatus(record ?? const {}) ==
                              attendanceIncomplete) {
                        status = 'Needs review';
                        color = AppTheme.warning;
                      } else if (record?['timeOut'] != null) {
                        final duration = attendanceShiftDuration(
                          record!['timeIn'],
                          record['timeOut'],
                        );
                        status = duration == null
                            ? 'Shift completed'
                            : 'Completed ${formatAttendanceDuration(duration)}';
                        color = AppTheme.success;
                      } else if (record != null) {
                        status = attendanceStatusLabel(
                          attendanceRecordStatus(record),
                        );
                        color = _statusColor(attendanceRecordStatus(record));
                      } else {
                        status = 'No record today';
                        color = scheme.onSurface.withValues(alpha: 0.5);
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: color.withValues(alpha: 0.12),
                              child: Text(
                                staffInitials(name),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (summary.missing > 0 || summary.needsReview > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Tip: open Staff > Attendance to encode or fix records.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    final phone = _profilePhone(_profile);
    return _SectionCard(
      title: 'Personal information',
      icon: Icons.person_outline,
      trailing: IconButton(
        tooltip: 'Edit profile',
        onPressed: _openEditSheet,
        icon: const Icon(Icons.edit_outlined, size: 20),
      ),
      child: Column(
        children: [
          _InfoTile(
            icon: Icons.person_outline,
            label: 'Name',
            value: _fullName,
          ),
          _InfoTile(
            icon: Icons.mail_outline,
            label: 'Email',
            value: _email,
          ),
          _InfoTile(
            icon: Icons.phone_outlined,
            label: 'Mobile number',
            value: phone.isEmpty ? 'Not set' : PhoneUtils.formatPhMobile(phone),
          ),
          _InfoTile(
            icon: Icons.work_outline,
            label: 'Position',
            value: (_profile?['position'] ?? '').toString().trim().isEmpty
                ? 'Not set'
                : _profile!['position'].toString().trim(),
          ),
          _InfoTile(
            icon: Icons.event_available_outlined,
            label: 'Account created',
            value: _formatDate(_accountCreatedAt),
          ),
        ],
      ),
    );
  }

  Widget _buildEateryCard() {
    if (_eateryData == null) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Eatery',
      icon: Icons.storefront_outlined,
      child: Column(
        children: [
          _InfoTile(
            icon: Icons.store,
            label: 'Name',
            value: (_eateryData?['name'] ?? '').toString().trim().isEmpty
                ? 'Unknown'
                : _eateryData!['name'].toString(),
          ),
          _InfoTile(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: (_eateryData?['address'] ?? '').toString().trim().isEmpty
                ? 'Not set'
                : _eateryData!['address'].toString(),
          ),
          _InfoTile(
            icon: Icons.calendar_today_outlined,
            label: 'Established',
            value: _formatDate(_eateryData?['createdAt']),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            subtitle: const Text('Send a reset link to your email'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePassword,
          ),
          Divider(
            height: 1,
            color: scheme.outline.withValues(alpha: 0.25),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/settings'),
          ),
          Divider(
            height: 1,
            color: scheme.outline.withValues(alpha: 0.25),
          ),
          ListTile(
            leading: context.watch<NotificationBadgeProvider>().unreadCount > 0
                ? Badge(
                    label: Text(
                      context.watch<NotificationBadgeProvider>().unreadCount >
                              99
                          ? '99+'
                          : '${context.watch<NotificationBadgeProvider>().unreadCount}',
                    ),
                    backgroundColor: AppTheme.error,
                    child: const Icon(Icons.notifications_outlined),
                  )
                : const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/notifications'),
          ),
          Divider(
            height: 1,
            color: scheme.outline.withValues(alpha: 0.25),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Notification settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).pushNamed('/settings/notifications'),
          ),
          Divider(
            height: 1,
            color: scheme.outline.withValues(alpha: 0.25),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.error),
            title: const Text(
              'Logout',
              style: TextStyle(color: AppTheme.error),
            ),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    final date = attendanceAsDateTime(timestamp);
    if (date == null) return 'Unknown';
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onPrimary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorStat extends StatelessWidget {
  const _MonitorStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
      ],
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.label,
    required this.value,
    required this.done,
  });

  final String label;
  final String value;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color =
        done ? AppTheme.success : Theme.of(context).colorScheme.outline;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          value.isEmpty ? '—' : value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
