import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/staff_utils.dart';

void main() {
  group('isAdminUser', () {
    test('detects modern isAdmin flag', () {
      expect(isAdminUser({'isAdmin': true}), isTrue);
      expect(isAdminUser({'isAdmin': false}), isFalse);
    });

    test('detects legacy role and string/number flags', () {
      expect(isAdminUser({'role': 'admin'}), isTrue);
      expect(isAdminUser({'role': 'Admin'}), isTrue);
      expect(isAdminUser({'role': 'staff'}), isFalse);
      expect(isAdminUser({'isAdmin': 'true'}), isTrue);
      expect(isAdminUser({'isAdmin': 1}), isTrue);
      expect(isAdminUser({'isAdmin': 0}), isFalse);
    });
  });

  group('isApprovedUser', () {
    test('missing approval is treated as approved', () {
      expect(isApprovedUser({}), isTrue);
    });

    test('honours boolean, string and numeric flags', () {
      expect(isApprovedUser({'approved': true}), isTrue);
      expect(isApprovedUser({'approved': false}), isFalse);
      expect(isApprovedUser({'approved': 'true'}), isTrue);
      expect(isApprovedUser({'approved': 'false'}), isFalse);
      expect(isApprovedUser({'approved': 1}), isTrue);
      expect(isApprovedUser({'approved': 0}), isFalse);
    });
  });

  test('isPendingStaff is only true for unapproved non-admins', () {
    expect(isPendingStaff({'approved': false}), isTrue);
    expect(isPendingStaff({'approved': true}), isFalse);
    expect(isPendingStaff({}), isFalse);
    expect(isPendingStaff({'approved': false, 'isAdmin': true}), isFalse);
  });

  group('staffDisplayName', () {
    test('prefers full name, then email, then uid', () {
      expect(
        staffDisplayName(
            {'firstName': 'Ana', 'lastName': 'Cruz', 'email': 'a@x.com'}, 'u1'),
        'Ana Cruz',
      );
      expect(staffDisplayName({'email': 'a@x.com'}, 'u1'), 'a@x.com');
      expect(staffDisplayName({}, 'u1'), 'u1');
    });
  });

  test('staffPhone falls back to legacy phoneNumber', () {
    expect(staffPhone({'phone': '0917'}), '0917');
    expect(staffPhone({'phoneNumber': '0918'}), '0918');
    expect(staffPhone({}), '');
  });

  group('payroll math', () {
    test('half-day rate falls back to half the daily rate', () {
      expect(
        effectiveHalfDayRate(dailyRate: 500, halfDayRate: 0),
        250,
      );
      expect(
        effectiveHalfDayRate(dailyRate: 500, halfDayRate: 200),
        200,
      );
      expect(effectiveHalfDayRate(dailyRate: 0, halfDayRate: 0), 0);
    });

    test('gross pay uses the effective half-day rate', () {
      expect(
        computeGrossPay(
          dailyRate: 500,
          halfDayRate: 0,
          fullDays: 3,
          halfDays: 2,
        ),
        2000,
      );
      expect(
        computeGrossPay(
          dailyRate: 500,
          halfDayRate: 220,
          fullDays: 1,
          halfDays: 1,
        ),
        720,
      );
    });

    test('net pay clamps at zero', () {
      expect(computeNetPay(gross: 1000, advances: 250), 750);
      expect(computeNetPay(gross: 100, advances: 250), 0);
    });
  });

  group('auto-mark dates', () {
    final today = DateTime(2026, 11, 12, 15, 30);

    test('only strictly past days are marked', () {
      expect(
        shouldAutoMarkAbsent(day: DateTime(2026, 11, 11), today: today),
        isTrue,
      );
      expect(
        shouldAutoMarkAbsent(day: DateTime(2026, 11, 12), today: today),
        isFalse,
      );
      expect(
        shouldAutoMarkAbsent(day: DateTime(2026, 11, 13), today: today),
        isFalse,
      );
    });

    test('time-of-day is ignored', () {
      expect(
        shouldAutoMarkAbsent(
          day: DateTime(2026, 11, 11, 23, 59),
          today: DateTime(2026, 11, 12, 0, 1),
        ),
        isTrue,
      );
    });

    test('ymd key is zero-padded', () {
      expect(staffFormatYmd(DateTime(2026, 1, 2)), '2026-01-02');
    });
  });

  group('staffFilterFor', () {
    test('unapproved non-admins are pending regardless of profile status', () {
      expect(
        staffFilterFor(
          data: {'approved': false},
          profileStatus: 'inactive',
        ),
        StaffDirectoryFilter.pending,
      );
    });

    test('inactive/removed/disabled profile statuses are inactive', () {
      for (final status in ['inactive', 'Removed', 'disabled']) {
        expect(
          staffFilterFor(data: {'approved': true}, profileStatus: status),
          StaffDirectoryFilter.inactive,
        );
      }
    });

    test('everything else is active', () {
      expect(
        staffFilterFor(data: {'approved': true}, profileStatus: 'active'),
        StaffDirectoryFilter.active,
      );
      expect(
        staffFilterFor(data: {}, profileStatus: ''),
        StaffDirectoryFilter.active,
      );
    });
  });

  group('staffMatchesFilter', () {
    test('all matches everything', () {
      expect(
        staffMatchesFilter(
          data: {'approved': false},
          profileStatus: 'inactive',
          filter: StaffDirectoryFilter.all,
        ),
        isTrue,
      );
    });

    test('compares against the derived bucket', () {
      expect(
        staffMatchesFilter(
          data: {'approved': false},
          profileStatus: 'active',
          filter: StaffDirectoryFilter.pending,
        ),
        isTrue,
      );
      expect(
        staffMatchesFilter(
          data: {'approved': true},
          profileStatus: 'inactive',
          filter: StaffDirectoryFilter.active,
        ),
        isFalse,
      );
    });
  });

  group('staffMatchesQuery', () {
    final data = <String, dynamic>{
      'firstName': 'Ana',
      'lastName': 'Cruz',
      'email': 'ana@example.com',
      'phone': '09171234567',
    };

    test('empty query matches', () {
      expect(
        staffMatchesQuery(data: data, uid: 'u1', query: '   '),
        isTrue,
      );
    });

    test('matches name, email, phone, uid and position case-insensitively', () {
      expect(staffMatchesQuery(data: data, uid: 'u1', query: 'ana'), isTrue);
      expect(
        staffMatchesQuery(data: data, uid: 'u1', query: 'CRUZ'),
        isTrue,
      );
      expect(
        staffMatchesQuery(data: data, uid: 'u1', query: 'example.com'),
        isTrue,
      );
      expect(
        staffMatchesQuery(data: data, uid: 'u1', query: '0917'),
        isTrue,
      );
      expect(staffMatchesQuery(data: data, uid: 'u1', query: 'u1'), isTrue);
      expect(
        staffMatchesQuery(
          data: data,
          uid: 'u1',
          query: 'cashier',
          position: 'Cashier',
        ),
        isTrue,
      );
    });

    test('returns false when nothing matches', () {
      expect(
        staffMatchesQuery(data: data, uid: 'u1', query: 'chef'),
        isFalse,
      );
    });
  });

  group('staffInitials', () {
    test('uses first and last name initials', () {
      expect(staffInitials('Ana Cruz'), 'AC');
      expect(staffInitials('  ana   maria cruz '), 'AC');
    });

    test('single word uses one letter', () {
      expect(staffInitials('Ana'), 'A');
    });

    test('empty name falls back to a question mark', () {
      expect(staffInitials('   '), '?');
    });
  });

  group('staffPayoutSummary', () {
    test('separates weekly payouts from advances', () {
      final summary = staffPayoutSummary([
        {'amount': 1000, 'type': 'weekly'},
        {'amount': 250, 'type': 'advance'},
        {'amount': 800, 'type': 'weekly'},
        {'amount': 100.5, 'type': 'advance'},
      ]);
      expect(summary.paid, 1800);
      expect(summary.advances, 350.5);
      expect(summary.count, 4);
    });

    test('missing type counts as a weekly payout', () {
      final summary = staffPayoutSummary([
        {'amount': 500},
      ]);
      expect(summary.paid, 500);
      expect(summary.advances, 0);
    });

    test('ignores non-numeric amounts but still counts records', () {
      final summary = staffPayoutSummary([
        {'amount': 'n/a'},
        {'amount': 200, 'type': 'weekly'},
      ]);
      expect(summary.paid, 200);
      expect(summary.count, 2);
    });

    test('empty history is all zeros', () {
      final summary = staffPayoutSummary(const []);
      expect(summary.paid, 0);
      expect(summary.advances, 0);
      expect(summary.count, 0);
    });
  });

  group('staffMealOrderTotal', () {
    test('multiplies price by quantity across items', () {
      final total = staffMealOrderTotal({
        'items': [
          {'name': 'Adobo', 'price': 120, 'quantity': 2},
          {'name': 'Rice', 'price': 20.5, 'quantity': 3},
        ],
      });
      expect(total, 301.5);
    });

    test('handles missing or invalid item fields', () {
      expect(staffMealOrderTotal({}), 0);
      expect(
        staffMealOrderTotal({
          'items': [
            {'name': 'Soup'},
            {'name': 'Juice', 'price': 'n/a', 'quantity': 2},
          ],
        }),
        0,
      );
    });
  });

  group('staffMealItemsLabel', () {
    test('joins items with quantities', () {
      final label = staffMealItemsLabel({
        'items': [
          {'name': 'Adobo', 'quantity': 2},
          {'name': 'Rice', 'quantity': 1},
        ],
      });
      expect(label, '2× Adobo, Rice');
    });

    test('truncates long item lists', () {
      final label = staffMealItemsLabel({
        'items': [
          {'name': 'A', 'quantity': 1},
          {'name': 'B', 'quantity': 1},
          {'name': 'C', 'quantity': 1},
          {'name': 'D', 'quantity': 1},
        ],
      }, maxItems: 2);
      expect(label, 'A, B +2 more');
    });

    test('empty orders fall back to a placeholder', () {
      expect(staffMealItemsLabel({}), 'No items');
      expect(staffMealItemsLabel({'items': const []}), 'No items');
    });
  });

  group('staffMealOrderSummary', () {
    test('counts statuses and sums completed order value', () {
      final summary = staffMealOrderSummary([
        {
          'status': 'pending',
          'items': [
            {'price': 100, 'quantity': 1},
          ],
        },
        {
          'status': 'completed',
          'items': [
            {'price': 120, 'quantity': 2},
          ],
        },
        {
          'status': 'completed',
          'items': [
            {'price': 50, 'quantity': 1},
          ],
        },
        {
          'status': 'cancelled',
          'items': [
            {'price': 999, 'quantity': 1},
          ],
        },
      ]);
      expect(summary.pending, 1);
      expect(summary.completed, 2);
      expect(summary.total, 290);
    });

    test('missing status counts as pending', () {
      final summary = staffMealOrderSummary([
        {
          'items': [
            {'price': 10, 'quantity': 1},
          ],
        },
      ]);
      expect(summary.pending, 1);
      expect(summary.completed, 0);
      expect(summary.total, 0);
    });
  });

  group('staffMealMatchesFilter', () {
    final order = <String, dynamic>{
      'staffName': 'Maria Santos',
      'staffId': 'uid-1',
      'status': 'pending',
      'notes': 'No onions',
      'items': [
        {'name': 'Adobo'},
        {'name': 'Pancit'},
      ],
    };

    test('all/empty status matches any status', () {
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'all',
          query: '',
        ),
        isTrue,
      );
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: '',
          query: '',
        ),
        isTrue,
      );
    });

    test('status filter compares case-insensitively', () {
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'PENDING',
          query: '',
        ),
        isTrue,
      );
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'completed',
          query: '',
        ),
        isFalse,
      );
    });

    test('search covers staff, notes and item names', () {
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'all',
          query: 'maria',
        ),
        isTrue,
      );
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'all',
          query: 'onions',
        ),
        isTrue,
      );
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'all',
          query: 'pancit',
        ),
        isTrue,
      );
      expect(
        staffMealMatchesFilter(
          order: order,
          statusFilter: 'all',
          query: 'burger',
        ),
        isFalse,
      );
    });
  });
}
