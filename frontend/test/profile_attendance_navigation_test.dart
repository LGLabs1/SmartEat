import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/profile_screen.dart';

File _source(String relativePath) {
  final file = File(relativePath);
  if (file.existsSync()) return file;
  return File('frontend/$relativePath');
}

void main() {
  test('profile screen exposes an optional attendance callback', () {
    var called = false;
    const withoutCallback = ProfileScreen();
    final withCallback = ProfileScreen(
      onOpenTeamAttendance: () => called = true,
    );

    expect(withoutCallback.onOpenTeamAttendance, isNull);
    expect(withCallback.onOpenTeamAttendance, isNotNull);

    withCallback.onOpenTeamAttendance!();
    expect(called, isTrue);
  });

  test('profile header has a back button and attendance action uses callback',
      () {
    final source =
        _source('lib/screens/profile_screen.dart').readAsStringSync();

    expect(source, contains('showBackButton: true'));
    expect(source, contains('final callback = widget.onOpenTeamAttendance;'));
    expect(
      source,
      matches(
        RegExp(r'callback\(\);\s*if \(Navigator\.of\(context\)\.canPop\(\)\)'),
      ),
    );
    expect(
      source,
      contains('const StaffManagementScreen(initialTabIndex: 1)'),
    );
  });

  test('dashboard profile route forwards attendance callback', () {
    final dashboard =
        _source('lib/screens/dashboard_screen.dart').readAsStringSync();
    final main = _source('lib/main.dart').readAsStringSync();

    expect(dashboard, contains('arguments: _openTeamAttendanceFromProfile'));
    expect(dashboard, contains('_goToTab(_adminStaffTab)'));
    expect(
      dashboard,
      matches(RegExp(r'controller\.animateTo\(\s*1,')),
    );
    expect(
      dashboard,
      contains('initialTabIndex: _staffManagementInitialTab'),
    );
    expect(main, contains('arguments is VoidCallback'));
    expect(main, contains('onOpenTeamAttendance: onOpenTeamAttendance'));
  });
}
