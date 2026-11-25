import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../utils/attendance_utils.dart';
import '../../../utils/staff_utils.dart';
import '../../../widgets/skeleton_loaders.dart';

class AdminAttendanceCalendar extends StatefulWidget {
  const AdminAttendanceCalendar({
    super.key,
    required this.records,
    required this.usersByUid,
    this.dailyRateByUid = const <String, double>{},
    this.halfDayRateByUid = const <String, double>{},
    required this.selectedMonth,
    required this.isLoading,
    required this.onMonthChanged,
    required this.onEncodeAttendance,
    required this.onMarkMissingAbsent,
  });

  final List<Map<String, dynamic>> records;
  final Map<String, Map<String, dynamic>> usersByUid;
  final Map<String, double> dailyRateByUid;
  final Map<String, double> halfDayRateByUid;
  final DateTime selectedMonth;
  final bool isLoading;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(String uid, String label, DateTime day)
      onEncodeAttendance;
  final Future<int> Function(
    DateTime monthStart,
    Map<String, Map<String, dynamic>> existingByUidDate,
  ) onMarkMissingAbsent;

  @override
  State<AdminAttendanceCalendar> createState() =>
      _AdminAttendanceCalendarState();
}

class _AdminAttendanceCalendarState extends State<AdminAttendanceCalendar> {
  static const _monthNames = [
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
    'December',
  ];
  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _weekdayShort = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _weekdayNarrow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  DateTime? _selectedDate;
  String _selectionMonthKey = '';
  bool _hasUserSelectedDate = false;
  bool _markingAbsent = false;

  @override
  void initState() {
    super.initState();
    _syncSelection(force: true);
  }

  @override
  void didUpdateWidget(covariant AdminAttendanceCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final monthChanged =
        oldWidget.selectedMonth.year != widget.selectedMonth.year ||
            oldWidget.selectedMonth.month != widget.selectedMonth.month;

    if (monthChanged) {
      _hasUserSelectedDate = false;
      _syncSelection(force: true);
      return;
    }

    if (oldWidget.records != widget.records && !_hasUserSelectedDate) {
      _syncSelection(force: true);
    }
  }

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool _isInSelectedMonth(DateTime date) =>
      date.year == widget.selectedMonth.year &&
      date.month == widget.selectedMonth.month;

  DateTime? _recordDate(Map<String, dynamic> record) {
    final rawDate = (record['date'] ?? '').toString().trim();
    if (rawDate.isNotEmpty) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) return attendanceDateOnly(parsed);
    }
    final timeIn = attendanceAsDateTime(record['timeIn']);
    return timeIn == null ? null : attendanceDateOnly(timeIn);
  }

  void _syncSelection({required bool force}) {
    final month = widget.selectedMonth;
    final monthKey = '${month.year}-${month.month}';

    if (!force &&
        monthKey == _selectionMonthKey &&
        _selectedDate != null &&
        _isInSelectedMonth(_selectedDate!)) {
      return;
    }

    _selectionMonthKey = monthKey;
    final now = DateTime.now();
    if (_sameMonth(month, now)) {
      _selectedDate = attendanceDateOnly(now);
      return;
    }

    DateTime? latest;
    for (final record in widget.records) {
      final date = _recordDate(record);
      if (date == null || !_isInSelectedMonth(date)) continue;
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    _selectedDate = latest ?? DateTime(month.year, month.month, 1);
  }

  void _goToMonth(int offset) {
    final target = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month + offset,
    );
    final now = DateTime.now();
    final canGoNext = widget.selectedMonth.year < now.year ||
        (widget.selectedMonth.year == now.year &&
            widget.selectedMonth.month < now.month);
    if (offset > 0 && !canGoNext) return;
    _hasUserSelectedDate = false;
    widget.onMonthChanged(target);
  }

  void _goToToday() {
    final now = attendanceDateOnly(DateTime.now());
    _hasUserSelectedDate = true;
    _selectedDate = now;
    _selectionMonthKey = '${now.year}-${now.month}';

    if (!_sameMonth(widget.selectedMonth, now)) {
      widget.onMonthChanged(DateTime(now.year, now.month));
    } else {
      setState(() {});
    }
  }

  void _selectDate(DateTime date) {
    if (!_isInSelectedMonth(date)) return;
    if (attendanceDateOnly(date).isAfter(attendanceDateOnly(DateTime.now()))) {
      return;
    }
    _hasUserSelectedDate = true;
    setState(() => _selectedDate = attendanceDateOnly(date));
  }

  Future<void> _markMissingAbsent(
    DateTime monthStart,
    Map<String, Map<String, dynamic>> existingByUidDate,
  ) async {
    if (_markingAbsent) return;
    setState(() => _markingAbsent = true);
    try {
      final count =
          await widget.onMarkMissingAbsent(monthStart, existingByUidDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nothing to mark'
                : 'Marked $count ${count == 1 ? 'day' : 'days'} absent',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _markingAbsent = false);
    }
  }

  String _monthLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.year}';

  String _shortDate(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.day}';

  String _longDate(DateTime date) => '${_weekdayNames[date.weekday - 1]}, '
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monthStart = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month,
      1,
    );
    final monthEnd = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month + 1,
      0,
    );
    final staffEntries = widget.usersByUid.entries
        .where((entry) => !isAdminUser(entry.value))
        .toList()
      ..sort((a, b) {
        final aName = staffDisplayName(a.value, a.key).toLowerCase();
        final bName = staffDisplayName(b.value, b.key).toLowerCase();
        return aName.compareTo(bName);
      });
    final staffUids = staffEntries.map((entry) => entry.key).toSet();

    final recordsByDate = <String, List<Map<String, dynamic>>>{};
    final byUidDate = <String, Map<String, dynamic>>{};
    for (final record in widget.records) {
      final uid = (record['uid'] ?? '').toString().trim();
      if (uid.isEmpty || !staffUids.contains(uid)) continue;
      final date = _recordDate(record);
      if (date == null || !_isInSelectedMonth(date)) continue;
      final dateKey = attendanceYmd(date);
      recordsByDate
          .putIfAbsent(dateKey, () => <Map<String, dynamic>>[])
          .add({...record, 'uid': uid});
      byUidDate['$uid|$dateKey'] = record;
    }

    final aggregates = <String, _DayAggregate>{
      for (final entry in recordsByDate.entries)
        entry.key: _aggregateFor(entry.value),
    };

    final selectedDate = _selectedDate ??
        DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1);
    final selectedKey = attendanceYmd(selectedDate);
    final selectedByUid = <String, Map<String, dynamic>>{
      for (final record
          in recordsByDate[selectedKey] ?? const <Map<String, dynamic>>[])
        (record['uid'] ?? '').toString(): record,
    };

    final onDuty = <_StaffAttendanceEntry>[];
    final notOnDuty = <_StaffAttendanceEntry>[];
    for (final entry in staffEntries) {
      final label = staffDisplayName(entry.value, entry.key);
      final record = selectedByUid[entry.key];
      final item = _StaffAttendanceEntry(
        uid: entry.key,
        label: label,
        record: record,
      );
      if (record != null && _isOnDuty(record)) {
        onDuty.add(item);
      } else {
        notOnDuty.add(item);
      }
    }

    final today = attendanceDateOnly(DateTime.now());
    var missingCount = 0;
    for (final uid in staffUids) {
      var day = monthStart;
      while (!day.isAfter(monthEnd)) {
        if (shouldAutoMarkAbsent(day: day, today: today) &&
            !byUidDate.containsKey('$uid|${attendanceYmd(day)}')) {
          missingCount++;
        }
        day = day.add(const Duration(days: 1));
      }
    }

    final monthRecordCount = recordsByDate.values.fold<int>(
      0,
      (total, records) => total + records.length,
    );
    final monthReviewCount = aggregates.values.fold<int>(
      0,
      (total, aggregate) => total + aggregate.needsReview,
    );
    final monthAbsentCount = aggregates.values.fold<int>(
      0,
      (total, aggregate) => total + aggregate.absent,
    );
    final monthRecords = recordsByDate.values.expand((list) => list).toList();
    final monthGross = attendanceGrossPay(
      records: monthRecords,
      dailyRateByUid: widget.dailyRateByUid,
      halfDayRateByUid: widget.halfDayRateByUid,
    );
    final selectedGross = attendanceGrossPay(
      records: recordsByDate[selectedKey] ?? const <Map<String, dynamic>>[],
      dailyRateByUid: widget.dailyRateByUid,
      halfDayRateByUid: widget.halfDayRateByUid,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 520;
        final showWeekTotals = constraints.maxWidth >= 760;

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(wide ? 20 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scheme),
              const SizedBox(height: 16),
              if (widget.isLoading)
                _buildLoadingState(wide, compact: compact)
              else ...[
                _buildSummary(
                  scheme,
                  selectedDate: selectedDate,
                  onDutyCount: onDuty.length,
                  monthRecordCount: monthRecordCount,
                  monthReviewCount: monthReviewCount,
                  monthAbsentCount: monthAbsentCount,
                  monthGross: monthGross,
                  missingCount: missingCount,
                  monthStart: monthStart,
                  existingByUidDate: byUidDate,
                  compact: compact,
                ),
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _buildCalendar(
                          scheme,
                          aggregates: aggregates,
                          compact: false,
                          showWeekTotals: showWeekTotals,
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 380,
                        child: _buildSelectedDayCard(
                          scheme,
                          selectedDate,
                          onDuty,
                          notOnDuty,
                          selectedGross: selectedGross,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildCalendar(
                    scheme,
                    aggregates: aggregates,
                    compact: compact,
                    showWeekTotals: showWeekTotals,
                  ),
                  const SizedBox(height: 14),
                  _buildSelectedDayCard(
                    scheme,
                    selectedDate,
                    onDuty,
                    notOnDuty,
                    selectedGross: selectedGross,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final now = DateTime.now();
    final isCurrentMonth = _sameMonth(widget.selectedMonth, now);
    final canGoNext = widget.selectedMonth.year < now.year ||
        (widget.selectedMonth.year == now.year &&
            widget.selectedMonth.month < now.month);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.calendar_month_rounded,
            color: scheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                _monthLabel(widget.selectedMonth),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavButton(
                icon: Icons.chevron_left,
                tooltip: 'Previous month',
                onPressed: () => _goToMonth(-1),
              ),
              TextButton(
                onPressed: _goToToday,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor:
                      isCurrentMonth ? scheme.primary : scheme.onSurface,
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              _NavButton(
                icon: Icons.chevron_right,
                tooltip: 'Next month',
                onPressed: canGoNext ? () => _goToMonth(1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(
    ColorScheme scheme, {
    required DateTime selectedDate,
    required int onDutyCount,
    required int monthRecordCount,
    required int monthReviewCount,
    required int monthAbsentCount,
    required double monthGross,
    required int missingCount,
    required DateTime monthStart,
    required Map<String, Map<String, dynamic>> existingByUidDate,
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary.withValues(alpha: 0.1),
                AppTheme.secondary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On duty · ${_shortDate(selectedDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$onDutyCount',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 30,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            onDutyCount == 1 ? 'staff member' : 'staff members',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.55),
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$monthRecordCount ${monthRecordCount == 1 ? 'record' : 'records'} this month',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  color: scheme.primary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Records',
                value: '$monthRecordCount',
                icon: Icons.fact_check_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                label: 'Needs review',
                value: '$monthReviewCount',
                icon: Icons.priority_high,
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                label: 'Absent',
                value: '$monthAbsentCount',
                icon: Icons.cancel_outlined,
                color: scheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.sageSuccess.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.sageSuccess.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 17,
                color: AppTheme.sageSuccess,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimated monthly gross',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.sageSuccess,
                      ),
                ),
              ),
              Text(
                '₱${monthGross.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.sageSuccess,
                ),
              ),
            ],
          ),
        ),
        if (missingCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.2),
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.event_busy,
                            size: 16,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$missingCount past ${missingCount == 1 ? 'day has' : 'days have'} no attendance record.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        key: const Key('admin-attendance-mark-missing'),
                        onPressed: _markingAbsent
                            ? null
                            : () => _markMissingAbsent(
                                  monthStart,
                                  existingByUidDate,
                                ),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Mark missing absent'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.event_busy,
                        size: 16,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$missingCount past ${missingCount == 1 ? 'day has' : 'days have'} no attendance record.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        key: const Key('admin-attendance-mark-missing'),
                        onPressed: _markingAbsent
                            ? null
                            : () => _markMissingAbsent(
                                  monthStart,
                                  existingByUidDate,
                                ),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Mark missing absent'),
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildCalendar(
    ColorScheme scheme, {
    required Map<String, _DayAggregate> aggregates,
    required bool compact,
    required bool showWeekTotals,
  }) {
    final firstDay = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month,
      1,
    );
    final daysInMonth =
        DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 0)
            .day;
    final leading = firstDay.weekday - 1;
    final totalSlots = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final weeks = totalSlots ~/ 7;
    final now = DateTime.now();
    final todayKey = attendanceYmd(now);
    final cellHeight = compact ? 48.0 : 62.0;

    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          _buildWeekdayHeader(
            scheme,
            compact: compact,
            showWeekTotals: showWeekTotals,
          ),
          const SizedBox(height: 6),
          for (var week = 0; week < weeks; week++) ...[
            if (week > 0) const SizedBox(height: 4),
            _buildWeekRow(
              scheme,
              week: week,
              leading: leading,
              daysInMonth: daysInMonth,
              aggregates: aggregates,
              todayKey: todayKey,
              cellHeight: cellHeight,
              compact: compact,
              showWeekTotals: showWeekTotals,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 14,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Select a day to see who is on duty.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader(
    ColorScheme scheme, {
    required bool compact,
    required bool showWeekTotals,
  }) {
    final labels = compact ? _weekdayNarrow : _weekdayShort;
    final children = <Widget>[];
    for (var index = 0; index < 7; index++) {
      if (index > 0) children.add(const SizedBox(width: 4));
      children.add(
        Expanded(
          child: Center(
            child: Text(
              labels[index],
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      );
    }
    if (showWeekTotals) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          SizedBox(
            width: 54,
            child: Center(
              child: Text(
                'Duty',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        );
    }
    return Row(children: children);
  }

  Widget _buildWeekRow(
    ColorScheme scheme, {
    required int week,
    required int leading,
    required int daysInMonth,
    required Map<String, _DayAggregate> aggregates,
    required String todayKey,
    required double cellHeight,
    required bool compact,
    required bool showWeekTotals,
  }) {
    final startIndex = week * 7;
    final days = List<DateTime?>.generate(7, (index) {
      final slot = startIndex + index;
      if (slot < leading || slot >= leading + daysInMonth) return null;
      return DateTime(
        widget.selectedMonth.year,
        widget.selectedMonth.month,
        slot - leading + 1,
      );
    });

    var weekDuty = 0;
    for (final date in days) {
      if (date == null) continue;
      final aggregate = aggregates[attendanceYmd(date)];
      if (aggregate != null) weekDuty += aggregate.onDuty;
    }

    final children = <Widget>[];
    for (var index = 0; index < days.length; index++) {
      if (index > 0) children.add(const SizedBox(width: 4));
      final date = days[index];
      if (date == null) {
        children.add(
          Expanded(
            child: SizedBox(height: cellHeight),
          ),
        );
        continue;
      }
      final key = attendanceYmd(date);
      final aggregate = aggregates[key];
      final isToday = key == todayKey;
      final isFuture =
          attendanceDateOnly(date).isAfter(attendanceDateOnly(DateTime.now()));
      final isSelected = _selectedDate != null &&
          attendanceDateOnly(_selectedDate!) == attendanceDateOnly(date);
      children.add(
        Expanded(
          child: _DayCell(
            date: date,
            aggregate: aggregate,
            isToday: isToday,
            isFuture: isFuture,
            isSelected: isSelected,
            compact: compact,
            height: cellHeight,
            onTap: isFuture ? null : () => _selectDate(date),
          ),
        ),
      );
    }

    if (showWeekTotals) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          SizedBox(
            width: 54,
            height: cellHeight,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  weekDuty > 0 ? '$weekDuty' : '—',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: weekDuty > 0
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.35),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        );
    }

    return Row(children: children);
  }

  Widget _buildSelectedDayCard(
    ColorScheme scheme,
    DateTime date,
    List<_StaffAttendanceEntry> onDuty,
    List<_StaffAttendanceEntry> notOnDuty, {
    required double selectedGross,
  }) {
    final today = attendanceDateOnly(DateTime.now());
    final isToday = attendanceDateOnly(date) == today;
    final isFuture = attendanceDateOnly(date).isAfter(today);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: const Key('admin-attendance-selected-day'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _longDate(date),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isFuture
                            ? 'Upcoming day'
                            : isToday
                                ? 'Today'
                                : 'Attendance details',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  label: '${onDuty.length} on duty',
                  color: onDuty.isEmpty
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppTheme.sageSuccess,
                  icon: Icons.groups_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gross for selected day',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                    ),
                  ),
                  Text(
                    '₱${selectedGross.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (isFuture)
              _buildEmptyState(
                scheme,
                icon: Icons.schedule_outlined,
                title: 'Nothing to show yet',
                message: 'This day has not happened yet.',
              )
            else if (onDuty.isEmpty)
              _buildEmptyState(
                scheme,
                icon: Icons.group_off_outlined,
                title: 'No staff on duty',
                message: 'No on-duty attendance records for this day.',
              )
            else
              ...onDuty.map(
                (entry) => _StaffAttendanceRow(
                  key: ValueKey('admin-attendance-on-duty-${entry.uid}'),
                  entry: entry,
                  onEncode: () => widget.onEncodeAttendance(
                    entry.uid,
                    entry.label,
                    date,
                  ),
                ),
              ),
            if (notOnDuty.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.16),
                  ),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    key: ValueKey(
                      'admin-attendance-not-on-duty-${attendanceYmd(date)}',
                    ),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    title: Text(
                      'Absent / No record (${notOnDuty.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Tap a staff member to encode attendance.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                    ),
                    children: notOnDuty
                        .map(
                          (entry) => _StaffAttendanceRow(
                            key: ValueKey(
                              'admin-attendance-off-duty-${entry.uid}',
                            ),
                            entry: entry,
                            muted: true,
                            onEncode: () => widget.onEncodeAttendance(
                              entry.uid,
                              entry.label,
                              date,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 34,
            color: scheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool wide, {required bool compact}) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Loading attendance summary',
            child: SkeletonBlock(
              height: 92,
              borderRadius: 16,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SkeletonCircle(diameter: 40),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SkeletonLine(width: 120, height: 12),
                        SizedBox(height: 8),
                        SkeletonLine(width: 88, height: 24),
                      ],
                    ),
                  ),
                  if (!compact) const SkeletonLine(width: 46, height: 46),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: SkeletonBlock(height: 58)),
              const SizedBox(width: 8),
              const Expanded(child: SkeletonBlock(height: 58)),
              const SizedBox(width: 8),
              const Expanded(child: SkeletonBlock(height: 58)),
            ],
          ),
          const SizedBox(height: 16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  flex: 7,
                  child: SkeletonBlock(height: 330, borderRadius: 16),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 380,
                  child: SkeletonBlock(height: 330, borderRadius: 16),
                ),
              ],
            )
          else ...[
            const SkeletonBlock(height: 330, borderRadius: 16),
            const SizedBox(height: 14),
            const SkeletonBlock(height: 230, borderRadius: 16),
          ],
        ],
      ),
    );
  }
}

class _StaffAttendanceEntry {
  const _StaffAttendanceEntry({
    required this.uid,
    required this.label,
    this.record,
  });

  final String uid;
  final String label;
  final Map<String, dynamic>? record;
}

class _DayAggregate {
  const _DayAggregate({
    required this.onDuty,
    required this.absent,
    required this.needsReview,
    required this.hasOpen,
    required this.records,
  });

  final int onDuty;
  final int absent;
  final int needsReview;
  final bool hasOpen;
  final int records;

  bool get hasRecords => records > 0;
}

class _StatusVisual {
  const _StatusVisual({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

_DayAggregate _aggregateFor(List<Map<String, dynamic>> records) {
  var onDuty = 0;
  var absent = 0;
  var needsReview = 0;
  var hasOpen = false;

  for (final record in records) {
    if (attendanceIsOpen(record)) hasOpen = true;
    if (_isOnDuty(record)) {
      onDuty++;
    } else {
      absent++;
    }
    if (_needsReview(record)) needsReview++;
  }

  return _DayAggregate(
    onDuty: onDuty,
    absent: absent,
    needsReview: needsReview,
    hasOpen: hasOpen,
    records: records.length,
  );
}

bool _isOnDuty(Map<String, dynamic> record) {
  if (attendanceIsOpen(record)) return true;
  return attendanceRecordStatus(record) != attendanceAbsent;
}

bool _needsReview(Map<String, dynamic> record) {
  final status = attendanceRecordStatus(record);
  return record['needsReview'] == true ||
      status == attendanceIncomplete ||
      status == attendanceShort;
}

double _recordHours(Map<String, dynamic> record) {
  final rawHours = record['hoursWorked'];
  if (rawHours is num) return rawHours.toDouble();
  final duration = attendanceShiftDuration(record['timeIn'], record['timeOut']);
  return duration == null ? 0 : duration.inSeconds / 3600.0;
}

_StatusVisual _statusVisual(
  Map<String, dynamic>? record,
  ColorScheme scheme,
) {
  if (record == null) {
    return _StatusVisual(
      label: 'No record',
      color: Colors.white.withValues(alpha: 0.5),
      icon: Icons.remove_circle_outline,
    );
  }

  final status = attendanceRecordStatus(record);
  if (attendanceIsOpen(record)) {
    return _StatusVisual(
      label: 'On shift',
      color: scheme.primary,
      icon: Icons.play_arrow_rounded,
    );
  }
  if (_needsReview(record)) {
    return const _StatusVisual(
      label: 'Needs review',
      color: AppTheme.warning,
      icon: Icons.priority_high,
    );
  }
  switch (status) {
    case attendancePresent:
      return const _StatusVisual(
        label: 'Full day',
        color: AppTheme.sageSuccess,
        icon: Icons.check,
      );
    case attendanceHalfDay:
      return const _StatusVisual(
        label: 'Half day',
        color: AppTheme.warning,
        icon: Icons.remove,
      );
    case attendanceShort:
      return _StatusVisual(
        label: 'Under half day',
        color: scheme.error,
        icon: Icons.error_outline,
      );
    case attendanceAbsent:
    default:
      return _StatusVisual(
        label: 'Absent',
        color: scheme.error,
        icon: Icons.close,
      );
  }
}

String _sourceLabel(dynamic source) {
  switch ((source ?? '').toString().toLowerCase()) {
    case 'self':
      return 'Staff clock';
    case 'admin':
      return 'Admin encoded';
    case 'cron':
      return 'Automated';
    default:
      return 'Recorded';
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.aggregate,
    required this.isToday,
    required this.isFuture,
    required this.isSelected,
    required this.compact,
    required this.height,
    required this.onTap,
  });

  final DateTime date;
  final _DayAggregate? aggregate;
  final bool isToday;
  final bool isFuture;
  final bool isSelected;
  final bool compact;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = aggregate;
    final hasRecords = value?.hasRecords ?? false;
    final baseColor = value == null
        ? Colors.white.withValues(alpha: 0.5)
        : value.hasOpen
            ? scheme.primary
            : value.needsReview > 0
                ? AppTheme.warning
                : value.onDuty > 0
                    ? AppTheme.sageSuccess
                    : scheme.error;
    final background = hasRecords
        ? baseColor.withValues(alpha: isSelected ? 0.2 : 0.09)
        : (isToday
            ? scheme.primary.withValues(alpha: 0.07)
            : scheme.surface.withValues(alpha: 0.65));
    final borderColor = isSelected
        ? baseColor
        : isToday
            ? scheme.primary.withValues(alpha: 0.5)
            : scheme.outline.withValues(alpha: 0.22);
    final foreground = isFuture
        ? scheme.onSurface.withValues(alpha: 0.3)
        : hasRecords
            ? baseColor
            : scheme.onSurface.withValues(alpha: 0.62);

    final caption = _caption(value, isFuture: isFuture, isToday: isToday);

    return Semantics(
      button: onTap != null,
      label: '${_monthName(date.month)} ${date.day}, ${date.year}: '
          '${_semanticsLabel(value)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('admin-attendance-day-${attendanceYmd(date)}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 12 : 13,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                if (!compact && caption.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        caption,
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ] else if (compact && (hasRecords || isToday)) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isToday && !hasRecords
                          ? scheme.primary.withValues(alpha: 0.6)
                          : baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _caption(
    _DayAggregate? value, {
    required bool isFuture,
    required bool isToday,
  }) {
    if (isFuture || value == null) {
      return !isFuture && isToday ? 'Today' : '';
    }
    if (value.onDuty > 0) {
      return value.onDuty == 1 ? '1 on duty' : '${value.onDuty} on duty';
    }
    if (value.absent > 0) return 'Absent';
    return '';
  }

  String _semanticsLabel(_DayAggregate? value) {
    if (value == null || !value.hasRecords) return 'no records';
    final parts = <String>[
      '${value.onDuty} on duty',
      if (value.absent > 0) '${value.absent} absent',
      if (value.needsReview > 0) '${value.needsReview} needs review',
    ];
    return parts.join(', ');
  }

  String _monthName(int month) => const [
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
        'December',
      ][month - 1];
}

class _StaffAttendanceRow extends StatelessWidget {
  const _StaffAttendanceRow({
    super.key,
    required this.entry,
    required this.onEncode,
    this.muted = false,
  });

  final _StaffAttendanceEntry entry;
  final VoidCallback onEncode;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final record = entry.record;
    final visual = _statusVisual(record, scheme);
    final avatarColor = muted ? scheme.outline : visual.color;

    return InkWell(
      onTap: onEncode,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: avatarColor.withValues(alpha: 0.12),
              child: Text(
                staffInitials(entry.label),
                style: TextStyle(
                  color: avatarColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: muted
                          ? scheme.onSurface.withValues(alpha: 0.72)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(record),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusPill(
                  label: visual.label,
                  color: visual.color,
                  icon: visual.icon,
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.edit_calendar_outlined,
                  size: 16,
                  color: scheme.primary.withValues(alpha: 0.8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(Map<String, dynamic>? record) {
    if (record == null) return 'No attendance record';
    if (attendanceIsOpen(record)) {
      final timeIn = formatAttendanceClock(record['timeIn']);
      final duration = formatAttendanceDuration(
        attendanceOpenShiftDuration(record['timeIn']),
      );
      return 'In $timeIn · $duration so far';
    }
    if (attendanceRecordStatus(record) == attendanceAbsent) {
      return 'Marked absent · ${_sourceLabel(record['source'])}';
    }

    final timeIn = formatAttendanceClock(record['timeIn']);
    final timeOut = formatAttendanceClock(record['timeOut']);
    final hours = formatAttendanceHours(_recordHours(record));
    final times = <String>[
      if (timeIn.isNotEmpty) 'In $timeIn',
      if (timeOut.isNotEmpty) 'Out $timeOut',
    ];
    return [
      if (times.isNotEmpty) times.join(' · '),
      if (hours != '0h') hours,
      _sourceLabel(record['source']),
    ].join(' · ');
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 19,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.58),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
