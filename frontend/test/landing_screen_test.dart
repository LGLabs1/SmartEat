import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/config/app_version.dart';
import 'package:smarteat/screens/landing_screen.dart';
import 'package:smarteat/theme.dart';
import 'package:smarteat/widgets/sage_avatar.dart';

void main() {
  Widget buildLanding() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const LandingScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
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

  Future<void> settleLanding(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  testWidgets('renders hero, CTAs, and all feature cards', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    expect(find.text('Run your eatery with\ncalm confidence.'), findsOneWidget);
    expect(
      find.text(
        'Orders, POS, inventory, recipes, analytics, finance, payroll, attendance, notifications, and Sage AI — all in one beautifully simple workspace.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('landing-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('landing-create-account')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-orders')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-inventory')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-staff')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-pos')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-recipes')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-analytics')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-finance')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-payroll')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-sage')), findsOneWidget);
    expect(
      find.byKey(const Key('landing-feature-notifications')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('landing-feature-settings')), findsOneWidget);
    expect(find.byKey(const Key('landing-feature-devices')), findsOneWidget);
    expect(find.text('MEET SAGE · YOUR AI COMPANION'), findsOneWidget);
    expect(find.byType(SageAvatar), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SageAvatar && widget.showBadge,
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('landing-sage-intro')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-android')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-windows')), findsOneWidget);
    expect(find.byKey(const Key('landing-download-pwa')), findsOneWidget);
    expect(
      find.text('Current download version ${AppVersion.display}'),
      findsOneWidget,
    );
    expect(find.text('Illustrative sample data'), findsOneWidget);
    expect(find.text('SAMPLE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.text('Sample figures only. Not connected to any registered eatery.'),
      findsOneWidget,
    );
  });

  testWidgets('Sage introduction messages advance on tap', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    expect(
      find.text('Hi, I’m Sage — your eatery sidekick.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('landing-sage-intro')));
    await settleLanding(tester);

    expect(
      find.text('Ask me what needs attention today.'),
      findsOneWidget,
    );
  });

  testWidgets('sign in CTA opens the login route', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    await tester.tap(find.byKey(const Key('landing-sign-in')));
    await settleLanding(tester);

    expect(find.byKey(const Key('login-route')), findsOneWidget);
  });

  testWidgets('create account CTA opens the register route', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    await tester.tap(find.byKey(const Key('landing-create-account')));
    await settleLanding(tester);

    expect(find.byKey(const Key('register-route')), findsOneWidget);
  });

  testWidgets('PWA download option shows install instructions', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('landing-download-pwa')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settleLanding(tester);
    await tester.tap(find.byKey(const Key('landing-download-pwa')));
    await settleLanding(tester);

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
    await settleLanding(tester);

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLanding());
    await settleLanding(tester);

    expect(find.byType(LandingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
