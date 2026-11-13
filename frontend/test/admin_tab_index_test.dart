import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/admin_tab_index.dart';

/// Guards the public admin tab indices that nested admin screens (e.g.
/// Finance's "go to Staff Payroll") use to switch tabs without literals.
void main() {
  test('admin tabs are sequential home..staff', () {
    expect(AdminTabIndex.home, 0);
    expect(AdminTabIndex.menu, 1);
    expect(AdminTabIndex.orders, 2);
    expect(AdminTabIndex.inventory, 3);
    expect(AdminTabIndex.analytics, 4);
    expect(AdminTabIndex.finance, 5);
    expect(AdminTabIndex.staff, 6);
  });

  test('staff is not the finance index', () {
    expect(AdminTabIndex.finance, isNot(AdminTabIndex.staff));
  });
}