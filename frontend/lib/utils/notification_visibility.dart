bool notificationVisibleToUser({
  required Map<String, dynamic> data,
  required String uid,
  required bool isAdmin,
}) {
  final targetUids = data['targetUids'];
  final targets = targetUids is List
      ? targetUids.map((value) => value.toString()).toList()
      : <String>[];

  if (targets.isNotEmpty) {
    return uid.isNotEmpty && targets.contains(uid);
  }

  final audience = (data['audience'] ?? '').toString().trim().toLowerCase();
  final type = (data['type'] ?? '').toString().trim().toLowerCase();

  if (isAdmin) {
    return audience == 'admin' ||
        audience == 'all' ||
        audience == 'everyone' ||
        audience.isEmpty;
  }

  if (audience == 'staff' ||
      audience == 'all' ||
      audience == 'everyone') {
    return true;
  }

  if (audience.isEmpty && type != 'staff_approval') return true;

  return false;
}
