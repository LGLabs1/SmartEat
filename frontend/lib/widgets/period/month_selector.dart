import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.onMonthChanged,
    this.firstDate,
    this.lastDate,
  });

  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  static Future<DateTime?> pickMonth(
    BuildContext context, {
    required DateTime initialMonth,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final start = firstDate ?? DateTime(2000, 1, 1);
    final end = lastDate ?? DateTime(2100, 12, 1);
    final first = DateTime(start.year, start.month, 1);
    final last = DateTime(end.year, end.month, 1);
    var selectedYear = initialMonth.year;
    var selectedMonth = initialMonth.month;

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final years = List<int>.generate(
            last.year - first.year + 1,
            (i) => last.year - i,
          ).where((y) => y >= first.year).toList();
          final months = List<int>.generate(12, (i) => i + 1).where((m) {
            final candidate = DateTime(selectedYear, m, 1);
            return !candidate.isBefore(first) && !candidate.isAfter(last);
          }).toList();
          if (!months.contains(selectedMonth)) {
            selectedMonth = months.isEmpty ? first.month : months.last;
          }

          return AlertDialog(
            title: const Text('Select Month'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selectedYear,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final year in years)
                        DropdownMenuItem<int>(
                            value: year, child: Text('$year')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedYear = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in months)
                        ChoiceChip(
                          key: ValueKey('month-choice-$m'),
                          label:
                              Text(DateFormat('MMM').format(DateTime(2024, m))),
                          selected: selectedMonth == m,
                          onSelected: (_) =>
                              setDialogState(() => selectedMonth = m),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext)
                    .pop(DateTime(selectedYear, selectedMonth, 1)),
                child: const Text('Select'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      key: const Key('month-selector-chip'),
      avatar:
          Icon(Icons.calendar_month_outlined, size: 16, color: scheme.primary),
      label: Text(DateFormat('MMM yyyy').format(month)),
      onPressed: () async {
        final picked = await pickMonth(
          context,
          initialMonth: month,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onMonthChanged(picked);
      },
    );
  }
}
