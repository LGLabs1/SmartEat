import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/staff/data/staff_service.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../widgets/confirmation_dialogs.dart';
import '../widgets/pending_approvals_card.dart';
import '../widgets/skeleton_loaders.dart';
import '../utils/error_messages.dart';
import '../utils/haptic_feedback.dart';
import '../utils/staff_utils.dart';

part '../features/staff/widgets/staff_profile_dialog.dart';
part '../features/staff/widgets/staff_tab.dart';
part '../features/staff/widgets/attendance_tab.dart';
part '../features/staff/widgets/payroll_tab.dart';
part '../features/staff/widgets/meals_tab.dart';

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

  // Cached so the profile is fetched once instead of on every rebuild (the
  // FutureBuilder below used to call the provider inline in build()).
  late Future<Map<String, dynamic>?> _profileFuture;

  // Stable StreamBuilders: memoized per eatery so rebuilds don't tear down and
  // re-establish the Firestore listener.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _usersStream;
  String _usersStreamKey = '';

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStreamFor(String eateryId) {
    if (_usersStream == null || _usersStreamKey != eateryId) {
      _usersStreamKey = eateryId;
      _usersStream = StaffService.usersStream(eateryId);
    }
    return _usersStream!;
  }

  @override
  void initState() {
    super.initState();
    _profileFuture = context.read<AuthProvider>().getCurrentUserProfile();
  }

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

  static String _displayNameFromUserDoc(
          Map<String, dynamic> data, String uid) =>
      staffDisplayName(data, uid);

  bool _isAdminFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    return isAdminUser(profile);
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
      await StaffService.approveStaff(uid);
      await _clearPendingApprovalNotification(uid);
      FirebaseService.invalidateUserProfileCache(uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff approved')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ErrorMessageHelper.showSnackBar(context, e, operationContext: 'staff');
    }
  }

  Future<void> _clearPendingApprovalNotification(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc('pending_staff_$uid')
          .delete();
    } catch (_) {}
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
      await _clearPendingApprovalNotification(uid);
      FirebaseService.invalidateUserProfileCache(uid);
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
    final isAdmin = isAdminUser(userData);
    final profileCollection = isAdmin ? 'admin_profiles' : 'staff_profiles';
    final profileRef = FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection(profileCollection)
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

    // Profile data
    final profilePosition = (existing['position'] ?? '').toString().trim();
    final position = profilePosition.isNotEmpty
        ? profilePosition
        : (userData['position'] ?? '').toString().trim();
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
    await StaffService.saveStaffProfile(
      eateryId: eateryId,
      uid: uid,
      isAdmin: isAdmin,
      position: result.position,
      dailyRate: result.dailyRate,
      halfDayRate: result.halfDayRate,
      status: result.status,
      createdAt: existing['createdAt'],
    );

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
    var selectedDate = DateTime.now();
    var workUnit = 1.0;
    final notesController = TextEditingController();
    Map<String, dynamic>? existing;
    var loadingExisting = true;

    Future<void> loadExisting(DateTime day) async {
      loadingExisting = true;
      existing = await _attendanceForDate(
        eateryId: eateryId,
        uid: uid,
        day: day,
      );
      final record = existing;
      if (record == null) {
        workUnit = 1.0;
        notesController.text = '';
      } else {
        final rawUnit = record['workUnit'];
        workUnit = rawUnit is num
            ? rawUnit.toDouble()
            : (record['present'] == true ? 1.0 : 0.0);
        notesController.text = (record['notes'] ?? '').toString();
      }
      loadingExisting = false;
    }

    await loadExisting(selectedDate);
    if (!context.mounted) {
      notesController.dispose();
      return;
    }

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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            setLocal(() {
                              selectedDate = picked;
                              loadingExisting = true;
                            });
                            await loadExisting(picked);
                            if (!context.mounted) return;
                            setLocal(() {});
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Pick'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (loadingExisting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _attendanceCheckInSummary(existing),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
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
                  onPressed: loadingExisting
                      ? null
                      : () => Navigator.of(context).pop(true),
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
    final status =
        workUnit >= 1.0 ? 'present' : (workUnit > 0 ? 'halfday' : 'absent');
    final data = <String, dynamic>{
      'eateryId': eateryId,
      'uid': uid,
      'date': _fmtDate(day),
      'present': present,
      'workUnit': workUnit,
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (existing == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await FirebaseFirestore.instance
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .doc(docId)
        .set(data, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance saved')),
    );
  }

  Future<Map<String, dynamic>?> _attendanceForDate({
    required String eateryId,
    required String uid,
    required DateTime day,
  }) async {
    try {
      final docId = '${eateryId}_${uid}_${_fmtDate(day)}';
      final snap = await FirebaseFirestore.instance
          .collection('eateries')
          .doc(eateryId)
          .collection('staff_attendance')
          .doc(docId)
          .get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  String _attendanceCheckInSummary(Map<String, dynamic>? record) {
    if (record == null) {
      return 'No record yet. Saving will create a new attendance entry.';
    }
    final morning = _formatClockValue(record['morningCheckIn']);
    final afternoon = _formatClockValue(record['afternoonCheckIn']);
    if (morning.isEmpty && afternoon.isEmpty) {
      return 'No self check-ins recorded for this day.';
    }
    return [
      if (morning.isNotEmpty) 'Morning: $morning',
      if (afternoon.isNotEmpty) 'Afternoon: $afternoon',
    ].join(' · ');
  }

  String _formatClockValue(dynamic value) {
    DateTime? dt;
    if (value is DateTime) {
      dt = value;
    } else if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is String) {
      dt = DateTime.tryParse(value);
    }
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<int> _autoMarkAbsent({
    required String eateryId,
    required Map<String, Map<String, dynamic>> usersByUid,
    required DateTime weekStart,
    required Map<String, Map<String, dynamic>> existingAttendance,
  }) {
    final staffUids = usersByUid.entries
        .where((e) => !isAdminUser(e.value))
        .map((e) => e.key);
    return StaffService.markMissingAbsent(
      eateryId: eateryId,
      staffUids: staffUids,
      weekStart: weekStart,
      existingKeys: existingAttendance.keys.toSet(),
      today: DateTime.now(),
    );
  }

  Future<void> _recordPayout(
    BuildContext context, {
    required String eateryId,
    required String uid,
    required DateTime weekStart,
    required double amount,
    required String userLabel,
    required String type,
    required String adminUid,
    required String adminName,
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
    try {
      await StaffService.recordPayout(
        eateryId: eateryId,
        uid: uid,
        weekStartKey: weekKey,
        amount: amount,
        type: type,
        adminUid: adminUid,
        adminName: adminName,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(type == 'advance' ? 'Advance recorded' : 'Payout recorded'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ErrorMessageHelper.showSnackBar(context, e, operationContext: 'staff');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
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
          length: 4,
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
                    stream: _usersStreamFor(eateryId),
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
                              adminUid: adminUid,
                              adminName: adminName,
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
            bottomNavigationBar: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: TabBar(
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.group_outlined, size: 20),
                        text: 'Staff',
                      ),
                      Tab(
                        icon: Icon(Icons.calendar_month_outlined, size: 20),
                        text: 'Attendance',
                      ),
                      Tab(
                        icon: Icon(Icons.payments_outlined, size: 20),
                        text: 'Payroll',
                      ),
                      Tab(
                        icon: Icon(Icons.lunch_dining_outlined, size: 20),
                        text: 'Meals',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
