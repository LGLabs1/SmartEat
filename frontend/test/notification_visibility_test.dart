import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/notification_visibility.dart';

void main() {
  test('admins see every notification', () {
    expect(
      notificationVisibleToUser(
        data: {'audience': 'admin', 'type': 'staff_approval'},
        uid: 'admin',
        isAdmin: true,
      ),
      isTrue,
    );
  });

  test('staff see shared and staff notifications', () {
    expect(
      notificationVisibleToUser(
        data: {'audience': 'all', 'type': 'order'},
        uid: 'staff-1',
        isAdmin: false,
      ),
      isTrue,
    );
    expect(
      notificationVisibleToUser(
        data: {'audience': 'staff', 'type': 'attendance'},
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
        data: {'audience': 'admin', 'type': 'low_stock'},
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
    expect(
      notificationVisibleToUser(
        data: {
          'audience': 'staff',
          'targetUids': ['staff-2'],
          'type': 'attendance',
        },
        uid: 'staff-1',
        isAdmin: false,
      ),
      isFalse,
    );
  });

  test('legacy notifications stay visible except staff approvals', () {
    expect(
      notificationVisibleToUser(
        data: {'type': 'low_stock'},
        uid: 'staff-1',
        isAdmin: false,
      ),
      isTrue,
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
}
