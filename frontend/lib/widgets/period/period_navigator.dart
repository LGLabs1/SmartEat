import 'package:flutter/material.dart';

import '../../features/finance/data/report_period.dart';

class PeriodNavigator extends StatelessWidget {
  const PeriodNavigator({
    super.key,
    required this.selection,
    required this.onChanged,
    this.now,
  });

  final ReportPeriodSelection selection;
  final ValueChanged<ReportPeriodSelection> onChanged;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previous = selection.previous(now: now);
    final next = selection.next(now: now);

    return Card(
      key: const Key('period-navigator'),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('period-navigator-previous'),
              tooltip: 'Previous period',
              icon: const Icon(Icons.chevron_left),
              onPressed: previous == null ? null : () => onChanged(previous),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 130, maxWidth: 220),
              child: Text(
                selection.label(),
                key: const Key('period-navigator-label'),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const Key('period-navigator-next'),
              tooltip: 'Next period',
              icon: const Icon(Icons.chevron_right),
              onPressed: next == null ? null : () => onChanged(next),
            ),
          ],
        ),
      ),
    );
  }
}
