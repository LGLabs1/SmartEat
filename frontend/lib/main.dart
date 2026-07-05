import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'services/auth_provider.dart';
import 'services/chat_provider.dart';
import 'services/ai_assistant_provider.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/about_screen.dart';
import 'widgets/ai_side_panel.dart';
import 'widgets/floating_ai_button.dart';
import 'theme.dart';

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
        ChangeNotifierProvider(create: (_) => AIAssistantProvider()),
      ],
      child: MaterialApp(
        title: 'Smart Eat - Eatery Management System',
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          return child ?? const SizedBox.shrink();
        },
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

class AIAssistantShell extends StatelessWidget {
  const AIAssistantShell({Key? key, required this.child}) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<AIAssistantProvider>(
          builder: (context, assistant, _) {
            return Stack(
              children: [
                if (assistant.isExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => assistant.setPanelExpanded(false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(color: Colors.black54),
                    ),
                  ),
                if (assistant.isExpanded)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: AISidePanel(),
                  ),
                // Draggable assistant button
                Positioned(
                  left: assistant.buttonPosition?.dx ?? 24,
                  top: assistant.buttonPosition?.dy ?? 24,
                  child: const FloatingAIAssistantButton(),
                ),

                // Transient popup anchored to the assistant button
                if (assistant.showPopup && assistant.buttonPosition != null)
                  Positioned(
                    left: (assistant.buttonPosition!.dx - 260).clamp(8.0, MediaQuery.of(context).size.width - 280.0),
                    top: (assistant.buttonPosition!.dy - 80).clamp(8.0, MediaQuery.of(context).size.height - 120.0),
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        onTap: () {
                          assistant.setPanelExpanded(true);
                          if (assistant.activeInsights.isNotEmpty) {
                            assistant.setActivePage(assistant.activeInsights.first.page);
                          }
                        },
                        child: Container(
                          width: 260,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1220).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20)],
                          ),
                          child: Text(
                            assistant.popupContent ?? '',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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
            return AIAssistantShell(child: widget.child!);
          }
          return const LoginScreen();
        }

        if (isAuthenticated) {
          return const AIAssistantShell(child: DashboardScreen());
        }

        return const LoginScreen();
      },
    );
  }
}
