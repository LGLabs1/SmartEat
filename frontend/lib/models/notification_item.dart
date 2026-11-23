class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final String source;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.source,
    required this.isRead,
    required this.createdAt,
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
      data: data ?? this.data,
    );
  }
}
