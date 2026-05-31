import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/firebase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _eateryData;
  bool _isLoading = true;
  bool _isEditing = false;

  // Attendance tracking
  List<Map<String, dynamic>> _attendanceRecords = [];
  Map<String, dynamic>? _todayAttendance;
  bool _isLoadingAttendance = false;
  DateTime _selectedMonth = DateTime.now();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _positionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadAttendance() async {
    final eateryId = _profile?['eateryId']?.toString();
    final uid = _profile?['uid']?.toString();

    if (eateryId == null || eateryId.isEmpty || uid == null || uid.isEmpty) {
      return;
    }

    setState(() => _isLoadingAttendance = true);

    try {
      // Load monthly attendance
      final records = await FirebaseService.getStaffAttendanceForMonth(
        eateryId: eateryId,
        uid: uid,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );

      // Load today's attendance
      final today = await FirebaseService.getTodayAttendance(
        eateryId: eateryId,
        uid: uid,
      );

      if (mounted) {
        setState(() {
          _attendanceRecords = records;
          _todayAttendance = today;
          _isLoadingAttendance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAttendance = false);
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      final eateryId = profile?['eateryId']?.toString();

      // Add uid to profile if not present
      final user = context.read<AuthProvider>().user;
      final profileWithUid = profile != null
          ? {...profile, 'uid': user?.uid ?? profile['uid'] ?? ''}
          : null;

      Map<String, dynamic>? eateryData;
      if (eateryId != null && eateryId.isNotEmpty) {
        try {
          eateryData = await FirebaseService.getEatery(eateryId);
        } catch (_) {
          eateryData = null;
        }
      }

      if (mounted) {
        setState(() {
          _profile = profileWithUid;
          _eateryData = eateryData;
          _isLoading = false;
          _updateControllers();
        });
        // Load attendance after profile is loaded
        await _loadAttendance();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e')),
        );
      }
    }
  }

  void _updateControllers() {
    _firstNameController.text = _profile?['firstName']?.toString() ?? '';
    _lastNameController.text = _profile?['lastName']?.toString() ?? '';
    _phoneController.text = _profile?['phone']?.toString() ?? '';
    _positionController.text = _profile?['position']?.toString() ?? '';
  }

  Future<void> _saveProfile() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final role = _profile?['role']?.toString() ?? 'staff';
      final eateryId = _profile?['eateryId']?.toString();

      final updateData = <String, dynamic>{
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'position': _positionController.text.trim(),
      };

      // Update in appropriate collection based on role
      if (role == 'admin' && eateryId != null) {
        // Update in eatery's admin_profiles
        await FirebaseService.updateAdminProfileInEatery(
            eateryId, uid, updateData);
      } else if (eateryId != null) {
        // Update in eatery's staff_profiles
        await FirebaseService.updateStaffProfileInEatery(
            eateryId, uid, updateData);
      }

      // Also update in users collection
      await FirebaseService.updateUser(uid, updateData);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isLoading = false;
        });
        _loadProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final email = _profile?['email']?.toString();
    if (email == null || email.isEmpty) return;

    try {
      await FirebaseService.sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent. Check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reset email: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // ignore: use_build_context_synchronously
      await context.read<AuthProvider>().logout();
      // Navigate to root (login screen) and clear all routes
      if (context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  String get _fullName {
    final first = _profile?['firstName']?.toString() ?? '';
    final last = _profile?['lastName']?.toString() ?? '';
    if (first.isEmpty && last.isEmpty) return 'No Name';
    return '$first $last'.trim();
  }

  String get _roleDisplay {
    final role = _profile?['role']?.toString() ?? 'staff';
    final isAdmin = role == 'admin' || (_profile?['isAdmin'] == true);
    if (isAdmin) return 'Administrator';
    return 'Staff Member';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(_isEditing ? Icons.save : Icons.edit),
              onPressed: () {
                if (_isEditing) {
                  _saveProfile();
                } else {
                  setState(() => _isEditing = true);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 24),
          _buildAttendanceCard(),
          const SizedBox(height: 24),
          _buildAttendanceCalendar(),
          const SizedBox(height: 24),
          _buildProfileDetails(),
          const SizedBox(height: 24),
          _buildEateryInfo(),
          const SizedBox(height: 24),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    final eateryId = _profile?['eateryId']?.toString();
    final uid = _profile?['uid']?.toString();

    if (eateryId == null || eateryId.isEmpty || uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasMorningCheckIn = _todayAttendance?['morningCheckIn'] != null;
    final hasAfternoonCheckIn = _todayAttendance?['afternoonCheckIn'] != null;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (hasMorningCheckIn && hasAfternoonCheckIn) {
      statusText = 'Present (Full Day)';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (hasMorningCheckIn || hasAfternoonCheckIn) {
      statusText = 'Half Day';
      statusColor = Colors.orange;
      statusIcon = Icons.timelapse;
    } else {
      statusText = 'Not Checked In';
      statusColor = Colors.grey;
      statusIcon = Icons.schedule;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Today\'s Attendance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCheckInButton(
                    label: 'Morning Check-In',
                    icon: Icons.wb_sunny,
                    isCheckedIn: hasMorningCheckIn,
                    canCheckIn: _canCheckInMorning(),
                    onPressed: hasMorningCheckIn
                        ? null
                        : () => _recordCheckIn('morning'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCheckInButton(
                    label: 'Afternoon Check-In',
                    icon: Icons.wb_twilight,
                    isCheckedIn: hasAfternoonCheckIn,
                    canCheckIn: _canCheckInAfternoon(),
                    onPressed: hasAfternoonCheckIn
                        ? null
                        : () => _recordCheckIn('afternoon'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Morning: 12am-11:59am | Afternoon: 12pm-11:59pm. Both = Full Day, One = Half Day, None = Absent.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canCheckInMorning() {
    final now = DateTime.now();
    final hour = now.hour;
    return hour >= 0 && hour < 12; // 12am to 11:59am
  }

  bool _canCheckInAfternoon() {
    final now = DateTime.now();
    final hour = now.hour;
    return hour >= 12 && hour < 24; // 12pm to 11:59pm
  }

  Widget _buildCheckInButton({
    required String label,
    required IconData icon,
    required bool isCheckedIn,
    required bool canCheckIn,
    required VoidCallback? onPressed,
  }) {
    final color =
        isCheckedIn ? Colors.green : (canCheckIn ? Colors.blue : Colors.grey);
    return ElevatedButton.icon(
      onPressed: canCheckIn ? onPressed : null,
      icon: Icon(
        isCheckedIn ? Icons.check : icon,
        color: isCheckedIn || !canCheckIn ? Colors.white : null,
        size: 18,
      ),
      label: Text(
        isCheckedIn ? 'Checked In' : label,
        style: const TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isCheckedIn ? color : (canCheckIn ? null : Colors.grey.shade300),
        foregroundColor: isCheckedIn || !canCheckIn ? Colors.white : null,
        minimumSize: const Size(double.infinity, 40),
        disabledBackgroundColor: color.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Future<void> _recordCheckIn(String checkInType) async {
    final eateryId = _profile?['eateryId']?.toString();
    final uid = _profile?['uid']?.toString();

    if (eateryId == null || uid == null) return;

    try {
      await FirebaseService.recordAttendanceCheckIn(
        eateryId: eateryId,
        uid: uid,
        checkInType: checkInType,
      );

      // Refresh attendance data
      await _loadAttendance();

      if (mounted) {
        final message = checkInType == 'morning'
            ? 'Morning check-in recorded!'
            : 'Afternoon check-in recorded!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record check-in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAttendanceCalendar() {
    final eateryId = _profile?['eateryId']?.toString();
    final uid = _profile?['uid']?.toString();

    if (eateryId == null || eateryId.isEmpty || uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }

    // Build a map of date -> attendance for quick lookup
    final attendanceByDate = <String, Map<String, dynamic>>{};
    for (final record in _attendanceRecords) {
      final date = record['date']?.toString();
      if (date != null) {
        attendanceByDate[date] = record;
      }
    }

    // Get calendar days
    final firstDayOfMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // Calculate starting weekday (0 = Monday, 6 = Sunday)
    var firstWeekday = firstDayOfMonth.weekday - 1; // 0 = Monday

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Attendance Calendar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month - 1,
                          );
                        });
                        _loadAttendance();
                      },
                    ),
                    Text(
                      '${_monthName(_selectedMonth.month)} ${_selectedMonth.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month + 1,
                          );
                        });
                        _loadAttendance();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildLegendItem(Colors.green, 'Present'),
                _buildLegendItem(Colors.orange, 'Half Day'),
                _buildLegendItem(Colors.red, 'Absent'),
                _buildLegendItem(Colors.grey.shade300, 'Upcoming'),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingAttendance)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Weekday headers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Mon',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Tue',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Wed',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Thu',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Fri',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Sat',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  Text('Sun',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),
              // Calendar grid - 50% smaller
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.8,
                ),
                itemCount: daysInMonth + firstWeekday,
                itemBuilder: (context, index) {
                  if (index < firstWeekday) {
                    return const SizedBox.shrink(); // Empty cell
                  }

                  final day = index - firstWeekday + 1;
                  final date =
                      DateTime(_selectedMonth.year, _selectedMonth.month, day);
                  final dateKey =
                      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

                  final isToday = date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final isFuture = date.isAfter(today);

                  Color dayColor;
                  IconData? dayIcon;

                  if (isFuture) {
                    dayColor = Colors.grey.shade300;
                    dayIcon = null;
                  } else {
                    final attendance = attendanceByDate[dateKey];
                    if (attendance == null) {
                      // No record = absent (will be auto-marked by cron)
                      dayColor = Colors.red;
                      dayIcon = Icons.close;
                    } else {
                      final status = attendance['status']?.toString();
                      final present = attendance['present'] == true;
                      final workUnit = attendance['workUnit'] as num?;

                      if (status == 'present' || (present && workUnit == 1.0)) {
                        dayColor = Colors.green;
                        dayIcon = Icons.check;
                      } else if (status == 'halfday' || workUnit == 0.5) {
                        dayColor = Colors.orange;
                        dayIcon = Icons.timelapse;
                      } else if (!present || workUnit == 0.0) {
                        dayColor = Colors.red;
                        dayIcon = Icons.close;
                      } else {
                        dayColor = Colors.grey.shade300;
                        dayIcon = null;
                      }
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color:
                          isToday ? dayColor.withValues(alpha: 0.3) : dayColor,
                      borderRadius: BorderRadius.circular(4),
                      border: isToday
                          ? Border.all(color: dayColor, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.normal,
                              color: isFuture
                                  ? Colors.grey.shade600
                                  : Colors.white,
                            ),
                          ),
                          if (dayIcon != null && !isFuture)
                            Icon(
                              dayIcon,
                              size: 8,
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  Widget _buildProfileHeader() {
    final initial = _fullName.isNotEmpty ? _fullName[0].toUpperCase() : '?';
    final roleColor =
        _profile?['role']?.toString() == 'admin' ? Colors.blue : Colors.green;

    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: roleColor,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _fullName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: roleColor.withOpacity(0.3)),
            ),
            child: Text(
              _roleDisplay,
              style: TextStyle(
                color: roleColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _profile?['email']?.toString() ?? 'No email',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_isEditing) ...[
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '+63 xxx xxx xxxx',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _positionController,
                decoration: const InputDecoration(
                  labelText: 'Position',
                  prefixIcon: Icon(Icons.work_outline),
                  hintText: 'e.g., Cashier, Cook, Manager',
                ),
              ),
            ] else ...[
              _buildInfoRow(Icons.person, 'First Name',
                  _profile?['firstName']?.toString() ?? 'Not set'),
              _buildInfoRow(Icons.person, 'Last Name',
                  _profile?['lastName']?.toString() ?? 'Not set'),
              _buildInfoRow(Icons.phone, 'Phone',
                  _profile?['phone']?.toString() ?? 'Not set'),
              _buildInfoRow(Icons.work, 'Position',
                  _profile?['position']?.toString() ?? 'Not set'),
              _buildInfoRow(Icons.calendar_today, 'Joined',
                  _formatDate(_profile?['createdAt'])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEateryInfo() {
    if (_eateryData == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Eatery Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              Icons.store,
              'Eatery Name',
              _eateryData?['name']?.toString() ?? 'Unknown',
            ),
            _buildInfoRow(
              Icons.location_on,
              'Address',
              _eateryData?['address']?.toString() ?? 'Not set',
            ),
            _buildInfoRow(
              Icons.calendar_today,
              'Established',
              _formatDate(_eateryData?['createdAt']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _changePassword,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Change Password'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
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

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      DateTime date;
      if (timestamp is DateTime) {
        date = timestamp;
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Unknown';
      }
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }
}
