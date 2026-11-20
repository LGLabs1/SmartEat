import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/register_screen.dart';
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

  Map<String, WidgetBuilder> buildRoutes() {
    return {
      '/': (_) => const Placeholder(key: Key('landing-route')),
      '/login': (_) => const Placeholder(key: Key('login-route')),
      '/register': (_) => const RegisterScreen(),
    };
  }

  Widget buildRegisterRouteApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      routes: buildRoutes(),
    );
  }

  Widget buildDirectRegisterApp() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      initialRoute: '/register',
      routes: buildRoutes(),
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

  testWidgets('renders premium signup controls', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildRegisterRouteApp());
    await settleAuthUi(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/register');
    await settleAuthUi(tester);

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byKey(const Key('register-welcome-panel')), findsOneWidget);
    expect(find.text('Start your\nSmartEat story.'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('register-back-to-home')), findsOneWidget);
    expect(find.byKey(const Key('register-continue')), findsOneWidget);
    expect(find.byKey(const Key('register-sign-in')), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('back control pops to landing when signup was pushed',
      (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildRegisterRouteApp());
    await settleAuthUi(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/register');
    await settleAuthUi(tester);

    await tester.tap(find.byKey(const Key('register-back-to-home')));
    await settleAuthUi(tester);

    expect(find.byKey(const Key('landing-route')), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('back control opens landing when signup is opened directly',
      (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildDirectRegisterApp());
    await settleAuthUi(tester);

    await tester.tap(find.byKey(const Key('register-back-to-home')));
    await settleAuthUi(tester);

    expect(find.byKey(const Key('landing-route')), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('compact signup layout renders without overflow', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildDirectRegisterApp());
    await settleAuthUi(tester);

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('join eatery mode swaps the eatery field', (tester) async {
    await setSurface(tester, const Size(1200, 900));
    await tester.pumpWidget(buildDirectRegisterApp());
    await settleAuthUi(tester);

    expect(find.text('Eatery Name'), findsOneWidget);

    await tester.tap(find.text('Join Eatery'));
    await settleAuthUi(tester);

    expect(find.text('Eatery Name'), findsNothing);
    expect(find.text('Eatery ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
