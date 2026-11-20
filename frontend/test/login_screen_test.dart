import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smarteat/screens/login_screen.dart';
import 'package:smarteat/services/auth_provider.dart' as app_auth;
import 'package:smarteat/theme.dart';

class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform() {
    FirebasePlatform.instance = this;
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    return _FakeFirebaseApp();
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    return _FakeFirebaseApp();
  }

  @override
  List<FirebaseAppPlatform> get apps => [_FakeFirebaseApp()];
}

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
      : super(
          defaultFirebaseAppName,
          const FirebaseOptions(
            apiKey: 'test',
            appId: 'test',
            messagingSenderId: 'test',
            projectId: 'test',
          ),
        );
}

class _FakeAuthPlatform extends FirebaseAuthPlatform {
  _FakeAuthPlatform() {
    FirebaseAuthPlatform.instance = this;
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;

  @override
  Stream<UserPlatform?> authStateChanges() => Stream<UserPlatform?>.value(null);

  @override
  Stream<UserPlatform?> idTokenChanges() => Stream<UserPlatform?>.value(null);

  @override
  Stream<UserPlatform?> userChanges() => Stream<UserPlatform?>.value(null);

  @override
  UserPlatform? get currentUser => null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _FakeFirebasePlatform();
    _FakeAuthPlatform();
  });

  Widget buildLoginRouteApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      routes: {
        '/': (_) => const Placeholder(key: Key('landing-route')),
        '/login': (_) => ChangeNotifierProvider(
              create: (_) => app_auth.AuthProvider(),
              child: const LoginScreen(),
            ),
      },
    );
  }

  Widget buildDirectLoginApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      initialRoute: '/login',
      routes: {
        '/': (_) => const Placeholder(key: Key('landing-route')),
        '/login': (_) => ChangeNotifierProvider(
              create: (_) => app_auth.AuthProvider(),
              child: const LoginScreen(),
            ),
      },
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settleAuthUi(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('renders premium login controls', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLoginRouteApp());
    await settleAuthUi(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/login');
    await settleAuthUi(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('login-welcome-panel')), findsOneWidget);
    expect(find.text('Welcome back to\nSmartEat.'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('login-back-to-home')), findsOneWidget);
    expect(find.byKey(const Key('login-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('login-create-account')), findsOneWidget);
    expect(find.byKey(const Key('login-forgot-password')), findsOneWidget);
    expect(find.text('Sign in to your workspace'), findsOneWidget);
  });

  testWidgets('back control pops to landing when login was pushed',
      (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildLoginRouteApp());
    await settleAuthUi(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/login');
    await settleAuthUi(tester);

    await tester.tap(find.byKey(const Key('login-back-to-home')));
    await settleAuthUi(tester);

    expect(find.byKey(const Key('landing-route')), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('back control opens landing when login is opened directly',
      (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildDirectLoginApp());
    await settleAuthUi(tester);

    await tester.tap(find.byKey(const Key('login-back-to-home')));
    await settleAuthUi(tester);

    expect(find.byKey(const Key('landing-route')), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('compact login layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildDirectLoginApp());
    await settleAuthUi(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
