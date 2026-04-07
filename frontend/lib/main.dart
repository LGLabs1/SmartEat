import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_provider.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    debugPrint('APP_START: Initializing Firebase...');
    await FirebaseService.initializeFirebase();
    debugPrint('APP_START: Firebase initialized successfully');

    // Initialize notifications in background - don't block on errors
    NotificationService().initialize().catchError((e) {
      debugPrint(
          'APP_START: Notification initialization error (non-critical): $e');
    });
  } catch (e, stack) {
    debugPrint('APP_START: CRITICAL Initialization error: $e');
    debugPrint('APP_START: Stack trace: $stack');
  }
  runApp(const SmartEatApp());
}

class SmartEatApp extends StatelessWidget {
  const SmartEatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'Smart Eat - Eatery Management System',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF1E88E5),
            secondary: const Color(0xFF00B0FF),
          ),
          scaffoldBackgroundColor: Colors.white,
          useMaterial3: true,
        ),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const DashboardScreen(),
        },
        home: const AuthGate(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Keep a persistent instance of LoginScreen to prevent state loss during rebuilds
  final Widget _loginScreen = const LoginScreen();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        debugPrint(
            'AUTH_GATE: Building - isAuthenticated: ${authProvider.isAuthenticated}, isLoading: ${authProvider.isLoading}');

        if (authProvider.isAuthenticated) {
          debugPrint('AUTH_GATE: Showing DashboardScreen');
          return const DashboardScreen();
        } else {
          debugPrint('AUTH_GATE: Showing LoginScreen');
          return _loginScreen;
        }
      },
    );
  }
}
