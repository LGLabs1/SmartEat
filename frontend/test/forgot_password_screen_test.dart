import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smarteat/screens/forgot_password_screen.dart';
import 'package:smarteat/services/password_reset_api.dart';
import 'package:smarteat/theme.dart';

void main() {
  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp(PasswordResetApi api) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      initialRoute: '/forgot-password',
      routes: {
        '/forgot-password': (_) => ForgotPasswordScreen(api: api),
        '/login': (_) => const Placeholder(key: Key('login-route')),
      },
    );
  }

  testWidgets('validates the registered email before sending a code',
      (tester) async {
    await setSurface(tester, const Size(1200, 900));
    var requestCount = 0;
    final api = PasswordResetApi(
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://example.test/api',
    );

    await tester.pumpWidget(buildApp(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot-email')), findsOneWidget);
    expect(find.byKey(const Key('forgot-channel-email')), findsOneWidget);
    expect(find.byKey(const Key('forgot-channel-sms')), findsOneWidget);
    expect(find.byKey(const Key('forgot-send-code')), findsOneWidget);

    await tester.tap(find.byKey(const Key('forgot-send-code')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your email'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgot-email')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('forgot-send-code')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(requestCount, 0);
  });

  testWidgets('requests, verifies, and confirms a password reset',
      (tester) async {
    await setSurface(tester, const Size(1200, 900));
    final calls = <http.Request>[];
    final api = PasswordResetApi(
      client: MockClient((request) async {
        calls.add(request);
        final path = request.url.path;
        if (path.endsWith('/request')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'message': 'If an account exists, a code was sent.',
              'retryAfterSeconds': 0,
            }),
            200,
          );
        }
        if (path.endsWith('/verify')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'resetToken': 'reset-token-123',
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
            }),
            200,
          );
        }
        if (path.endsWith('/confirm')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'message': 'Password reset successfully.',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
      baseUrl: 'https://example.test/api',
    );

    await tester.pumpWidget(buildApp(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('forgot-email')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('forgot-send-code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot-otp-0')), findsOneWidget);
    expect(find.byKey(const Key('forgot-verify-code')), findsOneWidget);
    expect(
      find.text('If an account exists, a code was sent.'),
      findsOneWidget,
    );

    for (var index = 0; index < 6; index += 1) {
      await tester.enterText(
        find.byKey(Key('forgot-otp-$index')),
        '${index + 1}',
      );
      await tester.pump();
    }

    await tester.ensureVisible(find.byKey(const Key('forgot-verify-code')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot-verify-code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot-new-password')), findsOneWidget);
    expect(find.byKey(const Key('forgot-confirm-password')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgot-new-password')),
      'newpass123',
    );
    await tester.enterText(
      find.byKey(const Key('forgot-confirm-password')),
      'newpass123',
    );
    await tester.ensureVisible(find.byKey(const Key('forgot-reset-password')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot-reset-password')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-route')), findsOneWidget);
    expect(calls.length, 3);
    expect(
      jsonDecode(calls[0].body)['email'],
      'admin@example.com',
    );
    expect(jsonDecode(calls[0].body)['channel'], 'email');
    expect(jsonDecode(calls[1].body)['code'], '123456');
    expect(jsonDecode(calls[2].body)['resetToken'], 'reset-token-123');
    expect(jsonDecode(calls[2].body)['newPassword'], 'newpass123');
  });

  testWidgets('shows the server error when a code is invalid', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    final api = PasswordResetApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/request')) {
          return http.Response(
            jsonEncode({'ok': true, 'retryAfterSeconds': 0}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'error': 'Invalid or expired verification code.',
            'code': 'invalid_code',
          }),
          400,
        );
      }),
      baseUrl: 'https://example.test/api',
    );

    await tester.pumpWidget(buildApp(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('forgot-email')),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('forgot-send-code')));
    await tester.pumpAndSettle();

    for (var index = 0; index < 6; index += 1) {
      await tester.enterText(
        find.byKey(Key('forgot-otp-$index')),
        '${index + 1}',
      );
      await tester.pump();
    }

    await tester.ensureVisible(find.byKey(const Key('forgot-verify-code')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot-verify-code')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid or expired verification code.'), findsOneWidget);
    expect(find.byKey(const Key('forgot-new-password')), findsNothing);
  });

  testWidgets('sends SMS codes and starts the resend cooldown', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    final calls = <http.Request>[];
    final api = PasswordResetApi(
      client: MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({'ok': true, 'retryAfterSeconds': 60}),
          200,
        );
      }),
      baseUrl: 'https://example.test/api',
    );

    await tester.pumpWidget(buildApp(api));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('forgot-email')),
      'staff@example.com',
    );
    await tester.tap(find.byKey(const Key('forgot-channel-sms')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('forgot-send-code')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('forgot-otp-0')), findsOneWidget);
    expect(find.text('Resend in 60s'), findsOneWidget);
    expect(jsonDecode(calls.single.body)['channel'], 'sms');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('compact recovery layout renders without overflow',
      (tester) async {
    await setSurface(tester, const Size(390, 844));
    final api = PasswordResetApi(
      client: MockClient((request) async => http.Response('{}', 200)),
      baseUrl: 'https://example.test/api',
    );

    await tester.pumpWidget(buildApp(api));
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.byKey(const Key('forgot-send-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
