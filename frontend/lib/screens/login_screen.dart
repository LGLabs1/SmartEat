import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart' as app_auth;
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

  // Focus nodes for text fields
  late FocusNode _emailFocusNode;
  late FocusNode _passwordFocusNode;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize focus nodes
    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutQuart,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _passwordController.dispose();

    // Dispose focus nodes
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _login();
    }
  }

  // Helper method to build animated text field
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
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: primaryColor, size: 20),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: primaryColor,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: errorColor,
              width: 2,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: errorDarkColor,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await context.read<app_auth.AuthProvider>().login(
            _emailController.text.trim(),
            _passwordController.text,
          );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: errorColor,
          ),
        );
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade100,
              Colors.blue.shade300,
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: AnimatedGradientShimmer(),
            ),
            // Animated background circles with different timings and scales
            Positioned(
              top: -120,
              right: -120,
              child: AnimatedCircle(
                size: 400,
                color: const Color.fromRGBO(255, 255, 255, 0.08),
                duration: const Duration(seconds: 12),
                beginScale: 0.7,
                endScale: 1.3,
                offset: const Offset(-10, 10),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -80,
              child: AnimatedCircle(
                size: 300,
                color: const Color.fromRGBO(63, 81, 181, 0.14),
                duration: const Duration(seconds: 10),
                beginScale: 0.8,
                endScale: 1.4,
                offset: const Offset(15, -5),
                curve: Curves.easeInOutCubic,
              ),
            ),
            Positioned(
              top: 150,
              left: -50,
              child: AnimatedCircle(
                size: 150,
                color: const Color.fromRGBO(33, 150, 243, 0.10),
                duration: const Duration(seconds: 14),
                beginScale: 0.9,
                endScale: 1.5,
                offset: const Offset(5, 10),
              ),
            ),
            Positioned(
              top: 40,
              left: 120,
              child: AnimatedCircle(
                size: 220,
                color: const Color.fromRGBO(255, 255, 255, 0.06),
                duration: const Duration(seconds: 18),
                beginScale: 0.75,
                endScale: 1.35,
                offset: const Offset(-12, 6),
                curve: Curves.easeInOutCubic,
              ),
            ),
            Positioned(
              bottom: 30,
              right: -60,
              child: AnimatedCircle(
                size: 260,
                color: const Color.fromRGBO(33, 150, 243, 0.08),
                duration: const Duration(seconds: 16),
                beginScale: 0.85,
                endScale: 1.45,
                offset: const Offset(10, -12),
              ),
            ),
            // Floating icons with different animations
            Positioned(
              top: 120,
              right: 40,
              child: FloatingIcon(
                icon: Icons.restaurant_menu,
                color: const Color.fromRGBO(255, 255, 255, 0.18),
                size: 70,
                duration: const Duration(seconds: 5),
                offset: const Offset(0, 25),
                rotate: false,
              ),
            ),
            Positioned(
              bottom: 120,
              left: 40,
              child: FloatingIcon(
                icon: Icons.coffee,
                color: const Color.fromRGBO(255, 255, 255, 0.16),
                size: 60,
                duration: const Duration(seconds: 6),
                offset: const Offset(0, -20),
                rotate: true,
              ),
            ),
            Positioned(
              top: 200,
              right: 100,
              child: FloatingIcon(
                icon: Icons.local_dining,
                color: const Color.fromRGBO(255, 255, 255, 0.14),
                size: 40,
                duration: const Duration(seconds: 7),
                offset: const Offset(15, 15),
                rotate: true,
              ),
            ),
            Positioned(
              top: 260,
              left: 18,
              child: FloatingIcon(
                icon: Icons.receipt_long,
                color: const Color.fromRGBO(255, 255, 255, 0.12),
                size: 46,
                duration: const Duration(seconds: 8),
                offset: const Offset(-8, 10),
                rotate: false,
              ),
            ),
            Positioned(
              bottom: 190,
              right: 30,
              child: FloatingIcon(
                icon: Icons.storefront,
                color: const Color.fromRGBO(255, 255, 255, 0.10),
                size: 52,
                duration: const Duration(seconds: 9),
                offset: const Offset(10, -6),
                rotate: true,
              ),
            ),
            Positioned(
              bottom: 40,
              left: 140,
              child: FloatingIcon(
                icon: Icons.fastfood,
                color: const Color.fromRGBO(255, 255, 255, 0.10),
                size: 44,
                duration: const Duration(seconds: 10),
                offset: const Offset(-6, -10),
                rotate: true,
              ),
            ),
            Positioned(
              top: 320,
              right: 10,
              child: FloatingIcon(
                icon: Icons.shopping_bag_outlined,
                color: const Color.fromRGBO(255, 255, 255, 0.09),
                size: 48,
                duration: const Duration(seconds: 11),
                offset: const Offset(8, 12),
                rotate: false,
              ),
            ),
            Positioned(
              top: 80,
              left: 20,
              child: FloatingIcon(
                icon: Icons.local_cafe,
                color: const Color.fromRGBO(255, 255, 255, 0.08),
                size: 40,
                duration: const Duration(seconds: 12),
                offset: const Offset(-10, 6),
                rotate: true,
              ),
            ),
            // Main content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Card(
                      elevation: 20,
                      shadowColor: const Color.fromRGBO(0, 0, 0, 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20.0),
                        constraints: const BoxConstraints(
                          maxWidth: 400,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white,
                              Colors.grey.shade50,
                            ],
                          ),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Logo and Title Section
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.shade400,
                                      Colors.indigo.shade600,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color.fromRGBO(
                                          33, 150, 243, 0.08),
                                      blurRadius: 12,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.restaurant,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Smart Eat',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Eatery Management System',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),

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
                                  if (!RegExp(
                                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                      .hasMatch(value)) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),

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
                                    color: Colors.grey,
                                  ),
                                  onPressed: _togglePasswordVisibility,
                                ),
                              ),
                              const SizedBox(height: 8),

                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context)
                                          .pushReplacementNamed('/register');
                                    },
                                    child: const Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
