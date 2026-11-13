part of 'package:smarteat/screens/staff_management_screen.dart';

class _AttendanceTab extends StatefulWidget {
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
  final Future<int> Function(
      Map<String, Map<String, dynamic>> existingAttendance) onAutoMarkAbsent;

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  // Memoized per eatery+week so rebuilds reuse the same Firestore listener.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _attendanceStream;
  String _attendanceStreamKey = '';

  Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStreamFor(
      String eateryId, String startKey, String endKey) {
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

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _displayName(Map<String, dynamic> data, String uid) =>
      staffDisplayName(data, uid);

  @override
  Widget build(BuildContext context) {
    final weekEnd = widget.weekStart.add(const Duration(days: 6));
    final startKey = _fmtDate(widget.weekStart);
    final endKey = _fmtDate(weekEnd);

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

        final uids = widget.usersByUid.entries
            .where((e) => !isAdminUser(e.value))
            .map((e) => e.key)
            .toList()
          ..sort();
        final days = List<DateTime>.generate(
          7,
          (i) => widget.weekStart.add(Duration(days: i)),
        );

        final today = DateTime.now();
        var missingCount = 0;
        for (final uid in uids) {
          for (final day in days) {
            if (!shouldAutoMarkAbsent(day: day, today: today)) continue;
            if (byUidDate.containsKey('$uid|${_fmtDate(day)}')) continue;
            missingCount++;
          }
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: uids.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Card(
                elevation: 0,
                color: Colors.blueGrey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blueGrey.shade100),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.event_busy, color: Colors.blueGrey.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          missingCount == 0
                              ? 'All past days are accounted for.'
                              : '$missingCount past ${missingCount == 1 ? 'day has' : 'days have'} no attendance record.',
                          style: TextStyle(color: Colors.blueGrey.shade900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: missingCount == 0
                            ? null
                            : () async {
                                final count =
                                    await widget.onAutoMarkAbsent(byUidDate);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(count == 0
                                        ? 'Nothing to mark'
                                        : 'Marked $count ${count == 1 ? 'day' : 'days'} absent'),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.done_all),
                        label: const Text('Mark missing absent'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final uid = uids[index - 1];
            final userData =
                widget.usersByUid[uid] ?? const <String, dynamic>{};
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
                          onPressed: () => widget.onEncodeAttendance(uid, label),
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
                          onTap: () => widget.onEncodeAttendance(uid, label),
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

