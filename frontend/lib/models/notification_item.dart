class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final String source;
  final bool isRead;
  final DateTime createdAt;
  final String route;
  final String ignoreKey;
  final bool pinned;
  final bool ignored;
  final List<String> details;
  final Map<String, dynamic> data;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.source,
    required this.isRead,
    required this.createdAt,
    this.route = '',
    this.ignoreKey = '',
    this.pinned = false,
    this.ignored = false,
    this.details = const <String>[],
    required this.data,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    String? source,
    bool? isRead,
    DateTime? createdAt,
    String? route,
    String? ignoreKey,
    bool? pinned,
    bool? ignored,
    List<String>? details,
    Map<String, dynamic>? data,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      source: source ?? this.source,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      route: route ?? this.route,
      ignoreKey: ignoreKey ?? this.ignoreKey,
      pinned: pinned ?? this.pinned,
      ignored: ignored ?? this.ignored,
      details: details ?? this.details,
      data: data ?? this.data,
    );
  }
}
