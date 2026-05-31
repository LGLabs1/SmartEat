import 'package:flutter/material.dart';
import '../utils/haptic_feedback.dart';

/// Reusable confirmation dialog with consistent styling
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? details;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? icon;
  final Color? iconColor;
  final Color? confirmColor;
  final bool isDestructive;

  const ConfirmationDialog({
    Key? key,
    required this.title,
    required this.message,
    this.details,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.icon,
    this.iconColor,
    this.confirmColor,
    this.isDestructive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ??
        (isDestructive ? Colors.red : Theme.of(context).colorScheme.primary);
    final effectiveConfirmColor =
        confirmColor ?? (isDestructive ? Colors.red : null);

    return AlertDialog(
      icon: icon != null
          ? Icon(
              icon,
              color: effectiveIconColor,
              size: 48,
            )
          : null,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (details != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: effectiveIconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: effectiveIconColor.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: effectiveIconColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      details!,
                      style: TextStyle(
                        fontSize: 13,
                        color: effectiveIconColor,
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
          onPressed: () {
            HapticHelper.light();
            Navigator.of(context).pop(false);
          },
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            HapticHelper.medium();
            Navigator.of(context).pop(true);
          },
          style: effectiveConfirmColor != null
              ? FilledButton.styleFrom(backgroundColor: effectiveConfirmColor)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Dialog helper methods
class ConfirmAction {
  /// Show delete confirmation
  static Future<bool> delete(
    BuildContext context, {
    required String itemName,
    String? details,
    String confirmLabel = 'Delete',
  }) async {
    HapticHelper.heavy();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Delete $itemName?',
        message: 'This action cannot be undone.',
        details: details,
        confirmLabel: confirmLabel,
        cancelLabel: 'Keep',
        icon: Icons.delete_outline,
        iconColor: Colors.red,
        confirmColor: Colors.red,
        isDestructive: true,
      ),
    );
    return result ?? false;
  }

  /// Show remove confirmation
  static Future<bool> remove(
    BuildContext context, {
    required String itemName,
    String? details,
  }) async {
    HapticHelper.heavy();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Remove $itemName?',
        message: 'They will lose access immediately.',
        details: details,
        confirmLabel: 'Remove',
        cancelLabel: 'Keep',
        icon: Icons.person_remove_outlined,
        iconColor: Colors.orange,
        confirmColor: Colors.orange,
        isDestructive: true,
      ),
    );
    return result ?? false;
  }

  /// Show discard changes confirmation
  static Future<bool> discardChanges(BuildContext context) async {
    HapticHelper.medium();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ConfirmationDialog(
        title: 'Discard changes?',
        message: 'You have unsaved changes.',
        details: 'Your changes will be lost if you leave this page.',
        confirmLabel: 'Discard',
        cancelLabel: 'Stay',
        icon: Icons.edit_off_outlined,
        iconColor: Colors.orange,
        isDestructive: true,
      ),
    );
    return result ?? false;
  }

  /// Show logout confirmation
  static Future<bool> logout(BuildContext context) async {
    HapticHelper.medium();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ConfirmationDialog(
        title: 'Sign out?',
        message: 'You will need to sign in again.',
        confirmLabel: 'Sign Out',
        cancelLabel: 'Stay',
        icon: Icons.logout,
        iconColor: Colors.blue,
      ),
    );
    return result ?? false;
  }

  /// Show generic confirmation
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? details,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    IconData icon = Icons.help_outline,
    bool isDestructive = false,
  }) async {
    HapticHelper.medium();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        details: details,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }
}

/// Success dialog for actions
class SuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;

  const SuccessDialog({
    Key? key,
    required this.title,
    required this.message,
    this.actionLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.check_circle_outline,
        color: Colors.green,
        size: 48,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          child: Text(actionLabel ?? 'OK'),
        ),
      ],
    );
  }
}

/// Show success dialog helper
Future<void> showSuccess(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
}) async {
  HapticHelper.success();
  await showDialog(
    context: context,
    builder: (context) => SuccessDialog(
      title: title,
      message: message,
      actionLabel: actionLabel,
    ),
  );
}
