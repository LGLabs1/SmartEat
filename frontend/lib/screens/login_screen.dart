import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart' as app_auth;
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/inline_error_banner.dart';
import 'auth_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  Object? _inlineAuthError;

  late FocusNode _emailFocusNode;
  late FocusNode _passwordFocusNode;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _cardFadeAnimation;
  late Animation<Offset> _introSlideAnimation;
  late Animation<Offset> _cardSlideAnimation;

  @override
  void initState() {
    super.initState();

    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _cardFadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: const Interval(0.22, 1, curve: Curves.easeOut),
    );
    _introSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: const Interval(0.15, 1, curve: Curves.easeOutCubic),
      ),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _clearInlineAuthError() {
    if (!mounted) return;
    setState(() => _inlineAuthError = null);
  }

  void _focusFieldForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
      case 'user-not-found':
        _emailFocusNode.requestFocus();
        break;
      case 'wrong-password':
        _passwordFocusNode.requestFocus();
        break;
    }
  }

  void _submit() {
    if (_inlineAuthError != null) {
      setState(() => _inlineAuthError = null);
    }
    if (_formKey.currentState!.validate()) {
      _login();
    }
  }

  void _goBackToLanding() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/');
    }
  }

  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    int? maxLines = 1,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    bool isLastField = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        cursorColor: AppTheme.sageAccent,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        textInputAction:
            isLastField ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (nextFocus != null) {
            FocusScope.of(context).requestFocus(nextFocus);
          } else if (isLastField) {
            _submit();
          }
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: const TextStyle(
            color: AppTheme.sageAccent,
            fontWeight: FontWeight.w700,
          ),
          prefixIcon: Icon(icon, color: AppTheme.sageAccent, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                const BorderSide(color: AppTheme.sageAccent, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: errorColor.withValues(alpha: 0.8)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: errorColor, width: 1.6),
          ),
          errorStyle: TextStyle(
            color: errorColor.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _inlineAuthError = null;
    });

    try {
      await context.read<app_auth.AuthProvider>().login(
            _emailController.text.trim(),
            _passwordController.text,
          );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _inlineAuthError = e);
        _focusFieldForAuthError(e);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _inlineAuthError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.sageNavy,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.sageNavy,
                    AppTheme.sagePanel,
                    const Color(0xFF070D18),
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: -180,
            right: -140,
            child: _SageGlow(
              size: 460,
              color: AppTheme.sageBlue.withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            bottom: -210,
            left: -160,
            child: _SageGlow(
              size: 520,
              color: AppTheme.sageBlueDeep.withValues(alpha: 0.2),
            ),
          ),
          Positioned(
            top: 220,
            left: 90,
            child: _SageGlow(
              size: 220,
              color: AppTheme.sageCyan.withValues(alpha: 0.08),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 48 : 20,
                      vertical: wide ? 32 : 20,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _introSlideAnimation,
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: _buildBrandIntro(compact: false),
                                    ),
                                    const SizedBox(width: 56),
                                    Expanded(
                                      flex: 4,
                                      child: FadeTransition(
                                        opacity: _cardFadeAnimation,
                                        child: SlideTransition(
                                          position: _cardSlideAnimation,
                                          child: _buildLoginCard(),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildBrandIntro(compact: true),
                                    const SizedBox(height: 26),
                                    FadeTransition(
                                      opacity: _cardFadeAnimation,
                                      child: SlideTransition(
                                        position: _cardSlideAnimation,
                                        child: _buildLoginCard(),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandIntro({required bool compact}) {
    final alignment =
        compact ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = compact ? TextAlign.center : TextAlign.start;

    return Container(
      key: const Key('login-welcome-panel'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF101A2E).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 68 : 82,
                height: compact ? 68 : 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.sageBlue.withValues(alpha: 0.22),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Lottie.asset(
                    'assets/animations/E V E.json',
                    fit: BoxFit.cover,
                    repeat: true,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SAGE AI',
                      style: TextStyle(
                        color: AppTheme.sageAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your eatery, understood.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 20 : 28),
          Text(
            compact ? 'Welcome back.' : 'Welcome back to\nSmartEat.',
            textAlign: textAlign,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 32 : 46,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'Sign in to run orders, inventory, attendance, and Sage-powered insights from one calm workspace.',
              textAlign: textAlign,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: compact ? 14 : 16,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 34),
            _buildBrandBullet(
              icon: Icons.auto_awesome_rounded,
              label: 'Sage insights that surface what matters',
            ),
            const SizedBox(height: 14),
            _buildBrandBullet(
              icon: Icons.groups_rounded,
              label: 'One workspace for your whole team',
            ),
            const SizedBox(height: 14),
            _buildBrandBullet(
              icon: Icons.insights_rounded,
              label: 'Live visibility across every shift',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrandBullet({required IconData icon, required String label}) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.sageBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: AppTheme.sageAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('login-back-to-home'),
                  tooltip: 'Back to home',
                  onPressed: _goBackToLanding,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white.withValues(alpha: 0.7),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 36, height: 36),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.sageBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 12,
                        color: AppTheme.sageAccent,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'SECURE SIGN IN',
                        style: TextStyle(
                          color: AppTheme.sagePaleBlue,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.sageBlue.withValues(alpha: 0.2),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const AppLogo(height: 52),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Eatery Management System',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.sageAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to your workspace',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 24),
            if (_inlineAuthError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InlineErrorBanner(
                  key: const Key('login-inline-error'),
                  error: _inlineAuthError!,
                  operationContext: 'auth',
                  onRetry: _clearInlineAuthError,
                  actionLabel: 'Dismiss',
                ),
              ),
            _buildAnimatedTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.email_outlined,
              focusNode: _emailFocusNode,
              nextFocus: _passwordFocusNode,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                    .hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            _buildAnimatedTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              focusNode: _passwordFocusNode,
              isLastField: true,
              obscureText: _obscurePassword,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                onPressed: _togglePasswordVisibility,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('login-forgot-password'),
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).pushNamed('/forgot-password'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: AppTheme.sageAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Opacity(
              opacity: _isLoading ? 0.75 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.sageGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.sageBlue.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    key: const Key('login-sign-in'),
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  key: const Key('login-create-account'),
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/register');
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sign Up',
                    style: TextStyle(
                      color: AppTheme.sageAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _goBackToLanding,
              icon: const Icon(Icons.arrow_back_rounded, size: 14),
              label: const Text('Back to home'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.5),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SageGlow extends StatelessWidget {
  const _SageGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
