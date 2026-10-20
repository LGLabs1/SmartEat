// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smarteat/main.dart';
import 'package:smarteat/models/business_context.dart';
import 'package:smarteat/screens/login_screen.dart';
import 'package:smarteat/widgets/sage_briefing_card.dart';

/// Minimal fake Firebase platform so the app can boot in the test
/// environment without a real Firebase project.
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
      : super(defaultFirebaseAppName,
            const FirebaseOptions(apiKey: 'test', appId: 'test', messagingSenderId: 'test', projectId: 'test'));
}

class _FakeAuthPlatform extends FirebaseAuthPlatform {
  _FakeAuthPlatform() {
    FirebaseAuthPlatform.instance = this;
  }

  @override
  String get name => 'test';

  @override
  Map<String, dynamic> get pluginConstants => const {};

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

  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartEatApp());
    // The login screen uses infinitely repeating ambient animations, so
    // pumpAndSettle would never return. Pump a few frames instead to let the
    // auth stream resolve to the signed-out (login) state.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify that the login screen is shown
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('Sage briefing generates dynamic content using business metrics', () {
    final context = BusinessContext(
      eateryId: 'eatery-1',
      eateryName: 'Sunny Bistro',
      generatedAt: DateTime(2026, 8, 12, 9, 0).toIso8601String(),
      todayRevenue: 3500,
      yesterdayRevenue: 3000,
      todayOrderCount: 52,
      todayBestSeller: 'Banh Mi',
      todayBestSellerQty: 18,
      dayChangePercent: 16.7,
      peakHour: '12:00 PM',
      lowStockItems: [
        {
          'name': 'Beef',
          'currentStock': 2.0,
          'minStock': 10.0,
          'unit': 'kg',
          'isCritical': true,
        },
      ],
      salesForecast: [
        {
          'dayName': 'Today',
          'date': '12',
          'predictedRevenue': 4100.0,
          'isWeekend': false,
        },
      ],
      trendDirection: 'improving',
      healthScore: 82,
      healthLabel: 'Good',
    );

    final briefing = SageBriefingCard.buildContent(context, 'morning');

    expect(briefing.title, contains('Good morning'));
    expect(briefing.summary, contains('Banh Mi'));
    expect(briefing.summary, contains('Beef'));
    expect(briefing.summary, contains('forecast'));
  });
}
