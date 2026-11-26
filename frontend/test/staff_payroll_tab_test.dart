import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/staff/presentation/screens/my_payroll_screen.dart';

File _source(String relativePath) {
  final file = File(relativePath);
  if (file.existsSync()) return file;
  return File('frontend/$relativePath');
}

String _readSource(String relativePath) =>
    _source(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('payroll screen supports standalone and embedded modes', () {
    const standalone = MyPayrollScreen();
    const embedded = MyPayrollScreen(showAppBar: false);

    expect(standalone.showAppBar, isTrue);
    expect(embedded.showAppBar, isFalse);

    final source = _readSource(
      'lib/features/staff/presentation/screens/my_payroll_screen.dart',
    );

    expect(source, contains('if (!widget.showAppBar) return content;'));
    expect(source, contains('showBackButton: true'));
    expect(source, contains('FeatureTabHeader('));
    expect(source, contains('SectionCard('));
    expect(source, contains('StaffService.myPayoutsStream'));
    expect(source, contains('staffPayoutSummary(payouts)'));
  });

  test('dashboard mounts payroll as the fourth staff tab', () {
    final source = _readSource('lib/screens/dashboard_screen.dart');

    expect(source, contains('static const int _staffTabCount = 4'));
    expect(source, contains('static const int _staffPayrollTab = 3'));
    expect(
      source,
      matches(RegExp(r'_staffPayrollTab,\s*\(k\) => MyPayrollScreen\(')),
    );
    expect(
      source,
      matches(RegExp(r"label: 'My payroll',\s*index: _staffPayrollTab")),
    );
    expect(source, isNot(contains('builder: (_) => const MyPayrollScreen()')));
    expect(
      source,
      contains("case _staffPayrollTab:\n        return 'My payroll';"),
    );
    expect(
      source,
      contains("case _staffPayrollTab:\n        return 'payroll';"),
    );
    expect(source,
        contains("case 'payroll':\n          return _staffPayrollTab;"));
  });
}
