import 'package:flutter/services.dart';

/// Haptic feedback helper for tactile UI responses
class HapticHelper {
  static bool _enabled = true;
  
  /// Enable/disable haptic feedback globally
  static set enabled(bool value) => _enabled = value;
  static bool get enabled => _enabled;
  
  /// Light impact - for subtle feedback (hover, small taps)
  static void light() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }
  
  /// Medium impact - for standard interactions (button presses)
  static void medium() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }
  
  /// Heavy impact - for significant actions (confirmations, warnings)
  static void heavy() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }
  
  /// Selection click - for picker/selector interactions
  static void selection() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }
  
  /// Success vibration pattern
  static void success() async {
    if (!_enabled) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.lightImpact();
  }
  
  /// Error/warning vibration pattern
  static void error() async {
    if (!_enabled) return;
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }
  
  /// Add to cart - specific feedback for POS
  static void addToCart() {
    if (!_enabled) return;
    // Subtle double-tap feel
    HapticFeedback.lightImpact();
  }
  
  /// Remove from cart
  static void removeFromCart() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }
  
  /// Order complete - celebratory feedback
  static void orderComplete() async {
    if (!_enabled) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.lightImpact();
  }
}
