const notificationRoleAdmin = 'admin';
const notificationRoleManager = 'manager';
const notificationRoleStaff = 'staff';
const notificationRoleAll = 'all';

const List<String> _notificationAdminRoles = <String>[
  notificationRoleAdmin,
  notificationRoleManager,
];

const List<String> _notificationStaffRoles = <String>[
  notificationRoleStaff,
  notificationRoleAdmin,
  notificationRoleManager,
];

const List<String> _notificationAllRoles = <String>[
  notificationRoleAll,
  notificationRoleStaff,
  notificationRoleAdmin,
  notificationRoleManager,
];

const Set<String> _sensitiveNotificationTypes = <String>{
  'low_stock',
  'out_of_stock',
  'bill_overdue',
  'bill_due_soon',
  'staff_approval',
  'order',
  'sms_low_stock',
  'sms_bill_reminder',
  'sms_daily_summary',
  'sms_test',
};

String buildNotificationDocId(String eateryId, String key) {
  final prefix = eateryId.trim().isEmpty ? 'eatery' : eateryId.trim();
  final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final room = 180 - prefix.length - 1;
  final trimmed =
      room > 0 && safe.length > room ? safe.substring(0, room) : safe;
  return '${prefix}_$trimmed';
}

List<String> notificationStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final single = (value ?? '').toString().trim();
  return single.isEmpty ? const <String>[] : <String>[single];
}

List<String> _notificationRoleList(dynamic value) {
  return notificationStringList(value)
      .map((role) => role.toLowerCase())
      .toList();
}

String notificationDefaultAudience(String type) {
  final normalized = type.trim().toLowerCase();
  if (_sensitiveNotificationTypes.contains(normalized) ||
      normalized.startsWith('sms_')) {
    return notificationRoleAdmin;
  }
  if (normalized == 'attendance') return notificationRoleStaff;
  return notificationRoleAll;
}

List<String> notificationRolesFor({
  required String audience,
  String type = '',
  List<String> targetUids = const <String>[],
}) {
  final normalizedAudience = audience.trim().toLowerCase();
  switch (normalizedAudience) {
    case notificationRoleAdmin:
    case notificationRoleManager:
      return List<String>.from(_notificationAdminRoles);
    case notificationRoleStaff:
      return List<String>.from(_notificationStaffRoles);
    case notificationRoleAll:
    case 'everyone':
      return List<String>.from(_notificationAllRoles);
  }

  if (targetUids.isNotEmpty) {
    return notificationRolesFor(
      audience: notificationDefaultAudience(type),
      type: type,
    );
  }

  return notificationRolesFor(
    audience: notificationDefaultAudience(type),
    type: type,
  );
}

List<String> notificationRolesForUser({
  required bool isAdmin,
  bool isManager = false,
}) {
  if (isAdmin) {
    return const <String>[
      notificationRoleAdmin,
      notificationRoleManager,
      notificationRoleStaff,
      notificationRoleAll,
    ];
  }
  if (isManager) {
    return const <String>[
      notificationRoleManager,
      notificationRoleStaff,
      notificationRoleAll,
    ];
  }
  return const <String>[notificationRoleStaff, notificationRoleAll];
}

List<String> notificationRolesFromPayload(Map<String, dynamic> data) {
  final explicit = _notificationRoleList(data['allowedRoles'])
      .where((role) =>
          role == notificationRoleAdmin ||
          role == notificationRoleManager ||
          role == notificationRoleStaff ||
          role == notificationRoleAll)
      .toList();
  if (explicit.isNotEmpty) return explicit;

  return notificationRolesFor(
    audience: (data['audience'] ?? '').toString(),
    type: (data['type'] ?? '').toString(),
    targetUids: notificationStringList(data['targetUids']),
  );
}

bool notificationVisibleToUser({
  required Map<String, dynamic> data,
  required String uid,
  required bool isAdmin,
  bool isManager = false,
}) {
  final targets = notificationStringList(data['targetUids']);
  if (targets.isNotEmpty) {
    return uid.isNotEmpty && targets.contains(uid.trim());
  }

  final roles = notificationRolesFromPayload(data);
  final userRoles = notificationRolesForUser(
    isAdmin: isAdmin,
    isManager: isManager,
  );
  return roles.any(userRoles.contains);
}
