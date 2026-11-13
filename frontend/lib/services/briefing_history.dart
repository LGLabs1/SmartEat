import '../widgets/sage_briefing_card.dart';

/// Order in which the three daily briefing periods are shown.
const List<String> briefingPeriodOrder = ['morning', 'afternoon', 'evening'];

/// Stable `yyyy-MM-dd` key for grouping briefings by calendar day.
/// The ISO-ish format sorts correctly as a plain string.
String briefingDateKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

/// Sort rank of a period (morning → 0, afternoon → 1, evening → 2).
int briefingPeriodRank(String period) {
  final index = briefingPeriodOrder.indexOf(period);
  return index == -1 ? briefingPeriodOrder.length : index;
}

/// Compact label used inside the history accordion.
String briefingPeriodShortLabel(String period) => switch (period) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      _ => 'Briefing',
    };

String briefingPeriodEmoji(String period) => switch (period) {
      'morning' => '🌅',
      'afternoon' => '☀',
      'evening' => '🌙',
      _ => '✨',
    };

/// Groups [items] by day and orders each day's briefings by period then time.
Map<String, List<SageBriefingContent>> groupBriefingsByDate(
  Iterable<SageBriefingContent> items,
) {
  final grouped = <String, List<SageBriefingContent>>{};
  for (final briefing in items) {
    grouped
        .putIfAbsent(briefingDateKey(briefing.generatedAt), () => [])
        .add(briefing);
  }
  for (final list in grouped.values) {
    list.sort((a, b) {
      final byPeriod =
          briefingPeriodRank(a.period).compareTo(briefingPeriodRank(b.period));
      return byPeriod != 0 ? byPeriod : a.generatedAt.compareTo(b.generatedAt);
    });
  }
  return grouped;
}

/// Date keys (newest first) that have at least one briefing.
List<String> sortedBriefingDateKeysDesc(
  Map<String, List<SageBriefingContent>> grouped,
) {
  final keys = grouped.keys.toList();
  keys.sort((a, b) => b.compareTo(a));
  return keys;
}

/// The periods that have already begun by [now], earliest first.
List<String> startedBriefingPeriods(DateTime now) {
  final periods = <String>[];
  if (now.hour >= 6) periods.add('morning');
  if (now.hour >= 12) periods.add('afternoon');
  if (now.hour >= 17) periods.add('evening');
  return periods;
}

/// Splits a stored `detailText` (one `Label: value` pair per line) into a
/// label→value map so the dialog and the PDF export can render it as themed,
/// highlighted sections instead of one flat paragraph. Unparseable lines are
/// dropped.
Map<String, String> parseBriefingDetail(String detailText) {
  final fields = <String, String>{};
  for (final rawLine in detailText.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final sep = line.indexOf(':');
    if (sep <= 0) continue;
    final label = line.substring(0, sep).trim();
    final value = line.substring(sep + 1).trim();
    if (label.isNotEmpty && value.isNotEmpty) {
      fields.putIfAbsent(label, () => value);
    }
  }
  return fields;
}

/// Pulls the numeric score out of a label like `Fair (72/100)`.
int? healthScoreFromLabel(String label) {
  final match = RegExp(r'(\d+)\s*/\s*100').firstMatch(label);
  return int.tryParse(match?.group(1) ?? '');
}
