import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/finance/data/report_period.dart';
import 'month_selector.dart';

enum _DateRangeAction { thisMonth, last7Days, last30Days, month, custom, clear }

class DateRangeSelector extends StatelessWidget {
  const DateRangeSelector({
    super.key,
    required this.range,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.showMonthQuickSelect = true,
  });

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool showMonthQuickSelect;

  String _label(DateTimeRange? value) {
    if (value == null) return 'Date range';
    final format = DateFormat('MMM d');
    return '${format.format(value.start)} → ${format.format(value.end)}';
  }

  Future<void> _handleAction(
    BuildContext context,
    _DateRangeAction action,
  ) async {
    final now = DateTime.now();
    switch (action) {
      case _DateRangeAction.thisMonth:
        onChanged(ReportPeriod.monthRange(now));
        return;
      case _DateRangeAction.last7Days:
        onChanged(DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 6),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        ));
        return;
      case _DateRangeAction.last30Days:
        onChanged(DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 29),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        ));
        return;
      case _DateRangeAction.month:
        final month = await MonthSelector.pickMonth(
          context,
          initialMonth: range?.start ?? DateTime(now.year, now.month, 1),
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (month != null) onChanged(ReportPeriod.monthRange(month));
        return;
      case _DateRangeAction.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime(2100),
          initialDateRange: range ??
              DateTimeRange(
                start: DateTime(now.year, now.month, now.day - 6),
                end: now,
              ),
        );
        if (picked != null) onChanged(picked);
        return;
      case _DateRangeAction.clear:
        onChanged(null);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      key: const Key('date-range-selector-chip'),
      avatar: Icon(Icons.date_range,
          size: 16, color: range == null ? null : scheme.primary),
      label: Text(_label(range)),
      onPressed: () async {
        final action = await showDialog<_DateRangeAction>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Select Date Range'),
            children: [
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DateRangeAction.thisMonth),
                child: const Text('This month'),
              ),
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DateRangeAction.last7Days),
                child: const Text('Last 7 days'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext)
                    .pop(_DateRangeAction.last30Days),
                child: const Text('Last 30 days'),
              ),
              if (showMonthQuickSelect)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_DateRangeAction.month),
                  child: const Text('Pick month'),
                ),
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DateRangeAction.custom),
                child: const Text('Custom range'),
              ),
              if (range != null)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_DateRangeAction.clear),
                  child: const Text('Clear range'),
                ),
            ],
          ),
        );
        if (action != null && context.mounted) {
          await _handleAction(context, action);
        }
      },
    );
  }
}
