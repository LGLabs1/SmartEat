import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'services/auth_provider.dart';
import 'services/chat_provider.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FirebaseService.initializeFirebase();

    // Initialize notifications in background - don't block on errors
    NotificationService().initialize().catchError((e) {});
  } catch (e) {}
  runApp(const SmartEatApp());
}

class SmartEatApp extends StatelessWidget {
  const SmartEatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
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
          '/': (context) => const AuthGate(),
          '/login': (context) => const AuthGate(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const AuthGate(child: DashboardScreen()),
          '/settings': (context) => const AuthGate(child: SettingsScreen()),
          '/notifications': (context) =>
              const AuthGate(child: NotificationsScreen()),
          '/profile': (context) => const AuthGate(child: ProfileScreen()),
          '/about': (context) => const AuthGate(child: AboutScreen()),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key, this.child}) : super(key: key);

  final Widget? child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'SmartEat',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E88E5),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final user = snapshot.data;
        final isAuthenticated = user != null;

        if (widget.child != null) {
          if (isAuthenticated) {
            return widget.child!;
          }
          return const LoginScreen();
        }

        if (isAuthenticated) {
          return const DashboardScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
