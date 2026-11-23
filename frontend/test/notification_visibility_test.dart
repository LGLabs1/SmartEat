import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/notification_visibility.dart';

void main() {
  test('admins see every notification', () {
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'admin',
          'allowedRoles': ['admin', 'manager'],
          'type': 'staff_approval',
        },
        uid: 'admin',
        isAdmin: true,
      ),
      isTrue,
    );
  });

  test('staff see shared and staff notifications', () {
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'all',
          'allowedRoles': ['all', 'staff', 'admin', 'manager'],
          'type': 'order',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isTrue,
    );
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'staff',
          'allowedRoles': ['staff', 'admin', 'manager'],
          'type': 'attendance',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isTrue,
    );
  });

  test('staff see targeted notifications regardless of audience', () {
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'admin',
          'allowedRoles': ['admin', 'manager'],
          'targetUids': ['staff-1'],
          'type': 'attendance',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isTrue,
    );
  });

  test('staff do not see admin-only or other users targeted notifications', () {
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'admin',
          'allowedRoles': ['admin', 'manager'],
          'type': 'low_stock',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'staff',
          'allowedRoles': ['staff', 'admin', 'manager'],
          'targetUids': ['staff-2'],
          'type': 'attendance',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
  });

  test('legacy sensitive notifications are hidden from staff', () {
    expect(
      notificationVisibleToUser(
        data: {'type': 'low_stock'},
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
    expect(
      notificationVisibleToUser(
        data: {'type': 'staff_approval'},
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
  });

  test('managers see admin-scoped notifications', () {
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'admin',
          'allowedRoles': ['admin', 'manager'],
          'type': 'bill_overdue',
        },
        uid: 'manager-1',
        isAdmin: false,
        isManager: true,
      ),
      isTrue,
    );
  });

  test('push payloads inherit role metadata from the notification type', () {
    expect(
      notificationRolesFromPayload({
        'type': 'low_stock',
        'source': 'push',
      }),
      contains('admin'),
    );
    expect(
      notificationRolesFromPayload({
        'type': 'push',
        'allowedRoles': ['manager', 'staff'],
      }),
      equals(['manager', 'staff']),
    );
  });

  test('notification document ids stay deterministic and prefixed', () {
    expect(
      buildNotificationDocId('eatery-42', 'push_abc:123'),
      'eatery-42_push_abc_123',
    );
  });
}
