import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/error_messages.dart';
import 'package:smarteat/widgets/inline_error_banner.dart';

Widget buildBanner({
  String? message,
  Object? error,
  ErrorSeverity? severity,
}) {
  return MaterialApp(
    home: Scaffold(
      body: InlineErrorBanner(
        key: const Key('banner'),
        message: message,
        error: error,
        severity: severity,
      ),
    ),
  );
}

void main() {
  testWidgets('plain string errors use error severity, not blue info',
      (tester) async {
    await tester.pumpWidget(buildBanner(message: 'Something went wrong'));

    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, ErrorSeverity.error.color);
    expect(icon.color, isNot(ErrorSeverity.info.color));
  });

  testWidgets('explicit severity overrides the plain-string default',
      (tester) async {
    await tester.pumpWidget(buildBanner(
      message: 'Heads up',
      severity: ErrorSeverity.info,
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, ErrorSeverity.info.color);
  });

  testWidgets('error objects still use helper severity', (tester) async {
    await tester.pumpWidget(buildBanner(error: 'permission-denied'));

    final icon = tester.widget<Icon>(find.byIcon(Icons.lock_outline));
    expect(icon.color, ErrorSeverity.warning.color);
  });

  testWidgets('unknown error objects do not fall back to blue info',
      (tester) async {
    await tester.pumpWidget(buildBanner(error: 'just a notice'));

    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, ErrorSeverity.error.color);
    expect(icon.color, isNot(ErrorSeverity.info.color));
  });
}
