import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// User-friendly error message mapper
/// Converts technical errors into actionable, user-friendly messages
class ErrorMessageHelper {
  /// Get user-friendly message from any error
  static String getUserFriendlyMessage(dynamic error,
      {String? operationContext}) {
    final errorString = _extractErrorString(error);

    // Check for specific error patterns
    for (final pattern in _errorPatterns) {
      if (pattern.matches(errorString)) {
        return pattern.userMessage;
      }
    }

    // Context-specific fallbacks
    if (operationContext != null) {
      final contextMessage =
          _contextSpecificMessages[operationContext]?[errorString];
      if (contextMessage != null) return contextMessage;
    }

    // Generic fallback
    return _genericMessage(errorString);
  }

  /// Get appropriate action/suggestion for error
  static String? getSuggestedAction(dynamic error) {
    final errorString = _extractErrorString(error).toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return 'Please check your internet connection and try again.';
    }

    if (errorString.contains('permission') ||
        errorString.contains('unauthorized') ||
        errorString.contains('denied')) {
      return 'You may not have permission for this action. Contact your admin if you believe this is an error.';
    }

    if (errorString.contains('not-found') ||
        errorString.contains('not found')) {
      return 'The item you\'re looking for may have been deleted or moved.';
    }

    if (errorString.contains('already-exists') ||
        errorString.contains('already exists')) {
      return 'This item already exists. Try using a different name or ID.';
    }

    if (errorString.contains('insufficient') ||
        errorString.contains('out of stock') ||
        errorString.contains('not enough')) {
      return 'Please check inventory levels or update stock before proceeding.';
    }

    if (errorString.contains('invalid-argument') ||
        errorString.contains('invalid argument')) {
      return 'Please check that all required fields are filled correctly.';
    }

    return null;
  }

  /// Get error severity level
  static ErrorSeverity getSeverity(dynamic error) {
    final errorString = _extractErrorString(error).toLowerCase();

    if (errorString.contains('permission') ||
        errorString.contains('unauthorized') ||
        errorString.contains('denied')) {
      return ErrorSeverity.warning;
    }

    if (errorString.contains('failed') ||
        errorString.contains('error') ||
        errorString.contains('exception')) {
      return ErrorSeverity.error;
    }

    if (errorString.contains('network') ||
        errorString.contains('timeout') ||
        errorString.contains('connection')) {
      return ErrorSeverity.warning;
    }

    return ErrorSeverity.info;
  }

  /// Get icon for error type
  static IconData getIcon(dynamic error) {
    final errorString = _extractErrorString(error).toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return Icons.wifi_off;
    }

    if (errorString.contains('permission') ||
        errorString.contains('unauthorized') ||
        errorString.contains('denied')) {
      return Icons.lock_outline;
    }

    if (errorString.contains('not-found') ||
        errorString.contains('not found')) {
      return Icons.search_off;
    }

    if (errorString.contains('success')) {
      return Icons.check_circle_outline;
    }

    return Icons.error_outline;
  }

  /// Show user-friendly snackbar
  static void showSnackBar(
    BuildContext context,
    dynamic error, {
    String? operationContext,
    bool showAction = true,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    final message =
        getUserFriendlyMessage(error, operationContext: operationContext);
    final action = showAction ? getSuggestedAction(error) : null;
    final severity = getSeverity(error);

    final backgroundColor = switch (severity) {
      ErrorSeverity.error => Colors.red.shade800,
      ErrorSeverity.warning => Colors.orange.shade800,
      ErrorSeverity.info => Colors.blue.shade800,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  getIcon(error),
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 4),
              Text(
                action,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        action: onAction != null
            ? SnackBarAction(
                label: actionLabel ?? 'Retry',
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show error dialog for critical errors
  static void showErrorDialog(
    BuildContext context,
    dynamic error, {
    String? title,
    String? operationContext,
    VoidCallback? onRetry,
  }) {
    final message =
        getUserFriendlyMessage(error, operationContext: operationContext);
    final action = getSuggestedAction(error);
    final severity = getSeverity(error);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          getIcon(error),
          color: severity.color,
          size: 48,
        ),
        title: Text(title ?? _getDefaultTitle(severity)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (action != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: severity.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        color: severity.color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        action,
                        style: TextStyle(
                          color: severity.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          if (onRetry != null)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Try Again'),
            ),
        ],
      ),
    );
  }

  // Private helpers
  static String _extractErrorString(dynamic error) {
    if (error == null) return '';

    // Firebase exception
    if (error is FirebaseException) {
      final code = error.code;
      final message = error.message ?? '';
      return '$code: $message';
    }

    // Unwrap nested errors (Flutter web boxed errors)
    dynamic current = error;
    for (int i = 0; i < 3; i++) {
      if (current is FirebaseException) {
        return '${current.code}: ${current.message}';
      }
      try {
        final next = current.error;
        if (next == null || next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }

    return error.toString();
  }

  static String _genericMessage(String errorString) {
    // Hide technical details, show generic message
    return 'Something went wrong. Please try again.';
  }

  static String _getDefaultTitle(ErrorSeverity severity) {
    return switch (severity) {
      ErrorSeverity.error => 'Error',
      ErrorSeverity.warning => 'Warning',
      ErrorSeverity.info => 'Notice',
    };
  }
}

/// Error severity levels
enum ErrorSeverity {
  error,
  warning,
  info;

  Color get color {
    return switch (this) {
      ErrorSeverity.error => Colors.red,
      ErrorSeverity.warning => Colors.orange,
      ErrorSeverity.info => Colors.blue,
    };
  }
}

/// Error pattern matcher
class _ErrorPattern {
  final List<String> keywords;
  final String userMessage;

  const _ErrorPattern({
    required this.keywords,
    required this.userMessage,
  });

  bool matches(String errorString) {
    final lower = errorString.toLowerCase();
    return keywords.any((keyword) => lower.contains(keyword.toLowerCase()));
  }
}

/// Common error patterns and their user-friendly messages
final List<_ErrorPattern> _errorPatterns = [
  _ErrorPattern(
    keywords: ['permission-denied', 'unauthorized', 'not authorized'],
    userMessage: 'You don\'t have permission to perform this action.',
  ),
  _ErrorPattern(
    keywords: ['network-request-failed', 'network error', 'connection refused'],
    userMessage: 'Unable to connect to the server. Please check your internet.',
  ),
  _ErrorPattern(
    keywords: ['timeout', 'timed out'],
    userMessage: 'The request took too long. Please try again.',
  ),
  _ErrorPattern(
    keywords: ['not-found', 'document not found'],
    userMessage: 'The requested item could not be found.',
  ),
  _ErrorPattern(
    keywords: ['already-exists', 'duplicate'],
    userMessage: 'This item already exists. Please use a different identifier.',
  ),
  _ErrorPattern(
    keywords: ['invalid-argument', 'bad request'],
    userMessage:
        'Some information provided is invalid. Please check and try again.',
  ),
  _ErrorPattern(
    keywords: ['resource-exhausted', 'quota exceeded'],
    userMessage:
        'System resources are temporarily limited. Please try again shortly.',
  ),
  _ErrorPattern(
    keywords: ['unauthenticated', 'not signed in'],
    userMessage: 'Your session has expired. Please sign in again.',
  ),
  _ErrorPattern(
    keywords: ['transaction', 'concurrent'],
    userMessage:
        'Another operation is in progress. Please wait a moment and try again.',
  ),
  _ErrorPattern(
    keywords: ['insufficient stock', 'out of stock', 'not enough inventory'],
    userMessage: 'Not enough stock available for this order.',
  ),
  _ErrorPattern(
    keywords: ['cancelled', 'canceled'],
    userMessage: 'The operation was cancelled.',
  ),
];

/// Context-specific error messages
final Map<String, Map<String, String>> _contextSpecificMessages = {
  'order': {
    'insufficient stock':
        'Not enough inventory to fulfill this order. Please check stock levels.',
    'not-found': 'Order not found. It may have been deleted or completed.',
  },
  'inventory': {
    'not-found': 'Inventory item not found. It may have been deleted.',
    'duplicate': 'An item with this name already exists in inventory.',
  },
  'menu': {
    'not-found': 'Menu item not found. It may have been removed.',
    'duplicate': 'A menu item with this name already exists.',
  },
  'staff': {
    'not-found': 'Staff member not found.',
    'duplicate': 'A staff member with this email already exists.',
  },
  'auth': {
    'wrong-password': 'Incorrect password. Please try again.',
    'user-not-found': 'No account found with this email.',
    'invalid-email': 'Please enter a valid email address.',
    'weak-password': 'Password is too weak. Please use at least 6 characters.',
    'email-already-in-use': 'An account with this email already exists.',
  },
};
