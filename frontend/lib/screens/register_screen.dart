import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';

import '../services/firebase_service.dart';
import '../theme.dart';
import '../utils/phone_utils.dart';
import '../widgets/app_logo.dart';
import 'auth_ui.dart';

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
  static const String _emailJsServiceId = 'service_a739dzd';
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
  String? _registrationError;
  late List<TextEditingController> _otpControllers;
  late List<FocusNode> _otpFocusNodes;

  _SignupMode _signupMode = _SignupMode.createEatery;

  bool _isValidEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  String _friendlyRegistrationError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'weak-password':
          return 'Please choose a password with at least 6 characters.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Try signing in instead.';
        case 'invalid-email':
          return "That email address doesn't look right. Please check it and try again.";
        case 'network-request-failed':
          return "We couldn't connect right now. Check your connection and try again.";
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'operation-not-allowed':
          return "Email sign-up isn't available right now. Please try again later.";
      }
    }

    final message = error.toString().toLowerCase();
    if (message.contains('eatery name')) {
      return 'Please enter your eatery name.';
    }
    if (message.contains('eatery id')) {
      return 'That eatery ID was not found. Check it with your admin and try again.';
    }
    return "We couldn't create your account right now. Please try again.";
  }

  void _showRegistrationError(String message) {
    if (!mounted) return;
    setState(() => _registrationError = message);
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
  late Animation<double> _cardFadeAnimation;
  late Animation<Offset> _introSlideAnimation;
  late Animation<Offset> _cardSlideAnimation;

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

  void _goBackToLanding() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/');
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _nextStep() {
    if (_formKey.currentState!.validate()) {
      setState(() => _registrationStep = 2);
    }
  }

  Widget _buildOtpCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isEmailVerified)
          Container(
            key: const Key('register-otp-sent-indicator'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.sageSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.sageSuccess.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppTheme.sageSuccess,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verification code sent',
                        style: TextStyle(
                          color: AppTheme.sageSuccess,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Check your inbox for the 6-digit code.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Enter the 6-digit code sent to your email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed:
                  (_isSendingCode || _isLoading) ? null : _sendVerificationCode,
              child: Text(
                _isSendingCode ? 'Sending...' : 'Resend',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.sageAccent,
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
                key: Key('register-otp-$index'),
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                maxLength: 1,
                cursorColor: AppTheme.sageAccent,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.sageAccent,
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
                  ? AppTheme.sageSuccess
                  : Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _previousStep() {
    setState(() {
      _registrationStep = 1;
      _registrationError = null;
    });
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
        cursorColor: AppTheme.sageAccent,
        style: const TextStyle(color: Colors.white, fontSize: 15),
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

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      _showRegistrationError('Passwords do not match.');
      return;
    }

    if (!_isEmailVerified || _verificationId == null) {
      _showRegistrationError('Please verify your email before signing up.');
      return;
    }

    final normalizedPhone = PhoneUtils.normalizePhMobile(_phoneController.text);
    if (normalizedPhone == null) {
      _showRegistrationError('Please enter a valid Philippine mobile number.');
      return;
    }

    setState(() {
      _isLoading = true;
      _registrationError = null;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final userCredential =
          await FirebaseService.createUserWithEmailAndPassword(email, password);

      final uid = userCredential.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('Failed to create user');
      }

      final registeredName =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();
      if (registeredName.isNotEmpty) {
        await userCredential.user?.updateDisplayName(registeredName);
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
          'phone': normalizedPhone,
          'phoneNumber': normalizedPhone,
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
          'phone': normalizedPhone,
          'phoneNumber': normalizedPhone,
          'role': 'staff',
          'isAdmin': false,
          'approved': false,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _showRegistrationError(_friendlyRegistrationError(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildRegistrationError() {
    final message = _registrationError;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const Key('register-error'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: errorColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: errorColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFFFCDD2),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return Opacity(
      opacity: onPressed == null ? 0.75 : 1,
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
            key: key,
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.78),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepTitle = _registrationStep == 1
        ? 'Create your account'
        : 'Complete your profile';
    final stepLabel = _registrationStep == 1 ? 'STEP 1 OF 2' : 'STEP 2 OF 2';

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
            child: _RegisterGlow(
              size: 460,
              color: AppTheme.sageBlue.withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            bottom: -210,
            left: -160,
            child: _RegisterGlow(
              size: 520,
              color: AppTheme.sageBlueDeep.withValues(alpha: 0.2),
            ),
          ),
          Positioned(
            top: 220,
            left: 90,
            child: _RegisterGlow(
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
                                          child: _buildSignupCard(
                                              stepTitle, stepLabel),
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
                                        child: _buildSignupCard(
                                            stepTitle, stepLabel),
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
      key: const Key('register-welcome-panel'),
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
            compact ? 'Join SmartEat.' : 'Start your\nSmartEat story.',
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
              'Create an eatery or join your team, then manage orders, inventory, attendance, and Sage insights in one calm workspace.',
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
            _buildIntroBullet(
              icon: Icons.bolt_rounded,
              label: 'Set up in minutes, no technical work',
            ),
            const SizedBox(height: 14),
            _buildIntroBullet(
              icon: Icons.groups_rounded,
              label: 'Admin or staff access from day one',
            ),
            const SizedBox(height: 14),
            _buildIntroBullet(
              icon: Icons.auto_awesome_rounded,
              label: 'Sage insights ready when you are',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntroBullet({required IconData icon, required String label}) {
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

  Widget _buildSignupCard(String stepTitle, String stepLabel) {
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
                  key: const Key('register-back-to-home'),
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
                  child: Text(
                    stepLabel,
                    style: const TextStyle(
                      color: AppTheme.sagePaleBlue,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
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
            Text(
              stepTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
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
                  segments: const <ButtonSegment<_SignupMode>>[
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
                      _registrationError = null;
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor:
                        WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppTheme.sageBlue;
                      }
                      return Colors.white.withValues(alpha: 0.05);
                    }),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    side: WidgetStateProperty.all(
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _signupMode == _SignupMode.createEatery
                      ? 'Start your own eatery and invite your team later with the ID we give you.'
                      : 'Join your team using the ID they shared with you. A team owner will approve your account.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.35,
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
                    if (_signupMode != _SignupMode.createEatery) {
                      return null;
                    }
                    if (value == null || value.isEmpty) {
                      return 'Please enter your eatery name';
                    }
                    return null;
                  },
                )
              else
                _buildAnimatedTextField(
                  controller: _joinEateryIdController,
                  label: 'Eatery ID',
                  icon: Icons.vpn_key_outlined,
                  focusNode: _eateryNameFocusNode,
                  nextFocus: _emailFocusNode,
                  validator: (value) {
                    if (_signupMode != _SignupMode.joinEatery) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the eatery ID';
                    }
                    final v = value.trim();
                    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(v)) {
                      return 'Use letters and numbers only for the Eatery ID.';
                    }
                    return null;
                  },
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _signupMode == _SignupMode.createEatery
                      ? 'Your team will see this name. You can change it later in Settings.'
                      : 'Ask your team for the Eatery ID. You may need to wait for approval after signing up.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.35,
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
                  if (!PhoneUtils.isValidPhMobile(value)) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              _buildGradientButton(
                key: const Key('register-continue'),
                label: 'Continue',
                onPressed: _isLoading ? null : _nextStep,
                loading: _isLoading,
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
                      color: Colors.white.withValues(alpha: 0.45),
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
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    onPressed: _toggleConfirmPasswordVisibility,
                  ),
                ),
              ] else ...[
                _buildOtpCard(),
              ],
              _buildRegistrationError(),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildBackButton(
                      key: const Key('register-back'),
                      label: 'Back',
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_showOtpCard) {
                                setState(() {
                                  _showOtpCard = false;
                                  _isEmailVerified = false;
                                  _registrationError = null;
                                });
                                _clearOtpInputs();
                              } else {
                                _previousStep();
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGradientButton(
                      key: const Key('register-sign-up'),
                      label: _showOtpCard ? 'Sign Up' : 'Continue',
                      onPressed: _isLoading ? null : _continueStep2,
                      loading: _isLoading,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  key: const Key('register-sign-in'),
                  onPressed: _goToLogin,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sign In',
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

class _RegisterGlow extends StatelessWidget {
  const _RegisterGlow({required this.size, required this.color});

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
