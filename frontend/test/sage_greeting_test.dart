import 'dart:async';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smarteat/services/ai_assistant_provider.dart';
import 'package:smarteat/services/auth_provider.dart' as app_auth;
import 'package:smarteat/widgets/ai_side_panel.dart';
import 'package:smarteat/widgets/sage_full_screen.dart';
import 'package:smarteat/widgets/sage_shared_views.dart';

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

class _FakeAuthProvider extends app_auth.AuthProvider {
  _FakeAuthProvider(this._profile) : super();

  final Future<Map<String, dynamic>?> _profile;

  @override
  Future<Map<String, dynamic>?> getCurrentUserProfile() => _profile;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _FakeFirebasePlatform();
    _FakeAuthPlatform();
  });

  test('sageFirstName keeps only the first name', () {
    expect(sageFirstName('FirstName LastName'), 'FirstName');
    expect(sageFirstName('  FirstName   LastName  '), 'FirstName');
    expect(sageFirstName('   '), '');
  });

  Future<void> expectHeaderBehavior(
    WidgetTester tester,
    Widget sageWidget,
  ) async {
    final profile = Completer<Map<String, dynamic>?>();
    final auth = _FakeAuthProvider(profile.future);
    final greeting = '${sageGreeting()},';
    final noBoss = find.textContaining(RegExp('boss', caseSensitive: false));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AIAssistantProvider>(
            create: (_) => AIAssistantProvider(),
          ),
          ChangeNotifierProvider<app_auth.AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(
          home: Scaffold(body: sageWidget),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(greeting), findsOneWidget);
    expect(find.text('FirstName!'), findsNothing);
    expect(noBoss, findsNothing);

    profile.complete({'name': 'FirstName LastName'});
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(greeting), findsOneWidget);
    expect(find.text('FirstName!'), findsOneWidget);
    expect(find.text('LastName!'), findsNothing);
    expect(noBoss, findsNothing);
  }

  testWidgets('AISidePanel header hides the name until profile resolution',
      (tester) async {
    await expectHeaderBehavior(tester, const AISidePanel());
  });

  testWidgets('SageFullScreen header hides the name until profile resolution',
      (tester) async {
    await expectHeaderBehavior(tester, const SageFullScreen());
  });
}
