import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/landing_screen.dart';
import 'package:smarteat/theme.dart';

void main() {
  Widget buildLanding() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const LandingScreen(),
      routes: {
        '/login': (_) => const Placeholder(key: Key('login-route')),
        '/register': (_) => const Placeholder(key: Key('register-route')),
      },
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders hero, CTAs, and three feature cards', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    expect(find.text('Run your eatery with\ncalm confidence.'), findsOneWidget);
    expect(
      find.text(
        'Orders, inventory, staff attendance, and AI-powered insights in one beautifully simple workspace.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('landing-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('landing-create-account')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-orders')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-inventory')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-staff')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-android')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-windows')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-pwa')), findsOneWidget);
    expect(find.text('Illustrative sample data'), findsOneWidget);
    expect(find.text('SAMPLE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.text('Sample figures only. Not connected to any registered eatery.'),
      findsOneWidget,
    );
  });

  testWidgets('sign in CTA opens the login route', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-route')), findsOneWidget);
  });

  testWidgets('create account CTA opens the register route', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing-create-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-route')), findsOneWidget);
  });

  testWidgets('PWA download option shows install instructions', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('landing-download-pwa')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Install on iPhone/iPad'),
      ),
      findsOneWidget,
    );
    expect(find.text('2. Tap the Share button.'), findsOneWidget);
    expect(
      find.text('3. Choose "Add to Home Screen", then tap Add.'),
      findsOneWidget,
    );
  });

  testWidgets('compact layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await tester.pumpAndSettle();

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
