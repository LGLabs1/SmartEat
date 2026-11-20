class OrderHistoryDates {
  static const String allKey = '__all__';
  static const String unknownKey = 'unknown';

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String key(DateTime? date) {
    if (date == null) return unknownKey;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static List<String> availableKeys(Iterable<DateTime?> dates) {
    final keys = <String>{};
    for (final date in dates) {
      keys.add(key(date));
    }
    final sorted = keys.toList()..sort(_compareKeys);
    return sorted;
  }

  static String filterLabel(String? key) {
    if (key == null || key == allKey) return 'All dates';
    return label(key);
  }

  static String label(String key) {
    if (key == unknownKey) return 'Unknown date';
    final parts = key.split('-');
    if (parts.length != 3) return key;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return key;
    if (month < 1 || month > 12) return key;

    final date = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateLabel = '${_months[month - 1]} $day, $year';

    if (date == today) return 'Today • $dateLabel';
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday • $dateLabel';
    }
    return dateLabel;
  }

  static Map<String, List<T>> groupByDate<T>(
    Iterable<T> items,
    DateTime? Function(T item) dateOf,
  ) {
    final grouped = <String, List<T>>{};
    for (final item in items) {
      grouped.putIfAbsent(key(dateOf(item)), () => <T>[]).add(item);
    }
    final keys = grouped.keys.toList()..sort(_compareKeys);
    return {for (final key in keys) key: grouped[key]!};
  }

  static int _compareKeys(String a, String b) {
    if (a == unknownKey && b == unknownKey) return 0;
    if (a == unknownKey) return 1;
    if (b == unknownKey) return -1;
    return b.compareTo(a);
  }
}
