import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'auth_ui.dart';
import '../services/firebase_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

enum _SignupMode {
  createEatery,
  joinEatery,
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  static const String _emailJsServiceId = 'service_6wsvfjb';
  static const String _emailJsTemplateId = 'template_6auftt7';
  static const String _emailJsPublicKey = 'PF41GpUmvHJ1Ck7c4';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _eateryNameController = TextEditingController();
  final _joinEateryIdController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _registrationStep = 1;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isEmailVerified = false;
  String? _verificationId;
  String _emailForVerification = '';
  String? _generatedEmailCode;
  DateTime? _emailCodeExpiresAt;
  bool _showOtpCard = false;
  late List<TextEditingController> _otpControllers;
  late List<FocusNode> _otpFocusNodes;

  _SignupMode _signupMode = _SignupMode.createEatery;

  bool _isValidEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  late FocusNode _emailFocusNode;
  late FocusNode _passwordFocusNode;
  late FocusNode _confirmPasswordFocusNode;
  late FocusNode _firstNameFocusNode;
  late FocusNode _lastNameFocusNode;
  late FocusNode _eateryNameFocusNode;
  late FocusNode _phoneFocusNode;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
    _confirmPasswordFocusNode = FocusNode();
    _firstNameFocusNode = FocusNode();
    _lastNameFocusNode = FocusNode();
    _eateryNameFocusNode = FocusNode();
    _phoneFocusNode = FocusNode();

    _otpControllers = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());

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

    _emailController.addListener(() {
      final current = _emailController.text.trim().toLowerCase();
      if (current == _emailForVerification) return;

      if (!mounted) return;
      setState(() {
        _emailForVerification = current;
        _isEmailVerified = false;
        _verificationId = null;
        _emailCodeController.clear();
        _generatedEmailCode = null;
        _emailCodeExpiresAt = null;
        _showOtpCard = false;
        for (final c in _otpControllers) {
          c.clear();
        }
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _emailCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _eateryNameController.dispose();
    _joinEateryIdController.dispose();
    _phoneController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _eateryNameFocusNode.dispose();
    _phoneFocusNode.dispose();

    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final n in _otpFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  String _getOtpValue() {
    return _otpControllers.map((c) => c.text.trim()).join();
  }

  void _clearOtpInputs() {
    for (final c in _otpControllers) {
      c.clear();
    }
    _emailCodeController.clear();
  }

  void _handleOtpChanged(int index, String value) {
    final v = value.trim();
    if (v.isEmpty) return;

    final digit = v.replaceAll(RegExp(r'\D'), '');
    if (digit.isEmpty) {
      _otpControllers[index].clear();
      return;
    }

    final d = digit.substring(digit.length - 1);
    if (_otpControllers[index].text != d) {
      _otpControllers[index].text = d;
      _otpControllers[index].selection =
          TextSelection.fromPosition(const TextPosition(offset: 1));
    }

    if (index < _otpFocusNodes.length - 1) {
      FocusScope.of(context).requestFocus(_otpFocusNodes[index + 1]);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _handleOtpBackspace(int index) {
    if (_otpControllers[index].text.isNotEmpty) {
      _otpControllers[index].clear();
      return;
    }
    if (index > 0) {
      FocusScope.of(context).requestFocus(_otpFocusNodes[index - 1]);
      _otpControllers[index - 1].clear();
    }
  }

  Future<void> _startEmailVerification() async {
    if (_isLoading || _isSendingCode || _isVerifyingCode) return;

    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email first.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    await _sendVerificationCode();
    if (!mounted) return;
    if (_verificationId != null && _verificationId!.isNotEmpty) {
      setState(() {
        _showOtpCard = true;
      });
      if (_otpFocusNodes.isNotEmpty) {
        FocusScope.of(context).requestFocus(_otpFocusNodes.first);
      }
    }
  }

  Future<void> _verifyOtpFromBoxes() async {
    _emailCodeController.text = _getOtpValue();
    await _verifyCode();
  }

  Future<void> _continueStep2() async {
    if (_isLoading || _isSendingCode || _isVerifyingCode) return;

    if (!_showOtpCard) {
      if (!_formKey.currentState!.validate()) return;
      await _startEmailVerification();
      return;
    }

    if (!_isEmailVerified) {
      await _verifyOtpFromBoxes();
    }

    if (!mounted) return;
    if (_isEmailVerified) {
      await _register();
    }
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
  }

  void _nextStep() {
    if (_formKey.currentState!.validate()) {
      setState(() => _registrationStep = 2);
    }
  }

  Widget _buildOtpCard() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Enter the 6-digit code sent to your email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            TextButton(
              onPressed:
                  (_isSendingCode || _isLoading) ? null : _sendVerificationCode,
              child: Text(
                _isSendingCode ? 'Sending...' : 'Resend',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 42,
              height: 58,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: primaryColor,
                      width: 2,
                    ),
                  ),
                ),
                onChanged: (v) => _handleOtpChanged(index, v),
                onSubmitted: (_) {
                  if (index == 5) {
                    _verifyOtpFromBoxes();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _isEmailVerified
                ? 'Email verified'
                : 'Verify your email to enable Sign Up',
            style: TextStyle(
              fontSize: 12,
              color: _isEmailVerified
                  ? Colors.green.shade700
                  : Colors.black.withOpacity(0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _previousStep() {
    setState(() => _registrationStep = 1);
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_registrationStep == 1) {
        _nextStep();
      } else {
        _register();
      }
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_isSendingCode || _isLoading || _isVerifyingCode) return;

    final email = _emailController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email first.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isSendingCode = true;
      _isEmailVerified = false;
      _verificationId = null;
      _generatedEmailCode = null;
      _emailCodeExpiresAt = null;
      _clearOtpInputs();
    });

    try {
      if (_emailJsServiceId == 'YOUR_EMAILJS_SERVICE_ID' ||
          _emailJsTemplateId == 'YOUR_EMAILJS_TEMPLATE_ID' ||
          _emailJsPublicKey == 'YOUR_EMAILJS_PUBLIC_KEY') {
        throw Exception(
          'EmailJS is not configured. Please set serviceId/templateId/publicKey in register_screen.dart',
        );
      }

      final code = (Random.secure().nextInt(900000) + 100000).toString();
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: 10));
      final verificationId = now.microsecondsSinceEpoch.toString();

      final payload = {
        'service_id': _emailJsServiceId,
        'template_id': _emailJsTemplateId,
        'user_id': _emailJsPublicKey,
        'template_params': {
          'to_email': email,
          'code': code,
        },
      };

      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'origin': Uri.base.origin,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = response.body.trim();
        throw Exception(
          'Email send failed (${response.statusCode})${body.isEmpty ? '' : ': $body'}',
        );
      }

      if (!mounted) return;
      setState(() {
        _verificationId = verificationId;
        _emailForVerification = email.trim().toLowerCase();
        _generatedEmailCode = code;
        _emailCodeExpiresAt = expiresAt;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code sent. Please check your email.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send verification code: $e'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_isVerifyingCode || _isLoading || _isSendingCode) return;

    final email = _emailController.text.trim();
    final code = _emailCodeController.text.trim();
    final verificationId = _verificationId;

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email first.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    if (verificationId == null || verificationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please request a code first.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit code.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    setState(() => _isVerifyingCode = true);
    try {
      final expectedCode = _generatedEmailCode;
      final expiresAt = _emailCodeExpiresAt;
      final isExpired = expiresAt == null || DateTime.now().isAfter(expiresAt);

      if (expectedCode == null || isExpired) {
        throw Exception('Code expired. Please request a new one.');
      }

      if (code != expectedCode) {
        throw Exception('Invalid verification code');
      }

      if (!mounted) return;
      setState(() => _isEmailVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isEmailVerified = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to verify code: $e'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifyingCode = false);
      }
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
        textInputAction:
            isLastField ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (nextFocus != null) {
            FocusScope.of(context).requestFocus(nextFocus);
          } else if (isLastField) {
            if (_registrationStep == 2) {
              _continueStep2();
            } else {
              _submit();
            }
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
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: errorColor, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: errorDarkColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    if (!_isEmailVerified || _verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your email before signing up.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final userCredential =
          await FirebaseService.createUserWithEmailAndPassword(email, password);

      final uid = userCredential.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('Failed to create user');
      }

      if (_signupMode == _SignupMode.createEatery) {
        final eateryName = _eateryNameController.text.trim();
        if (eateryName.isEmpty) {
          throw Exception('Please enter eatery name');
        }

        final eateryId = await FirebaseService.generateUniqueEateryId();
        await FirebaseService.createEatery(
          eateryId: eateryId,
          name: eateryName,
          ownerUid: uid,
        );

        await FirebaseService.createUserProfile(uid, {
          'email': email,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'eateryName': eateryName,
          'eateryId': eateryId,
          'phoneNumber': _phoneController.text.trim(),
          'role': 'admin',
          'isAdmin': true,
        });
      } else {
        final joinId = _joinEateryIdController.text.trim().toUpperCase();
        if (joinId.isEmpty) {
          throw Exception('Please enter an eatery ID');
        }
        final eatery = await FirebaseService.getEatery(joinId);
        if (eatery == null) {
          throw Exception('Invalid eatery ID');
        }

        await FirebaseService.createUserProfile(uid, {
          'email': email,
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'eateryName': (eatery['name'] ?? '').toString(),
          'eateryId': joinId,
          'phoneNumber': _phoneController.text.trim(),
          'role': 'staff',
          'isAdmin': false,
          'approved': false,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepTitle =
        _registrationStep == 1 ? 'Create New Account' : 'Complete Your Profile';

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
                        constraints: const BoxConstraints(maxWidth: 400),
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
                                stepTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (_registrationStep == 1) ...[
                                _buildAnimatedTextField(
                                  controller: _firstNameController,
                                  label: 'First Name',
                                  icon: Icons.person_outline,
                                  focusNode: _firstNameFocusNode,
                                  nextFocus: _lastNameFocusNode,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your first name';
                                    }
                                    return null;
                                  },
                                ),
                                _buildAnimatedTextField(
                                  controller: _lastNameController,
                                  label: 'Last Name',
                                  icon: Icons.person_outline,
                                  focusNode: _lastNameFocusNode,
                                  nextFocus: _eateryNameFocusNode,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your last name';
                                    }
                                    return null;
                                  },
                                ),
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  width: double.infinity,
                                  child: SegmentedButton<_SignupMode>(
                                    segments: const <ButtonSegment<
                                        _SignupMode>>[
                                      ButtonSegment<_SignupMode>(
                                        value: _SignupMode.createEatery,
                                        label: Text('New Eatery'),
                                        icon: Icon(Icons.storefront),
                                      ),
                                      ButtonSegment<_SignupMode>(
                                        value: _SignupMode.joinEatery,
                                        label: Text('Join Eatery'),
                                        icon: Icon(Icons.group_outlined),
                                      ),
                                    ],
                                    selected: <_SignupMode>{_signupMode},
                                    onSelectionChanged: (value) {
                                      setState(() {
                                        _signupMode = value.first;
                                      });
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    _signupMode == _SignupMode.createEatery
                                        ? 'Create a new eatery and you will be the admin. You can share the Eatery ID with staff later.'
                                        : 'Join an existing eatery as staff using the Eatery ID provided by your admin. Your account will require admin approval.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                if (_signupMode == _SignupMode.createEatery)
                                  _buildAnimatedTextField(
                                    controller: _eateryNameController,
                                    label: 'Eatery Name',
                                    icon: Icons.storefront,
                                    focusNode: _eateryNameFocusNode,
                                    nextFocus: _emailFocusNode,
                                    validator: (value) {
                                      if (_signupMode !=
                                          _SignupMode.createEatery) {
                                        return null;
                                      }
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your eatery name';
                                      }
                                      return null;
                                    },
                                  ),
                                if (_signupMode == _SignupMode.createEatery)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 16),
                                    child: Text(
                                      'This name will be visible to your staff. You can edit details later in the admin area.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        height: 1.3,
                                      ),
                                    ),
                                  )
                                else
                                  _buildAnimatedTextField(
                                    controller: _joinEateryIdController,
                                    label: 'Eatery ID',
                                    icon: Icons.vpn_key_outlined,
                                    focusNode: _eateryNameFocusNode,
                                    nextFocus: _emailFocusNode,
                                    validator: (value) {
                                      if (_signupMode !=
                                          _SignupMode.joinEatery) {
                                        return null;
                                      }
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Enter the eatery ID';
                                      }
                                      final v = value.trim();
                                      if (!RegExp(r'^[A-Za-z0-9]+$')
                                          .hasMatch(v)) {
                                        return 'Eatery ID must be alphanumeric';
                                      }
                                      return null;
                                    },
                                  ),
                                if (_signupMode == _SignupMode.joinEatery)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 16),
                                    child: Text(
                                      'Ask your eatery admin for the Eatery ID (it can be copied from the admin dashboard). You may need to wait for approval after registering.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                _buildAnimatedTextField(
                                  controller: _phoneController,
                                  label: 'Phone Number',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                  focusNode: _phoneFocusNode,
                                  isLastField: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your phone number';
                                    }
                                    if (value.length < 8) {
                                      return 'Please enter a valid phone number';
                                    }
                                    return null;
                                  },
                                ),
                              ] else ...[
                                if (!_showOtpCard) ...[
                                  _buildAnimatedTextField(
                                    controller: _emailController,
                                    label: 'Email',
                                    icon: Icons.email_outlined,
                                    focusNode: _emailFocusNode,
                                    nextFocus: _passwordFocusNode,
                                    keyboardType: TextInputType.emailAddress,
                                    isLastField: false,
                                    maxLines: 1,
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
                                  _buildAnimatedTextField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    icon: Icons.lock_outline,
                                    focusNode: _passwordFocusNode,
                                    nextFocus: _confirmPasswordFocusNode,
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
                                  _buildAnimatedTextField(
                                    controller: _confirmPasswordController,
                                    label: 'Confirm Password',
                                    icon: Icons.lock_outline,
                                    focusNode: _confirmPasswordFocusNode,
                                    isLastField: true,
                                    obscureText: _obscureConfirmPassword,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please confirm your password';
                                      }
                                      if (value != _passwordController.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: Colors.grey,
                                      ),
                                      onPressed:
                                          _toggleConfirmPasswordVisibility,
                                    ),
                                  ),
                                ] else ...[
                                  _buildOtpCard(),
                                ],
                              ],
                              if (_registrationStep == 1) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _nextStep,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
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
                                            'Next',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 50,
                                        child: ElevatedButton(
                                          onPressed: _isLoading
                                              ? null
                                              : () {
                                                  if (_showOtpCard) {
                                                    setState(() {
                                                      _showOtpCard = false;
                                                      _isEmailVerified = false;
                                                    });
                                                    _clearOtpInputs();
                                                  } else {
                                                    _previousStep();
                                                  }
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.grey.shade300,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            elevation: 2,
                                          ),
                                          child: const Text(
                                            'Back',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 50,
                                        child: ElevatedButton(
                                          onPressed: _isLoading
                                              ? null
                                              : _continueStep2,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            elevation: 2,
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                                Color>(
                                                            Colors.white),
                                                  ),
                                                )
                                              : Text(
                                                  _showOtpCard
                                                      ? 'Sign Up'
                                                      : 'Continue',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Already have an account? ',
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context)
                                          .pushReplacementNamed('/login');
                                    },
                                    child: const Text(
                                      'Sign In',
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
