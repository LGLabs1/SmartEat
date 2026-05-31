import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isLoggingOut = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _initAuthListener();
    // Defer initial user check to ensure Firebase is fully initialized
    Future.delayed(const Duration(milliseconds: 100), () {
      _user = FirebaseAuth.instance.currentUser;
      notifyListeners();
    });
  }

  void _initAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userCredential = await FirebaseService.signInWithEmailAndPassword(
        email,
        password,
      );

      _user = userCredential.user;
      _error = null;
      _isLoading = false;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _user = null;
      _error = _getFirebaseAuthErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      throw Exception(_error);
    } catch (e) {
      _user = null;
      _error = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      throw Exception(_error);
    }
  }

  Future<UserCredential?> register(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userCredential =
          await FirebaseService.createUserWithEmailAndPassword(
        email,
        password,
      );

      if (userCredential.user != null) {
        // Create basic user profile in Firestore
        await FirebaseService.createUserProfile(userCredential.user!.uid, {
          'email': email,
          'name': email.split('@')[0], // Use email prefix as default name
          'role': 'staff', // Default role
          'eateryId': '', // Will be set later by admin
          'createdAt': DateTime.now().toIso8601String(),
        });

        _user = userCredential.user;
        _error = null;
        return userCredential;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      _error = _getFirebaseAuthErrorMessage(e);
      return null;
    } catch (e) {
      _error = 'An unexpected error occurred: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_isLoggingOut) {
      return;
    }
    _isLoggingOut = true;
    try {
      _error = null;
      await FirebaseService.signOut();
      // Auth state listener will handle setting _user = null
    } catch (e) {
      _error = 'Failed to logout: $e';
      notifyListeners();
    } finally {
      _isLoggingOut = false;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    if (_user == null) return null;

    try {
      return await FirebaseService.getUserProfile(_user!.uid);
    } catch (e) {
      _error = 'Failed to load user profile: $e';
      notifyListeners();
      return null;
    }
  }

  void setError(String error) {
    _error = error;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error. Please check your internet connection (Wi‑Fi/mobile data), disable VPN/proxy, and ensure device date/time is set automatically.';
      case 'app-not-authorized':
        return 'This app is not authorized to use Firebase Authentication. Re-check Android package name, SHA-1/SHA-256 in Firebase Console, and google-services.json.';
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many unsuccessful login attempts. Please try again later.';
      default:
        return 'Authentication failed (${e.code}): ${e.message}';
    }
  }
}
