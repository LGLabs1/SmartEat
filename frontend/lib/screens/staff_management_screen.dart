import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/confirmation_dialogs.dart';
import '../widgets/skeleton_loaders.dart';
import '../utils/error_messages.dart';
import '../utils/haptic_feedback.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
  }) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  DateTime _weekStart = _startOfWeek(DateTime.now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _startOfWeek(DateTime d) {
    final day = _dateOnly(d);
    final weekday = day.weekday; // Mon=1
    return day.subtract(Duration(days: weekday - 1));
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _fmtMoney(double v) {
    return '₱${v.toStringAsFixed(2)}';
  }

  static double _asDouble(dynamic v, {required double fallback}) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().trim()) ?? fallback;
  }

  static String _displayNameFromUserDoc(Map<String, dynamic> data, String uid) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final name = ('$firstName $lastName').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  bool _isAdminFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final dynamic isAdminRaw = profile['isAdmin'];
    final bool isAdminFlag = isAdminRaw == true ||
        isAdminRaw == 1 ||
        (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
    return isAdminFlag || role == 'admin';
  }

  static String _adminDisplayNameFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    final firstName = (profile['firstName'] ?? '').toString().trim();
    final lastName = (profile['lastName'] ?? '').toString().trim();
    return ('$firstName $lastName').trim();
  }

  String _getAdminUid() {
    final authProvider = context.read<AuthProvider>();
    return authProvider.user?.uid ?? '';
  }

  Future<void> _approveStaff(BuildContext context, String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'approved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff approved')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ErrorMessageHelper.showSnackBar(context, e, operationContext: 'staff');
    }
  }

  Future<void> _removeStaff(
    BuildContext context, {
    required String uid,
    required String label,
  }) async {
    final confirmed = await ConfirmAction.remove(
      context,
      itemName: label,
      details: 'They will immediately lose access to this eatery. '
          'They can only access again if added back or if they register again.',
    );

    if (!confirmed) return;

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryId = profile?['eateryId']?.toString() ?? '';
      final eateryName = profile?['eateryName']?.toString() ?? eateryId;
      final adminUid = _getAdminUid();
      final adminFirstName = (profile?['firstName'] ?? '').toString().trim();
      final adminLastName = (profile?['lastName'] ?? '').toString().trim();
      final adminName = ('$adminFirstName $adminLastName').trim();

      final finalAdminName = adminName.isNotEmpty ? adminName : 'Admin';
      final finalEateryName = eateryName.isNotEmpty ? eateryName : eateryId;
      final message =
          '$finalAdminName of eatery $finalEateryName has removed you from this eatery. '
          'You will be logged out. If you believe this is a mistake, please contact your admin.';
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'eateryId': '',
        'eateryName': '',
        'approved': false,
        'removalMessage': message,
        'removedAt': FieldValue.serverTimestamp(),
        'removedByUid': adminUid,
        'removedByName': finalAdminName,
        'removedFromEateryId': eateryId,
        'removedFromEateryName': finalEateryName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      HapticHelper.success();
      ErrorMessageHelper.showSnackBar(
        context,
        Exception('Staff removed successfully'),
        operationContext: 'staff',
      );
    } catch (e) {
      if (!context.mounted) return;
      ErrorMessageHelper.showSnackBar(context, e, operationContext: 'staff');
    }
  }

  Future<void> _editStaffProfile(
    BuildContext context, {
    required String eateryId,
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    final userName = _displayNameFromUserDoc(userData, uid);
    final profileRef = FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_profiles')
        .doc(uid);

    Map<String, dynamic> existing;
    try {
      final snap = await profileRef.get();
      existing = snap.data() ?? const <String, dynamic>{};
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
      return;
    }

    // Get joined date from createdAt
    String joinedDate = 'Unknown';
    final createdAt = existing['createdAt'];
    if (createdAt != null) {
      try {
        if (createdAt is Timestamp) {
          joinedDate = _fmtDate(createdAt.toDate());
        } else if (createdAt is String) {
          joinedDate = createdAt;
        }
      } catch (_) {
        joinedDate = 'Unknown';
      }
    }

    final email = (userData['email'] ?? '').toString();
    final legacyRole = userData['role']?.toString().trim().toLowerCase();
    final isAdmin = (userData['isAdmin'] == true) || (legacyRole == 'admin');

    // Profile data
    final position = (existing['position'] ?? '').toString().trim();
    final dailyRate = existing['dailyRate'];
    final rate = dailyRate is num ? dailyRate.toDouble() : 0.0;
    final halfDayRate = existing['halfDayRate'];
    final halfRate = halfDayRate is num ? halfDayRate.toDouble() : 0.0;
    final status = (existing['status'] ?? 'active').toString().trim();

    final result = await showDialog<_StaffProfileResult>(
      context: context,
      builder: (context) {
        return _StaffProfileDialog(
          userName: userName,
          email: email,
          isAdmin: isAdmin,
          joinedDate: joinedDate,
          position: position,
          dailyRate: rate,
          halfDayRate: halfRate,
          status: status,
          onRemove: isAdmin
              ? null
              : () async {
                  Navigator.of(context).pop();
                  await _removeStaff(context, uid: uid, label: userName);
                },
        );
      },
    );

    if (result == null) return;

    // Save changes
    await profileRef.set({
      'eateryId': eateryId,
      'uid': uid,
      'position': result.position,
      'dailyRate': result.dailyRate,
      'halfDayRate': result.halfDayRate,
      'status': result.status,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': existing['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Staff profile saved')),
    );
  }

  Future<void> _encodeAttendance(
    BuildContext context, {
    required String eateryId,
    required String uid,
    required String userLabel,
  }) async {
    DateTime selectedDate = DateTime.now();
    double workUnit = 1.0;
    final notesController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('Attendance: $userLabel'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Date: ${_fmtDate(selectedDate)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020, 1, 1),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (picked == null) return;
                            setLocal(() => selectedDate = picked);
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Pick'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<double>(
                      value: workUnit,
                      items: const [
                        DropdownMenuItem(value: 1.0, child: Text('Full day')),
                        DropdownMenuItem(value: 0.5, child: Text('Half day')),
                        DropdownMenuItem(value: 0.0, child: Text('Absent')),
                      ],
                      onChanged: (v) =>
                          setLocal(() => workUnit = (v ?? workUnit)),
                      decoration: const InputDecoration(
                        labelText: 'Work logged',
                      ),
                    ),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final notes = notesController.text.trim();
    notesController.dispose();
    if (saved != true) return;

    final day = _dateOnly(selectedDate);
    final docId = '${eateryId}_${uid}_${_fmtDate(day)}';
    final present = workUnit > 0;
    await FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .doc(docId)
        .set({
      'eateryId': eateryId,
      'uid': uid,
      'date': _fmtDate(day),
      'present': present,
      'workUnit': workUnit,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance saved')),
    );
  }

  Future<void> _autoMarkAbsent({
    required String eateryId,
    required Map<String, Map<String, dynamic>> usersByUid,
    required DateTime weekStart,
    required Map<String, Map<String, dynamic>> existingAttendance,
  }) async {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final weekEnd = weekStart.add(const Duration(days: 6));

    for (final uid in usersByUid.keys) {
      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        // Only auto-mark past days (not today or future)
        if (day.isAfter(today)) continue;

        final dateKey = _fmtDate(day);
        final key = '$uid|$dateKey';

        // Skip if attendance already exists
        if (existingAttendance.containsKey(key)) continue;

        // Mark as absent
        final docId = '${eateryId}_${uid}_$dateKey';
        await FirebaseFirestore.instance
            .collection('eateries')
            .doc(eateryId)
            .collection('staff_attendance')
            .doc(docId)
            .set({
          'eateryId': eateryId,
          'uid': uid,
          'date': dateKey,
          'present': false,
          'workUnit': 0.0,
          'notes': 'Auto-marked absent',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'autoMarked': true,
        }, SetOptions(merge: true));
      }
    }
  }

  Future<void> _recordPayout(
    BuildContext context, {
    required String eateryId,
    required String uid,
    required DateTime weekStart,
    required double amount,
    required String userLabel,
    required String type,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(type == 'advance'
              ? 'Record advance: $userLabel'
              : 'Record payout: $userLabel'),
          content: Text(
            'Week of ${_fmtDate(weekStart)}\n\nAmount: ${_fmtMoney(amount)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child:
                  Text(type == 'advance' ? 'Record advance' : 'Record as paid'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final weekKey = _fmtDate(weekStart);
    final payoutId = type == 'weekly'
        ? '${eateryId}_${uid}_$weekKey'
        : '${eateryId}_${uid}_${weekKey}_advance_${DateTime.now().millisecondsSinceEpoch}';
    await FirebaseFirestore.instance
        .collection('payroll_payouts')
        .doc(payoutId)
        .set({
      'eateryId': eateryId,
      'uid': uid,
      'weekStart': weekKey,
      'amount': amount,
      'type': type,
      'paidAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(type == 'advance' ? 'Advance recorded' : 'Payout recorded'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: context.read<AuthProvider>().getCurrentUserProfile(),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SkeletonCard(height: 80),
                SizedBox(height: 16),
                SkeletonListTile(hasLeading: true, hasSubtitle: true),
                SkeletonListTile(hasLeading: true, hasSubtitle: true),
                SkeletonListTile(hasLeading: true, hasSubtitle: true),
              ],
            ),
          );
        }

        if (profileSnapshot.hasError) {
          return Scaffold(
            appBar: widget.showAppBar
                ? AppBar(
                    leading: widget.onOpenDrawer != null
                        ? IconButton(
                            icon: const Icon(Icons.menu),
                            tooltip: 'Menu',
                            onPressed: widget.onOpenDrawer,
                          )
                        : (Navigator.of(context).canPop()
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              )
                            : null),
                    title: const Text('Staff Management'),
                  )
                : null,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load profile: ${profileSnapshot.error}'),
              ),
            ),
          );
        }

        final profile = profileSnapshot.data;
        final eateryId = (profile?['eateryId'] ?? '').toString().trim();
        final eateryName = (profile?['eateryName'] ?? '').toString().trim();
        final adminUid = context.read<AuthProvider>().user?.uid ?? '';
        final adminName = _adminDisplayNameFromProfile(profile);
        if (eateryId.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Eatery is not set for this account.'),
              ),
            ),
          );
        }

        final isAdmin = _isAdminFromProfile(profile);
        if (!isAdmin) {
          return Scaffold(
            appBar: widget.showAppBar
                ? AppBar(
                    leading: widget.onOpenDrawer != null
                        ? IconButton(
                            icon: const Icon(Icons.menu),
                            tooltip: 'Menu',
                            onPressed: widget.onOpenDrawer,
                          )
                        : (Navigator.of(context).canPop()
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              )
                            : null),
                    title: const Text('Staff Management'),
                  )
                : null,
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Admin access required.'),
              ),
            ),
          );
        }

        final weekEnd = _weekStart.add(const Duration(days: 6));
        final weekLabel = '${_fmtDate(_weekStart)} to ${_fmtDate(weekEnd)}';

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: widget.showAppBar
                ? AppBar(
                    leading: widget.onOpenDrawer != null
                        ? IconButton(
                            icon: const Icon(Icons.menu),
                            tooltip: 'Menu',
                            onPressed: widget.onOpenDrawer,
                          )
                        : (Navigator.of(context).canPop()
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              )
                            : null),
                    title: const Text('Staff Management'),
                    bottom: const TabBar(
                      tabs: [
                        Tab(text: 'Staff'),
                        Tab(text: 'Admins'),
                        Tab(text: 'Attendance'),
                        Tab(text: 'Payroll'),
                        Tab(text: 'Meals'),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Previous week',
                        onPressed: () {
                          setState(() {
                            _weekStart =
                                _weekStart.subtract(const Duration(days: 7));
                          });
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            weekLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next week',
                        onPressed: () {
                          setState(() {
                            _weekStart =
                                _weekStart.add(const Duration(days: 7));
                          });
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                      const SizedBox(width: 4),
                    ],
                  )
                : null,
            body: Column(
              children: [
                if (!widget.showAppBar)
                  Material(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Staff'),
                            Tab(text: 'Admins'),
                            Tab(text: 'Attendance'),
                            Tab(text: 'Payroll'),
                            Tab(text: 'Meals'),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Previous week',
                                onPressed: () {
                                  setState(() {
                                    _weekStart = _weekStart
                                        .subtract(const Duration(days: 7));
                                  });
                                },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  weekLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next week',
                                onPressed: () {
                                  setState(() {
                                    _weekStart =
                                        _weekStart.add(const Duration(days: 7));
                                  });
                                },
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('eateryId', isEqualTo: eateryId)
                        .snapshots(),
                    builder: (context, usersSnap) {
                      if (usersSnap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                'Failed to load users: ${usersSnap.error}'),
                          ),
                        );
                      }
                      if (!usersSnap.hasData) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SkeletonListTile(
                                hasLeading: true, hasSubtitle: true),
                            SkeletonListTile(
                                hasLeading: true, hasSubtitle: true),
                            SkeletonListTile(
                                hasLeading: true, hasSubtitle: true),
                            SkeletonListTile(
                                hasLeading: true, hasSubtitle: true),
                            SkeletonListTile(
                                hasLeading: true, hasSubtitle: true),
                          ],
                        );
                      }

                      final userDocs = usersSnap.data!.docs;
                      final usersByUid = <String, Map<String, dynamic>>{
                        for (final d in userDocs) d.id: d.data(),
                      };

                      return TabBarView(
                        children: [
                          _StaffTab(
                            eateryId: eateryId,
                            eateryName: eateryName,
                            adminUid: adminUid,
                            adminName: adminName,
                            usersByUid: usersByUid,
                            globalSearchQuery: widget.globalSearchQuery,
                            onEditProfile: (uid, data) => _editStaffProfile(
                              context,
                              eateryId: eateryId,
                              uid: uid,
                              userData: data,
                            ),
                            onApproveStaff: _approveStaff,
                            onRemoveStaff: _removeStaff,
                          ),
                          _AdminsTab(
                            eateryId: eateryId,
                            usersByUid: usersByUid,
                            onEditProfile: (uid, data) => _editStaffProfile(
                              context,
                              eateryId: eateryId,
                              uid: uid,
                              userData: data,
                            ),
                          ),
                          _AttendanceTab(
                            eateryId: eateryId,
                            usersByUid: usersByUid,
                            weekStart: _weekStart,
                            onEncodeAttendance: (uid, label) =>
                                _encodeAttendance(
                              context,
                              eateryId: eateryId,
                              uid: uid,
                              userLabel: label,
                            ),
                            onAutoMarkAbsent: (existingAttendance) =>
                                _autoMarkAbsent(
                              eateryId: eateryId,
                              usersByUid: usersByUid,
                              weekStart: _weekStart,
                              existingAttendance: existingAttendance,
                            ),
                          ),
                          _PayrollTab(
                            eateryId: eateryId,
                            usersByUid: usersByUid,
                            weekStart: _weekStart,
                            onRecordPayout: (uid, label, amount, type) =>
                                _recordPayout(
                              context,
                              eateryId: eateryId,
                              uid: uid,
                              weekStart: _weekStart,
                              amount: amount,
                              userLabel: label,
                              type: type,
                            ),
                          ),
                          _MealsTab(eateryId: eateryId),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StaffProfileResult {
  final String position;
  final double dailyRate;
  final double halfDayRate;
  final String status;

  _StaffProfileResult({
    required this.position,
    required this.dailyRate,
    required this.halfDayRate,
    required this.status,
  });
}

class _StaffProfileDialog extends StatefulWidget {
  final String userName;
  final String email;
  final bool isAdmin;
  final String joinedDate;
  final String position;
  final double dailyRate;
  final double halfDayRate;
  final String status;
  final VoidCallback? onRemove;

  const _StaffProfileDialog({
    required this.userName,
    required this.email,
    required this.isAdmin,
    required this.joinedDate,
    required this.position,
    required this.dailyRate,
    required this.halfDayRate,
    required this.status,
    this.onRemove,
  });

  @override
  State<_StaffProfileDialog> createState() => _StaffProfileDialogState();
}

class _StaffProfileDialogState extends State<_StaffProfileDialog> {
  late bool _isEditing;
  late TextEditingController _positionController;
  late TextEditingController _dailyRateController;
  late TextEditingController _halfDayRateController;
  late String _status;

  @override
  void initState() {
    super.initState();
    _isEditing = false;
    _positionController = TextEditingController(text: widget.position);
    _dailyRateController = TextEditingController(
      text: widget.dailyRate > 0 ? widget.dailyRate.toStringAsFixed(2) : '',
    );
    _halfDayRateController = TextEditingController(
      text: widget.halfDayRate > 0 ? widget.halfDayRate.toStringAsFixed(2) : '',
    );
    _status = widget.status;
  }

  @override
  void dispose() {
    _positionController.dispose();
    _dailyRateController.dispose();
    _halfDayRateController.dispose();
    super.dispose();
  }

  double _parseDouble(String value) {
    if (value.trim().isEmpty) return 0.0;
    return double.tryParse(value.trim()) ?? 0.0;
  }

  Widget _buildReadOnlyView() {
    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info header
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    widget.isAdmin ? Colors.indigo : Colors.grey.shade400,
                child: Icon(
                  widget.isAdmin
                      ? Icons.admin_panel_settings
                      : Icons.badge_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.email.isNotEmpty ? widget.email : 'No email',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Joined date
          _buildInfoRow(Icons.calendar_today, 'Joined', widget.joinedDate),
          const SizedBox(height: 12),

          // Role
          _buildInfoRow(
            widget.isAdmin ? Icons.admin_panel_settings : Icons.badge_outlined,
            'Role',
            widget.isAdmin ? 'Admin' : 'Staff',
          ),
          const SizedBox(height: 12),

          // Position
          _buildInfoRow(Icons.work_outline, 'Position',
              widget.position.isNotEmpty ? widget.position : 'Not set'),
          const SizedBox(height: 12),

          // Daily rate
          _buildInfoRow(
            Icons.attach_money,
            'Daily Rate',
            widget.dailyRate > 0
                ? '₱${widget.dailyRate.toStringAsFixed(2)}'
                : 'Not set',
          ),
          const SizedBox(height: 12),

          // Half-day rate (now exact amount)
          _buildInfoRow(
            Icons.timer_outlined,
            'Half-Day Rate',
            widget.halfDayRate > 0
                ? '₱${widget.halfDayRate.toStringAsFixed(2)}'
                : 'Not set',
          ),
          const SizedBox(height: 12),

          // Status
          _buildInfoRow(
            Icons.circle,
            'Status',
            widget.status.isNotEmpty ? widget.status : 'active',
            statusColor: widget.status == 'active' ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? statusColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: statusColor ?? Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: statusColor ?? Colors.grey.shade900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditView() {
    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _positionController,
            decoration: const InputDecoration(
              labelText: 'Position',
              prefixIcon: Icon(Icons.work_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dailyRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daily rate (₱)',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _halfDayRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Half-day rate (₱) - exact amount',
              prefixIcon: Icon(Icons.timer_outlined),
              helperText: 'Enter exact amount (not percentage)',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _status = v);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.circle_outlined),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Staff profile: ${widget.userName}'),
      content: _isEditing ? _buildEditView() : _buildReadOnlyView(),
      actions: [
        if (!_isEditing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (widget.onRemove != null)
            TextButton.icon(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          FilledButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
          ),
        ] else ...[
          TextButton(
            onPressed: () => setState(() => _isEditing = false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final result = _StaffProfileResult(
                position: _positionController.text.trim(),
                dailyRate: _parseDouble(_dailyRateController.text),
                halfDayRate: _parseDouble(_halfDayRateController.text),
                status: _status,
              );
              Navigator.of(context).pop(result);
            },
            child: const Text('Save'),
          ),
        ],
      ],
    );
  }
}

class _StaffTab extends StatefulWidget {
  const _StaffTab({
    required this.eateryId,
    required this.eateryName,
    required this.adminUid,
    required this.adminName,
    required this.usersByUid,
    required this.globalSearchQuery,
    required this.onEditProfile,
    required this.onApproveStaff,
    required this.onRemoveStaff,
  });

  final String eateryId;
  final String eateryName;
  final String adminUid;
  final String adminName;
  final Map<String, Map<String, dynamic>> usersByUid;
  final ValueNotifier<String>? globalSearchQuery;
  final Future<void> Function(String uid, Map<String, dynamic> userData)
      onEditProfile;
  final Future<void> Function(BuildContext context, String uid) onApproveStaff;
  final Future<void> Function(BuildContext context,
      {required String uid, required String label}) onRemoveStaff;

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  late TextEditingController _searchController;
  String _localQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _displayName(Map<String, dynamic> data, String uid) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final name = ('$firstName $lastName').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  bool _matches(String q, String text) {
    if (q.isEmpty) return true;
    return text.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.globalSearchQuery;
    if (notifier == null) {
      final q = '';

      final entries = widget.usersByUid.entries.where((e) {
        final uid = e.key;
        final data = e.value;
        final email = (data['email'] ?? '').toString();
        final name = _displayName(data, uid);
        // Filter out admins - they should only appear in Admins tab
        final legacyRole = data['role']?.toString().trim().toLowerCase();
        final isAdmin = (data['isAdmin'] == true) || (legacyRole == 'admin');
        if (isAdmin) return false;
        return _matches(q, uid) || _matches(q, email) || _matches(q, name);
      }).toList()
        ..sort((a, b) => _displayName(a.value, a.key)
            .toLowerCase()
            .compareTo(_displayName(b.value, b.key).toLowerCase()));

      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('eateries')
            .doc(widget.eateryId)
            .collection('staff_profiles')
            .snapshots(),
        builder: (context, profilesSnap) {
          final profileByUid = <String, Map<String, dynamic>>{};
          if (profilesSnap.hasData) {
            for (final d in profilesSnap.data!.docs) {
              final data = d.data();
              final docUid = d.id.toString().trim();
              if (docUid.isEmpty) continue;
              profileByUid[docUid] = data;
            }
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final uid = entries[index].key;
              final userData = entries[index].value;
              final label = _displayName(userData, uid);
              final email = (userData['email'] ?? '').toString();

              final legacyRole =
                  userData['role']?.toString().trim().toLowerCase();
              final isAdmin =
                  (userData['isAdmin'] == true) || (legacyRole == 'admin');
              final dynamic approvedRaw = userData['approved'];
              final bool approved =
                  approvedRaw == null ? true : approvedRaw == true;

              final p = profileByUid[uid] ?? const <String, dynamic>{};
              final position = (p['position'] ?? '').toString().trim();
              final dailyRate = p['dailyRate'];
              final rate = dailyRate is num ? dailyRate.toDouble() : 0.0;
              final status = (p['status'] ?? 'active').toString().trim();

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  onTap: () => widget.onEditProfile(uid, userData),
                  leading: CircleAvatar(
                    backgroundColor:
                        isAdmin ? Colors.indigo : Colors.grey.shade400,
                    child: Icon(
                      isAdmin
                          ? Icons.admin_panel_settings
                          : Icons.badge_outlined,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${email.isEmpty ? uid : email}\n'
                    '${isAdmin ? 'Admin' : (approved ? 'Staff' : 'Staff (Pending)')} · '
                    '${status.isEmpty ? 'active' : status}'
                    '${position.isEmpty ? '' : ' · $position'}'
                    '${rate > 0 ? ' · ₱${rate.toStringAsFixed(2)}/day' : ''}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      );
    }

    return ValueListenableBuilder<String>(
      valueListenable: widget.globalSearchQuery!,
      builder: (context, query, _) {
        final q = query.trim().toLowerCase();
        final combinedQuery =
            q.isNotEmpty ? q : _localQuery.trim().toLowerCase();

        final entries = widget.usersByUid.entries.where((e) {
          final uid = e.key;
          final data = e.value;
          final email = (data['email'] ?? '').toString();
          final name = _displayName(data, uid);
          // Filter out admins - they should only appear in Admins tab
          final legacyRole = data['role']?.toString().trim().toLowerCase();
          final isAdmin = (data['isAdmin'] == true) || (legacyRole == 'admin');
          if (isAdmin) return false;
          return _matches(combinedQuery, uid) ||
              _matches(combinedQuery, email) ||
              _matches(combinedQuery, name);
        }).toList()
          ..sort((a, b) => _displayName(a.value, a.key)
              .toLowerCase()
              .compareTo(_displayName(b.value, b.key).toLowerCase()));

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('eateries')
              .doc(widget.eateryId)
              .collection('staff_profiles')
              .snapshots(),
          builder: (context, profilesSnap) {
            final profileByUid = <String, Map<String, dynamic>>{};
            if (profilesSnap.hasData) {
              for (final d in profilesSnap.data!.docs) {
                final data = d.data();
                final docUid = d.id.toString().trim();
                if (docUid.isEmpty) continue;
                profileByUid[docUid] = data;
              }
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final uid = entries[index].key;
                final userData = entries[index].value;
                final label = _displayName(userData, uid);
                final email = (userData['email'] ?? '').toString();

                final legacyRole =
                    userData['role']?.toString().trim().toLowerCase();
                final isAdmin =
                    (userData['isAdmin'] == true) || (legacyRole == 'admin');
                final dynamic approvedRaw = userData['approved'];
                final bool approved =
                    approvedRaw == null ? true : approvedRaw == true;

                final p = profileByUid[uid] ?? const <String, dynamic>{};
                final position = (p['position'] ?? '').toString().trim();
                final dailyRate = p['dailyRate'];
                final rate = dailyRate is num ? dailyRate.toDouble() : 0.0;
                final status = (p['status'] ?? 'active').toString().trim();

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    onTap: () => widget.onEditProfile(uid, userData),
                    leading: CircleAvatar(
                      backgroundColor:
                          isAdmin ? Colors.indigo : Colors.grey.shade400,
                      child: Icon(
                        isAdmin
                            ? Icons.admin_panel_settings
                            : Icons.badge_outlined,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${email.isEmpty ? uid : email}\n'
                      '${isAdmin ? 'Admin' : (approved ? 'Staff' : 'Staff (Pending)')} · '
                      '${status.isEmpty ? 'active' : status}'
                      '${position.isEmpty ? '' : ' · $position'}'
                      '${rate > 0 ? ' · ₱${rate.toStringAsFixed(2)}/day' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminsTab extends StatelessWidget {
  const _AdminsTab({
    required this.eateryId,
    required this.usersByUid,
    required this.onEditProfile,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final Future<void> Function(String uid, Map<String, dynamic> userData)
      onEditProfile;

  String _displayName(Map<String, dynamic> data, String uid) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final name = ('$firstName $lastName').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  @override
  Widget build(BuildContext context) {
    // Filter only admin users
    final adminEntries = usersByUid.entries.where((e) {
      final data = e.value;
      final legacyRole = data['role']?.toString().trim().toLowerCase();
      return (data['isAdmin'] == true) || (legacyRole == 'admin');
    }).toList()
      ..sort((a, b) => _displayName(a.value, a.key)
          .toLowerCase()
          .compareTo(_displayName(b.value, b.key).toLowerCase()));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('admin_profiles')
          .snapshots(),
      builder: (context, profilesSnap) {
        final profileByUid = <String, Map<String, dynamic>>{};
        if (profilesSnap.hasData) {
          for (final d in profilesSnap.data!.docs) {
            final data = d.data();
            final docUid = d.id.toString().trim();
            if (docUid.isEmpty) continue;
            profileByUid[docUid] = data;
          }
        }

        if (adminEntries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No admins found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: adminEntries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final uid = adminEntries[index].key;
            final userData = adminEntries[index].value;
            final label = _displayName(userData, uid);
            final email = (userData['email'] ?? '').toString();

            final p = profileByUid[uid] ?? const <String, dynamic>{};
            final position = (p['position'] ?? '').toString().trim();
            final status = (p['status'] ?? 'active').toString().trim();
            final joinedAt = p['joinedAt'] ?? userData['createdAt'];

            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.indigo.shade200),
              ),
              child: ListTile(
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(label),
                    content: Text(
                      '${email.isEmpty ? uid : email}\n'
                      'Admin · ${status.isEmpty ? 'active' : status}'
                      '${position.isEmpty ? '' : ' · $position'}'
                      '${joinedAt != null ? '\nJoined: ${joinedAt.toString().split('T').first}' : ''}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => onEditProfile(uid, userData),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${email.isEmpty ? uid : email}\n'
                  'Admin · ${status.isEmpty ? 'active' : status}'
                  '${position.isEmpty ? '' : ' · $position'}'
                  '${joinedAt != null ? '\nJoined: ${joinedAt.toString().split('T').first}' : ''}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({
    required this.eateryId,
    required this.usersByUid,
    required this.weekStart,
    required this.onEncodeAttendance,
    required this.onAutoMarkAbsent,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final DateTime weekStart;
  final Future<void> Function(String uid, String userLabel) onEncodeAttendance;
  final Future<void> Function(
      Map<String, Map<String, dynamic>> existingAttendance) onAutoMarkAbsent;

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _displayName(Map<String, dynamic> data, String uid) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final name = ('$firstName $lastName').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startKey = _fmtDate(weekStart);
    final endKey = _fmtDate(weekEnd);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('staff_attendance')
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .snapshots(),
      builder: (context, attSnap) {
        if (attSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load attendance: ${attSnap.error}'),
            ),
          );
        }

        final byUidDate = <String, Map<String, dynamic>>{};
        if (attSnap.hasData) {
          for (final d in attSnap.data!.docs) {
            final a = d.data();
            final uid = (a['uid'] ?? '').toString().trim();
            final date = (a['date'] ?? '').toString().trim();
            if (uid.isEmpty || date.isEmpty) continue;
            byUidDate['$uid|$date'] = a;
          }
          // Auto-mark absent for past days without attendance records
          onAutoMarkAbsent(byUidDate);
        }

        final uids = usersByUid.keys.toList()..sort();
        final days = List<DateTime>.generate(
          7,
          (i) => weekStart.add(Duration(days: i)),
        );

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: uids.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final uid = uids[index];
            final userData = usersByUid[uid] ?? const <String, dynamic>{};
            final label = _displayName(userData, uid);

            double workedUnits = 0;
            for (final day in days) {
              final key = _fmtDate(day);
              final a = byUidDate['$uid|$key'];
              if (a == null) continue;
              final rawUnit = a['workUnit'];
              final unit = rawUnit is num
                  ? rawUnit.toDouble()
                  : (a['present'] == true ? 1.0 : 0.0);
              workedUnits += unit;
            }

            return Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${workedUnits.toStringAsFixed(1)}/7 worked',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => onEncodeAttendance(uid, label),
                          icon: const Icon(Icons.edit_calendar),
                          label: const Text('Encode'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: days.map((day) {
                        final dateKey = _fmtDate(day);
                        final a = byUidDate['$uid|$dateKey'];
                        final hasLog = a != null;
                        final rawUnit = a?['workUnit'];
                        final unit = rawUnit is num
                            ? rawUnit.toDouble()
                            : (a?['present'] == true ? 1.0 : 0.0);
                        final labelDay = '${day.month}/${day.day}';

                        Color bg;
                        Color fg;
                        if (!hasLog) {
                          bg = Colors.grey.shade100;
                          fg = Colors.grey.shade700;
                        } else if (unit >= 1.0) {
                          bg = Colors.green.shade100;
                          fg = Colors.green.shade900;
                        } else if (unit > 0) {
                          bg = Colors.orange.shade100;
                          fg = Colors.orange.shade900;
                        } else {
                          bg = Colors.red.shade100;
                          fg = Colors.red.shade900;
                        }

                        return InkWell(
                          onTap: () => onEncodeAttendance(uid, label),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              hasLog
                                  ? (unit >= 1.0
                                      ? '$labelDay ✓'
                                      : (unit > 0
                                          ? '$labelDay ½'
                                          : '$labelDay ✕'))
                                  : '$labelDay —',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PayrollTab extends StatelessWidget {
  const _PayrollTab({
    required this.eateryId,
    required this.usersByUid,
    required this.weekStart,
    required this.onRecordPayout,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final DateTime weekStart;
  final Future<void> Function(
    String uid,
    String userLabel,
    double amount,
    String type,
  ) onRecordPayout;

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _fmtMoney(double v) => '₱${v.toStringAsFixed(2)}';

  String _displayName(Map<String, dynamic> data, String uid) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final name = ('$firstName $lastName').trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startKey = _fmtDate(weekStart);
    final endKey = _fmtDate(weekEnd);

    final profilesStream = FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_profiles')
        .snapshots();

    final attendanceStream = FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .snapshots();

    final payoutsStream = FirebaseFirestore.instance
        .collection('payroll_payouts')
        .where('eateryId', isEqualTo: eateryId)
        .where('weekStart', isEqualTo: startKey)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: profilesStream,
      builder: (context, profSnap) {
        final rateByUid = <String, double>{};
        final halfDayRateByUid = <String, double>{};
        if (profSnap.hasData) {
          for (final d in profSnap.data!.docs) {
            final p = d.data();
            final uid = (p['uid'] ?? '').toString().trim();
            if (uid.isEmpty) continue;
            final raw = p['dailyRate'];
            final rate = raw is num ? raw.toDouble() : 0.0;
            rateByUid[uid] = rate;

            final rawHalf = p['halfDayRate'];
            final halfRate = rawHalf is num ? rawHalf.toDouble() : 0.0;
            halfDayRateByUid[uid] = halfRate;
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: attendanceStream,
          builder: (context, attSnap) {
            final fullDaysByUid = <String, int>{};
            final halfDaysByUid = <String, int>{};
            if (attSnap.hasData) {
              for (final d in attSnap.data!.docs) {
                final a = d.data();
                final uid = (a['uid'] ?? '').toString().trim();
                if (uid.isEmpty) continue;

                final rawUnit = a['workUnit'];
                final unit = rawUnit is num
                    ? rawUnit.toDouble()
                    : (a['present'] == true ? 1.0 : 0.0);

                if (unit >= 1.0) {
                  fullDaysByUid[uid] = (fullDaysByUid[uid] ?? 0) + 1;
                } else if (unit > 0) {
                  halfDaysByUid[uid] = (halfDaysByUid[uid] ?? 0) + 1;
                }
              }
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: payoutsStream,
              builder: (context, paySnap) {
                final paidWeeklyByUid = <String, double>{};
                final advancesByUid = <String, double>{};
                if (paySnap.hasData) {
                  for (final d in paySnap.data!.docs) {
                    final p = d.data();
                    final uid = (p['uid'] ?? '').toString().trim();
                    if (uid.isEmpty) continue;
                    final raw = p['amount'];
                    final amount = raw is num ? raw.toDouble() : 0.0;
                    final type = (p['type'] ?? 'weekly').toString().trim();
                    if (type == 'advance') {
                      advancesByUid[uid] = (advancesByUid[uid] ?? 0) + amount;
                    } else {
                      paidWeeklyByUid[uid] = amount;
                    }
                  }
                }

                final uids = usersByUid.keys.toList()..sort();
                double grandTotal = 0;

                final rows = uids.map((uid) {
                  final userData = usersByUid[uid] ?? const <String, dynamic>{};
                  final label = _displayName(userData, uid);
                  final fullDays = fullDaysByUid[uid] ?? 0;
                  final halfDays = halfDaysByUid[uid] ?? 0;
                  final rate = rateByUid[uid] ?? 0.0;
                  final halfDayRate = halfDayRateByUid[uid] ?? 0.0;

                  // Calculate gross using exact half-day rate
                  final gross = (rate * fullDays) + (halfDayRate * halfDays);
                  grandTotal += gross;
                  final advances = advancesByUid[uid] ?? 0.0;
                  final net = (gross - advances) < 0 ? 0.0 : (gross - advances);
                  final paidAmount = paidWeeklyByUid[uid];
                  final isPaid = paidAmount != null;
                  return {
                    'uid': uid,
                    'label': label,
                    'fullDays': fullDays,
                    'halfDays': halfDays,
                    'rate': rate,
                    'halfDayRate': halfDayRate,
                    'gross': gross,
                    'advances': advances,
                    'net': net,
                    'isPaid': isPaid,
                  };
                }).toList();

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Weekly total',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _fmtMoney(grandTotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...rows.map((r) {
                      final uid = r['uid'] as String;
                      final label = r['label'] as String;
                      final fullDays = r['fullDays'] as int;
                      final halfDays = r['halfDays'] as int;
                      final halfDayRate = r['halfDayRate'] as double;
                      final gross = r['gross'] as double;
                      final advances = r['advances'] as double;
                      final net = r['net'] as double;
                      final isPaid = r['isPaid'] as bool;

                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          title: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Full: $fullDays · Half: $halfDays @ ₱${halfDayRate.toStringAsFixed(2)}/half-day\n'
                            'Gross: ${_fmtMoney(gross)} · Advances: ${_fmtMoney(advances)}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _fmtMoney(net),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonal(
                                onPressed: isPaid
                                    ? null
                                    : () async {
                                        final amountController =
                                            TextEditingController();
                                        final saved = await showDialog<bool>(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: Text(
                                                  'Advance payout: $label'),
                                              content: TextField(
                                                controller: amountController,
                                                keyboardType:
                                                    TextInputType.number,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Amount (₱)',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(false),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(true),
                                                  child: const Text('Record'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        final amount =
                                            _StaffManagementScreenState
                                                ._asDouble(
                                          amountController.text,
                                          fallback: 0,
                                        );
                                        amountController.dispose();
                                        if (saved != true) return;
                                        if (amount <= 0) return;
                                        await onRecordPayout(
                                          uid,
                                          label,
                                          amount,
                                          'advance',
                                        );
                                      },
                                child: const Text('Advance'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: isPaid || net <= 0
                                    ? null
                                    : () => onRecordPayout(
                                        uid, label, net, 'weekly'),
                                child: Text(isPaid ? 'Paid' : 'Mark paid'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MealsTab extends StatefulWidget {
  final String eateryId;

  const _MealsTab({required this.eateryId});

  @override
  State<_MealsTab> createState() => _MealsTabState();
}

class _MealsTabState extends State<_MealsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mealOrders = [];
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadMealOrders();
  }

  Future<void> _loadMealOrders() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getStaffMealOrders(
        eateryId: widget.eateryId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        setState(() {
          _mealOrders = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load meal orders: $e')),
        );
      }
    }
  }

  // Optimistic update helper
  void _updateMealOrderStatusLocal(String orderId, String status) {
    setState(() {
      _mealOrders = _mealOrders.map((order) {
        if (order['id'] == orderId) {
          return {...order, 'status': status};
        }
        return order;
      }).toList();
    });
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await ApiService.updateStaffMealOrderStatus(
        orderId,
        eateryId: widget.eateryId,
        status: status,
      );
      // Optimistic update - update status in local list without full refresh
      _updateMealOrderStatusLocal(orderId, status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order $status')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update order: $e')),
        );
      }
    }
  }

  double _calculateTotalCost() {
    return _mealOrders.fold(0.0, (sum, order) {
      final items = (order['items'] as List?) ?? [];
      return sum +
          items.fold(0.0, (itemSum, item) {
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            return itemSum + (price * qty);
          });
    });
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    final total = items.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      return sum + (price * qty);
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order by ${order['staffName'] ?? 'Unknown'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${order['status'] ?? 'unknown'}',
                style: TextStyle(
                  color: (order['status'] ?? '') == 'completed'
                      ? Colors.green
                      : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Date: ${order['createdAt'] ?? ''}'),
              if (order['notes'] != null &&
                  order['notes'].toString().isNotEmpty)
                Text('Notes: ${order['notes']}'),
              const SizedBox(height: 16),
              const Divider(),
              const Text('Items:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...items.map((item) => ListTile(
                    title: Text(item['name'] ?? 'Unknown'),
                    trailing: Text(
                      '${item['quantity']} x ₱${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                  )),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total: ₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (order['status'] == 'pending')
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateOrderStatus(order['id'], 'completed');
              },
              child: const Text('Mark Completed'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCost = _calculateTotalCost();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range picker and summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: _endDate,
                            );
                            if (date != null) {
                              setState(() => _startDate = date);
                              _loadMealOrders();
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'From',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _endDate,
                              firstDate: _startDate,
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() => _endDate = date);
                              _loadMealOrders();
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'To',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Orders: ${_mealOrders.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total Cost: ₱${totalCost.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Meal orders list
          Expanded(
            child: _isLoading
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                    ],
                  )
                : _mealOrders.isEmpty
                    ? const Center(child: Text('No meal orders found'))
                    : ListView.builder(
                        itemCount: _mealOrders.length,
                        itemBuilder: (context, index) {
                          final order = _mealOrders[index];
                          final items = (order['items'] as List?) ?? [];
                          final itemCount = items.fold(0, (sum, item) {
                            return sum +
                                ((item['quantity'] as num?)?.toInt() ?? 0);
                          });
                          final total = items.fold(0.0, (sum, item) {
                            final price =
                                (item['price'] as num?)?.toDouble() ?? 0.0;
                            final qty =
                                (item['quantity'] as num?)?.toInt() ?? 0;
                            return sum + (price * qty);
                          });

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: order['status'] == 'completed'
                                    ? Colors.green
                                    : Colors.orange,
                                child: Icon(
                                  order['status'] == 'completed'
                                      ? Icons.check
                                      : Icons.access_time,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(order['staffName'] ?? 'Unknown'),
                              subtitle: Text(
                                '$itemCount items • ₱${total.toStringAsFixed(2)}',
                              ),
                              trailing: Text(
                                order['createdAt'] != null
                                    ? order['createdAt']
                                        .toString()
                                        .substring(0, 10)
                                    : '',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => _showOrderDetails(order),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
