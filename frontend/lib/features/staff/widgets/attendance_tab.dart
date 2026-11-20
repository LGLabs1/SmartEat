part of 'package:smarteat/screens/staff_management_screen.dart';

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab({
    required this.eateryId,
    required this.usersByUid,
    required this.onEncodeAttendance,
    required this.onMarkMissingAbsent,
  });

  final String eateryId;
  final Map<String, Map<String, dynamic>> usersByUid;
  final void Function(String uid, String label, DateTime day)
      onEncodeAttendance;
  final Future<int> Function(
    DateTime monthStart,
    Map<String, Map<String, dynamic>> existingAttendance,
  ) onMarkMissingAbsent;

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab>
    with AutomaticKeepAliveClientMixin {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Memoized per eatery+month so rebuilds reuse the same Firestore listener.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _attendanceStream;
  String _attendanceStreamKey = '';

  @override
  bool get wantKeepAlive => true;

  Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStreamFor(
    String eateryId,
    String startKey,
    String endKey,
  ) {
    final key = '$eateryId|$startKey|$endKey';
    if (_attendanceStream == null || _attendanceStreamKey != key) {
      _attendanceStreamKey = key;
      _attendanceStream = StaffService.attendanceStream(
        eateryId,
        startKey: startKey,
        endKey: endKey,
      );
    }
    return _attendanceStream!;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final monthStart = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final monthEnd = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final startKey = attendanceYmd(monthStart);
    final endKey = attendanceYmd(monthEnd);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _attendanceStreamFor(widget.eateryId, startKey, endKey),
      builder: (context, attSnap) {
        if (attSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load attendance: ${attSnap.error}'),
            ),
          );
        }

        final records = <Map<String, dynamic>>[];
        if (attSnap.hasData) {
          for (final doc in attSnap.data!.docs) {
            final data = doc.data();
            final uid = (data['uid'] ?? '').toString().trim();
            if (uid.isEmpty) continue;
            records.add({...data, 'uid': uid});
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: AdminAttendanceCalendar(
            records: records,
            usersByUid: widget.usersByUid,
            selectedMonth: _selectedMonth,
            isLoading: !attSnap.hasData,
            onMonthChanged: (month) {
              setState(() {
                _selectedMonth = DateTime(month.year, month.month);
              });
            },
            onEncodeAttendance: widget.onEncodeAttendance,
            onMarkMissingAbsent: widget.onMarkMissingAbsent,
          ),
        );
      },
    );
  }
}
