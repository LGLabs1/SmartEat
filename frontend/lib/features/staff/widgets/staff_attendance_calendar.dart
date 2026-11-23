import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../utils/attendance_utils.dart';
import '../../../widgets/skeleton_loaders.dart';

/// A responsive, month-based attendance calendar with an inline day panel.
///
/// The parent owns the selected month and the attendance fetch. This widget
/// owns only the selected day so tapping around the grid does not trigger a
/// network read.
class StaffAttendanceCalendar extends StatefulWidget {
  const StaffAttendanceCalendar({
    super.key,
    required this.records,
    required this.selectedMonth,
    required this.isLoading,
    required this.onMonthChanged,
    this.openShift,
  });

  final List<Map<String, dynamic>> records;
  final DateTime selectedMonth;
  final bool isLoading;
  final Map<String, dynamic>? openShift;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<StaffAttendanceCalendar> createState() =>
      _StaffAttendanceCalendarState();
}

class _StaffAttendanceCalendarState extends State<StaffAttendanceCalendar> {
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
    'Sun'
  ];
  static const _weekdayNarrow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  DateTime? _selectedDate;
  String _selectionMonthKey = '';
  bool _hasUserSelectedDate = false;

  @override
  void initState() {
    super.initState();
    _syncSelection(force: true);
  }

  @override
  void didUpdateWidget(covariant StaffAttendanceCalendar oldWidget) {
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
        widget.selectedMonth.year, widget.selectedMonth.month + offset);
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

  String _monthLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.year}';

  String _longDate(DateTime date) => '${_weekdayNames[date.weekday - 1]}, '
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

  Map<String, Map<String, dynamic>> _recordsByDate() {
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in widget.records) {
      final date = _recordDate(record);
      if (date == null) continue;
      byDate[attendanceYmd(date)] = record;
    }

    final active = widget.openShift;
    if (active != null && attendanceIsOpen(active)) {
      final date = _recordDate(active);
      if (date != null && _isInSelectedMonth(date)) {
        byDate.putIfAbsent(attendanceYmd(date), () => active);
      }
    }
    return byDate;
  }

  double _completedHours(Map<String, dynamic> record) {
    final rawHours = record['hoursWorked'];
    if (rawHours is num) return rawHours.toDouble();
    final duration =
        attendanceShiftDuration(record['timeIn'], record['timeOut']);
    return duration == null ? 0 : duration.inSeconds / 3600.0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byDate = _recordsByDate();
    final summary = attendanceMonthSummary(widget.records);
    final reviewCount = widget.records.where((record) {
      final status = attendanceRecordStatus(record);
      return record['needsReview'] == true ||
          status == attendanceIncomplete ||
          status == attendanceShort;
    }).length;

    final selectedDate = _selectedDate ??
        DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1);
    final selectedRecord = byDate[attendanceYmd(selectedDate)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 520;
        final showWeekTotals = constraints.maxWidth >= 700;

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
                _buildSummary(scheme, summary, reviewCount),
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _buildCalendar(
                          scheme,
                          byDate,
                          compact: false,
                          showWeekTotals: showWeekTotals,
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 320,
                        child: _buildDetail(
                          scheme,
                          selectedDate,
                          selectedRecord,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildCalendar(
                    scheme,
                    byDate,
                    compact: compact,
                    showWeekTotals: showWeekTotals,
                  ),
                  const SizedBox(height: 14),
                  _buildDetail(scheme, selectedDate, selectedRecord),
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
    ColorScheme scheme,
    ({int present, int half, int absent, double hours}) summary,
    int reviewCount,
  ) {
    final recorded = summary.present + summary.half + summary.absent;
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
                      'Hours this month',
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
                          formatAttendanceHours(summary.hours),
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
                            'worked',
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
                      '$recorded ${recorded == 1 ? 'day' : 'days'} recorded',
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
                  Icons.timelapse_rounded,
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
                label: 'Full days',
                value: '${summary.present}',
                icon: Icons.check_circle_outline,
                color: AppTheme.sageSuccess,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                label: 'Half days',
                value: '${summary.half}',
                icon: Icons.remove_circle_outline,
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                label: 'Absent',
                value: '${summary.absent}',
                icon: Icons.cancel_outlined,
                color: scheme.error,
              ),
            ),
          ],
        ),
        if (recorded > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (summary.present > 0)
                    Expanded(
                      flex: summary.present,
                      child: ColoredBox(color: AppTheme.sageSuccess),
                    ),
                  if (summary.half > 0)
                    Expanded(
                      flex: summary.half,
                      child: const ColoredBox(color: AppTheme.warning),
                    ),
                  if (summary.absent > 0)
                    Expanded(
                      flex: summary.absent,
                      child: ColoredBox(color: scheme.error),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (reviewCount > 0) ...[
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
            child: Row(
              children: [
                const Icon(
                  Icons.priority_high,
                  size: 16,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reviewCount == 1
                        ? '1 shift needs admin review'
                        : '$reviewCount shifts need admin review',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCalendar(
    ColorScheme scheme,
    Map<String, Map<String, dynamic>> byDate, {
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
    final cellHeight = compact ? 44.0 : 58.0;

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
              byDate: byDate,
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
                  'Select a day to see shift details.',
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
                'Week',
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
    required Map<String, Map<String, dynamic>> byDate,
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

    var weekHours = 0.0;
    for (final date in days) {
      if (date == null) continue;
      final record = byDate[attendanceYmd(date)];
      if (record == null || attendanceIsOpen(record)) continue;
      weekHours += _completedHours(record);
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
      final record = byDate[key];
      final isToday = key == todayKey;
      final isFuture =
          attendanceDateOnly(date).isAfter(attendanceDateOnly(DateTime.now()));
      final isSelected = _selectedDate != null &&
          attendanceDateOnly(_selectedDate!) == attendanceDateOnly(date);
      children.add(
        Expanded(
          child: _DayCell(
            date: date,
            record: record,
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
                  weekHours > 0 ? formatAttendanceHours(weekHours) : '—',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: weekHours > 0
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

  Widget _buildDetail(
    ColorScheme scheme,
    DateTime date,
    Map<String, dynamic>? record,
  ) {
    final today = attendanceDateOnly(DateTime.now());
    final isToday = attendanceDateOnly(date) == today;
    final isFuture = attendanceDateOnly(date).isAfter(today);
    final open = record != null && attendanceIsOpen(record);
    final status = record == null ? '' : attendanceRecordStatus(record);
    final style = _styleForRecord(record, scheme);
    final needsReview = record != null &&
        (record['needsReview'] == true ||
            status == attendanceIncomplete ||
            status == attendanceShort);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(attendanceYmd(date)),
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
                  label: isFuture
                      ? 'Upcoming'
                      : record == null
                          ? (isToday ? 'No shift yet' : 'No record')
                          : style.label,
                  color: style.color,
                  icon: isFuture ? Icons.schedule_outlined : style.icon,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (record == null)
              _buildMissingDetail(scheme, isToday: isToday, isFuture: isFuture)
            else
              _buildRecordDetail(
                scheme,
                record,
                open: open,
                status: status,
                needsReview: needsReview,
                color: style.color,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingDetail(
    ColorScheme scheme, {
    required bool isToday,
    required bool isFuture,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
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
                isFuture ? Icons.schedule_outlined : Icons.event_busy_outlined,
                size: 34,
                color: scheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 8),
              Text(
                isFuture
                    ? 'Nothing to show yet'
                    : isToday
                        ? 'No shift yet'
                        : 'No record for this day',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isFuture
                      ? 'This day has not happened yet.'
                      : isToday
                          ? 'Tap Time In on your shift clock when you start.'
                          : 'If you worked this day, ask your admin to encode it.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordDetail(
    ColorScheme scheme,
    Map<String, dynamic> record, {
    required bool open,
    required String status,
    required bool needsReview,
    required Color color,
  }) {
    final duration =
        attendanceShiftDuration(record['timeIn'], record['timeOut']);
    final liveDuration =
        open ? attendanceOpenShiftDuration(record['timeIn']) : null;
    final rawHours = record['hoursWorked'];
    final unit = record['workUnit'] is num
        ? (record['workUnit'] as num).toDouble()
        : 0.0;
    final lateMinutes = record['lateMinutes'] is num
        ? (record['lateMinutes'] as num).toInt()
        : 0;
    final legacy = attendanceLegacySummary(record);
    final notes = (record['notes'] ?? '').toString().trim();

    String headline;
    if (open && liveDuration != null) {
      headline = formatAttendanceDuration(liveDuration);
    } else if (duration != null) {
      headline = formatAttendanceDuration(duration);
    } else if (status == attendanceAbsent) {
      headline = 'Absent';
    } else if (status == attendanceIncomplete) {
      headline = 'Needs review';
    } else if (rawHours is num) {
      headline = formatAttendanceHours(rawHours.toDouble());
    } else {
      headline = '—';
    }

    String unitsLabel;
    if (unit >= 1) {
      unitsLabel = '1.0 · full day';
    } else if (unit > 0) {
      unitsLabel = '0.5 · half day';
    } else {
      unitsLabel = '0.0';
    }

    final timeIn = formatAttendanceClock(record['timeIn']);
    final timeOut = formatAttendanceClock(record['timeOut']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    open ? 'Live duration' : 'Hours worked',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                  ),
                ],
              ),
            ),
            if (open)
              _StatusPill(
                label: 'Live',
                color: scheme.primary,
                icon: Icons.play_arrow_rounded,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _TimelineRow(
          label: 'Time In',
          value: timeIn.isEmpty ? 'Not recorded' : timeIn,
          done: timeIn.isNotEmpty,
        ),
        _TimelineRow(
          label: 'Time Out',
          value: timeOut.isEmpty
              ? (open ? 'Still on shift' : 'Not recorded')
              : timeOut,
          done: timeOut.isNotEmpty,
          last: true,
        ),
        const SizedBox(height: 14),
        _DetailLine(
          icon: Icons.timelapse,
          label: 'Work unit',
          value: unitsLabel,
        ),
        if (lateMinutes > 0)
          _DetailLine(
            icon: Icons.alarm,
            label: 'Late',
            value: '$lateMinutes min',
          ),
        _DetailLine(
          icon: Icons.source_outlined,
          label: 'Recorded by',
          value: _sourceLabel(record['source']),
        ),
        if (legacy.isNotEmpty)
          _DetailLine(
            icon: Icons.history,
            label: 'Legacy check-ins',
            value: legacy,
          ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (needsReview) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.priority_high,
                  size: 16,
                  color: AppTheme.warning,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This shift needs admin review. Ask your admin to fix the missing details.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
                  width: 320,
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
}

({Color color, IconData? icon, String label}) _styleForRecord(
  Map<String, dynamic>? record,
  ColorScheme scheme,
) {
  if (record == null) {
    return (
      color: Colors.white.withValues(alpha: 0.5),
      icon: null,
      label: 'No record'
    );
  }

  final status = attendanceRecordStatus(record);
  final open = attendanceIsOpen(record);
  if (open || status == attendanceInProgress) {
    return (
      color: scheme.primary,
      icon: Icons.play_arrow_rounded,
      label: 'On shift',
    );
  }
  if (record['needsReview'] == true || status == attendanceIncomplete) {
    return (
      color: AppTheme.warning,
      icon: Icons.priority_high,
      label: 'Needs review',
    );
  }
  switch (status) {
    case attendancePresent:
      return (
        color: AppTheme.sageSuccess,
        icon: Icons.check,
        label: 'Full day',
      );
    case attendanceHalfDay:
      return (
        color: AppTheme.warning,
        icon: Icons.remove,
        label: 'Half day',
      );
    case attendanceShort:
      return (
        color: scheme.error,
        icon: Icons.error_outline,
        label: 'Under half day',
      );
    case attendanceAbsent:
    default:
      return (
        color: scheme.error,
        icon: Icons.close,
        label: 'Absent',
      );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.record,
    required this.isToday,
    required this.isFuture,
    required this.isSelected,
    required this.compact,
    required this.height,
    required this.onTap,
  });

  final DateTime date;
  final Map<String, dynamic>? record;
  final bool isToday;
  final bool isFuture;
  final bool isSelected;
  final bool compact;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _styleForRecord(record, scheme);
    final hasRecord = record != null;
    final open = record != null && attendanceIsOpen(record!);
    final status = record == null ? '' : attendanceRecordStatus(record!);
    final needsReview = record != null &&
        (record!['needsReview'] == true || status == attendanceIncomplete);

    final baseColor =
        hasRecord ? style.color : Colors.white.withValues(alpha: 0.5);
    final background = hasRecord
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
        : hasRecord
            ? baseColor
            : scheme.onSurface.withValues(alpha: 0.62);

    String caption = '';
    if (!isFuture && hasRecord) {
      if (open) {
        caption = 'LIVE';
      } else if (status == attendanceAbsent) {
        caption = 'Absent';
      } else if (needsReview) {
        caption = 'Review';
      } else {
        final hours = _recordHours(record!);
        caption = hours > 0
            ? formatAttendanceHours(hours)
            : attendanceStatusLabel(status);
      }
    } else if (!isFuture && isToday) {
      caption = 'Today';
    }

    return Semantics(
      button: onTap != null,
      label: '${_monthName(date.month)} ${date.day}, ${date.year}: '
          '${record == null ? 'no record' : style.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
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
                ] else if (compact && (hasRecord || isToday)) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isToday && !hasRecord
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

  double _recordHours(Map<String, dynamic> value) {
    final rawHours = value['hoursWorked'];
    if (rawHours is num) return rawHours.toDouble();
    final duration = attendanceShiftDuration(value['timeIn'], value['timeOut']);
    return duration == null ? 0 : duration.inSeconds / 3600.0;
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

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.value,
    required this.done,
    this.last = false,
  });

  final String label;
  final String value;
  final bool done;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        done ? AppTheme.sageSuccess : Colors.white.withValues(alpha: 0.5);
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: done ? color : scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: scheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
