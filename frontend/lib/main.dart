import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'services/auth_provider.dart';
import 'services/chat_provider.dart';
import 'services/ai_assistant_provider.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'services/notification_badge_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/register_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sms_settings_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/about_screen.dart';
import 'widgets/ai_side_panel.dart';
import 'widgets/sage_briefing_card.dart';
import 'widgets/sage_full_screen.dart';
import 'widgets/sage_popup_bubble.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({Key? key}) : super(key: key);

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  bool _firebaseReady = false;
  Object? _firebaseError;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _firebaseError = null;
      _firebaseReady = false;
    });
    try {
      await FirebaseService.initializeFirebase();
      // Initialize notifications in background - don't block on errors.
      unawaited(NotificationService().initialize().catchError((_) {}));
      if (!mounted) return;
      setState(() {
        _firebaseReady = true;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _firebaseError = e;
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firebaseReady) {
      return const SmartEatApp();
    }

    return MaterialApp(
      title: 'Smart Eat - Eatery Management System',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _initializing
                ? Column(
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
                      const SizedBox(height: 24),
                      const Text(
                        'SmartEat',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E88E5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Starting...',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 56, color: Color(0xFF1E88E5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to start SmartEat',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _firebaseError?.toString() ??
                            'Failed to initialize required services.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
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
        ChangeNotifierProvider(create: (_) => NotificationBadgeProvider()),
      ],
      child: MaterialApp(
        title: 'Smart Eat - Eatery Management System',
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          return child ?? const SizedBox.shrink();
        },
        routes: {
          '/': (context) => const AuthGate(showLandingWhenSignedOut: true),
          '/login': (context) => const AuthGate(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const AuthGate(child: DashboardScreen()),
          '/settings': (context) => Theme(
                data: AppTheme.dashboardTheme,
                child: const AuthGate(child: SettingsScreen()),
              ),
          '/settings/sms': (context) =>
              const AuthGate(child: SmsSettingsScreen()),
          '/settings/notifications': (context) => Theme(
                data: AppTheme.dashboardTheme,
                child: const AuthGate(child: NotificationSettingsScreen()),
              ),
          '/notifications': (context) => Theme(
                data: AppTheme.dashboardTheme,
                child: const AuthGate(child: NotificationsScreen()),
              ),
          '/profile': (context) => Theme(
                data: AppTheme.dashboardTheme,
                child: const AuthGate(child: ProfileScreen()),
              ),
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

  void _openFromPopup(AIAssistantProvider assistant) {
    assistant.dismissPopup();
    assistant.setPanelExpanded(true);
    if (assistant.activeInsights.isNotEmpty) {
      assistant.setActivePage(assistant.activeInsights.first.page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<AIAssistantProvider>(
          builder: (context, assistant, _) {
            // Sage is admin-only: keep the entire floating layer unmounted
            // while the staff dashboard is showing.
            if (assistant.staffDashboardActive) {
              return const SizedBox.shrink();
            }
            final panelOpen = assistant.isExpanded && !assistant.isFullScreen;
            final popupContent = assistant.popupContent;
            final showPopup = !assistant.isFullScreen &&
                !panelOpen &&
                !assistant.showSageBriefing &&
                assistant.showPopup &&
                assistant.sageAnchorRect != null &&
                popupContent != null &&
                popupContent.isNotEmpty;

            return Stack(
              children: [
                // Rendered first so panel, briefing, and full-screen layers
                // always draw on top of it. The bubble itself clamps to the
                // MediaQuery safe area.
                if (showPopup)
                  Positioned.fill(
                    child: SagePopupBubble(
                      anchor: assistant.sageAnchorRect!,
                      message: popupContent,
                      onOpen: () => _openFromPopup(assistant),
                      onDismiss: assistant.dismissPopup,
                    ),
                  ),
                if (assistant.isFullScreen)
                  const Positioned.fill(child: SageFullScreen()),
                if (panelOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => assistant.setPanelExpanded(false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(color: Colors.black54),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: AISidePanel(),
                  ),
                ],
                if (!assistant.isFullScreen &&
                    assistant.showSageBriefing &&
                    assistant.sageBriefingContent != null)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.38),
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: SageBriefingCard(
                            content: assistant.sageBriefingContent!,
                            onDismiss: assistant.dismissSageBriefing,
                            onAskSage: assistant.openSageChat,
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
  const AuthGate({
    Key? key,
    this.child,
    this.showLandingWhenSignedOut = false,
  }) : super(key: key);

  final Widget? child;
  final bool showLandingWhenSignedOut;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _lastAuthState;
  bool _routeResetScheduled = false;

  // Memoized so rebuilds reuse the same auth stream instead of resubscribing.
  late final Stream<User?> _authStateStream =
      FirebaseAuth.instance.authStateChanges();
  late final StreamSubscription<User?> _preferencesSubscription =
      _authStateStream.listen((user) {
    if (user != null) NotificationService().loadPreferences();
  });

  @override
  void dispose() {
    _preferencesSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateStream,
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
        final wasAuthenticated = _lastAuthState ?? false;

        if (_lastAuthState != null && _lastAuthState != isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          });
        }
        if (!wasAuthenticated && isAuthenticated && !_routeResetScheduled) {
          final routeName = ModalRoute.of(context)?.settings.name;
          if (routeName == '/login') {
            _routeResetScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/',
                (route) => false,
              );
            });
          }
        }
        if (!isAuthenticated) {
          _routeResetScheduled = false;
        }
        _lastAuthState = isAuthenticated;

        if (widget.child != null) {
          if (isAuthenticated) {
            return AIAssistantShell(child: widget.child!);
          }
          return const LoginScreen();
        }

        if (isAuthenticated) {
          return const AIAssistantShell(child: DashboardScreen());
        }

        if (widget.showLandingWhenSignedOut) {
          return const LandingScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
