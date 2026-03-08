import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({Key? key, this.globalSearchQuery})
      : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  DateTime _weekStart = _startOfWeek(DateTime.now());

  static const double _defaultHalfDayMultiplier = 0.5;

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

  Future<void> _editStaffProfile(
    BuildContext context, {
    required String eateryId,
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    final userName = _displayNameFromUserDoc(userData, uid);
    final profileRef = FirebaseFirestore.instance
        .collection('staff_profiles')
        .doc('${eateryId}_$uid');

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

    final positionController = TextEditingController(
      text: (existing['position'] ?? '').toString(),
    );
    final rateController = TextEditingController(
      text: (() {
        final rate = existing['dailyRate'];
        if (rate is num) return rate.toString();
        final s = (rate ?? '').toString().trim();
        return s;
      })(),
    );

    final halfDayMultiplierController = TextEditingController(
      text: (() {
        final v = existing['halfDayMultiplier'];
        if (v is num) return v.toString();
        final s = (v ?? '').toString().trim();
        return s;
      })(),
    );

    String status = (existing['status'] ?? 'active').toString().trim();
    if (status.isEmpty) status = 'active';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Staff profile: $userName'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(
                    labelText: 'Position',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily rate (₱)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: halfDayMultiplierController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Half-day multiplier (e.g. 0.5)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => status = (v ?? 'active'),
                  decoration: const InputDecoration(
                    labelText: 'Status',
                  ),
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

    final nextPosition = positionController.text.trim();
    final nextDailyRate = _asDouble(rateController.text, fallback: 0);
    final nextHalfDayMultiplier = _asDouble(
      halfDayMultiplierController.text,
      fallback: _defaultHalfDayMultiplier,
    );

    positionController.dispose();
    rateController.dispose();
    halfDayMultiplierController.dispose();

    if (saved != true) return;

    await profileRef.set({
      'eateryId': eateryId,
      'uid': uid,
      'position': nextPosition,
      'dailyRate': nextDailyRate,
      'halfDayMultiplier': nextHalfDayMultiplier,
      'status': status,
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (profileSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Staff Management')),
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
            appBar: AppBar(title: const Text('Staff Management')),
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
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Staff Management'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Staff'),
                  Tab(text: 'Attendance'),
                  Tab(text: 'Payroll'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.subtract(const Duration(days: 7));
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
                      _weekStart = _weekStart.add(const Duration(days: 7));
                    });
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('eateryId', isEqualTo: eateryId)
                  .snapshots(),
              builder: (context, usersSnap) {
                if (usersSnap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load users: ${usersSnap.error}'),
                    ),
                  );
                }
                if (!usersSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userDocs = usersSnap.data!.docs;
                final usersByUid = <String, Map<String, dynamic>>{
                  for (final d in userDocs) d.id: d.data(),
                };

                return TabBarView(
                  children: [
                    _StaffTab(
                      eateryId: eateryId,
                      usersByUid: usersByUid,
                      globalSearchQuery: widget.globalSearchQuery,
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
                      onEncodeAttendance: (uid, label) => _encodeAttendance(
                        context,
                        eateryId: eateryId,
                        uid: uid,
                        userLabel: label,
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
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.eateryId,
    required this.usersByUid,
    required this.globalSearchQuery,
    required this.onEditProfile,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final ValueNotifier<String>? globalSearchQuery;
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

  bool _matches(String q, String text) {
    if (q.isEmpty) return true;
    return text.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = globalSearchQuery;
    if (notifier == null) {
      final q = '';

      final entries = usersByUid.entries.where((e) {
        final uid = e.key;
        final data = e.value;
        final email = (data['email'] ?? '').toString();
        final name = _displayName(data, uid);
        return _matches(q, uid) || _matches(q, email) || _matches(q, name);
      }).toList()
        ..sort((a, b) => _displayName(a.value, a.key)
            .toLowerCase()
            .compareTo(_displayName(b.value, b.key).toLowerCase()));

      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('staff_profiles')
            .where('eateryId', isEqualTo: eateryId)
            .snapshots(),
        builder: (context, profilesSnap) {
          final profileByUid = <String, Map<String, dynamic>>{};
          if (profilesSnap.hasData) {
            for (final d in profilesSnap.data!.docs) {
              final data = d.data();
              final uid = (data['uid'] ?? '').toString().trim();
              if (uid.isEmpty) continue;
              profileByUid[uid] = data;
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
                  onTap: () => onEditProfile(uid, userData),
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
                  trailing: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit),
                    onPressed: () => onEditProfile(uid, userData),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (context, query, _) {
        final q = query.trim().toLowerCase();

        final entries = usersByUid.entries.where((e) {
          final uid = e.key;
          final data = e.value;
          final email = (data['email'] ?? '').toString();
          final name = _displayName(data, uid);
          return _matches(q, uid) || _matches(q, email) || _matches(q, name);
        }).toList()
          ..sort((a, b) => _displayName(a.value, a.key)
              .toLowerCase()
              .compareTo(_displayName(b.value, b.key).toLowerCase()));

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('staff_profiles')
              .where('eateryId', isEqualTo: eateryId)
              .snapshots(),
          builder: (context, profilesSnap) {
            final profileByUid = <String, Map<String, dynamic>>{};
            if (profilesSnap.hasData) {
              for (final d in profilesSnap.data!.docs) {
                final data = d.data();
                final uid = (data['uid'] ?? '').toString().trim();
                if (uid.isEmpty) continue;
                profileByUid[uid] = data;
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
                    onTap: () => onEditProfile(uid, userData),
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
                    trailing: IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit),
                      onPressed: () => onEditProfile(uid, userData),
                    ),
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

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({
    required this.eateryId,
    required this.usersByUid,
    required this.weekStart,
    required this.onEncodeAttendance,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final DateTime weekStart;
  final Future<void> Function(String uid, String userLabel) onEncodeAttendance;

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
          .collection('staff_attendance')
          .where('eateryId', isEqualTo: eateryId)
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
        .collection('staff_profiles')
        .where('eateryId', isEqualTo: eateryId)
        .snapshots();

    final attendanceStream = FirebaseFirestore.instance
        .collection('staff_attendance')
        .where('eateryId', isEqualTo: eateryId)
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
        final halfMultByUid = <String, double>{};
        if (profSnap.hasData) {
          for (final d in profSnap.data!.docs) {
            final p = d.data();
            final uid = (p['uid'] ?? '').toString().trim();
            if (uid.isEmpty) continue;
            final raw = p['dailyRate'];
            final rate = raw is num ? raw.toDouble() : 0.0;
            rateByUid[uid] = rate;

            final rawHalf = p['halfDayMultiplier'];
            final half = rawHalf is num
                ? rawHalf.toDouble()
                : _StaffManagementScreenState._defaultHalfDayMultiplier;
            halfMultByUid[uid] = half;
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
                  final halfMult = halfMultByUid[uid] ??
                      _StaffManagementScreenState._defaultHalfDayMultiplier;

                  final gross =
                      (rate * fullDays) + (rate * halfMult * halfDays);
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
                    'halfMult': halfMult,
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
                      final halfMult = r['halfMult'] as double;
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
                            'Full: $fullDays · Half: $halfDays (x${halfMult.toStringAsFixed(2)})\n'
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
