import 'package:flutter/material.dart';

import '../utils/error_messages.dart';

class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({
    super.key,
    this.message,
    this.error,
    this.severity,
    this.operationContext,
    this.onRetry,
    this.actionLabel,
  }) : assert(
          message != null || error != null,
          'Provide either message or error',
        );

  final String? message;
  final Object? error;
  final ErrorSeverity? severity;
  final String? operationContext;
  final VoidCallback? onRetry;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final source = error ?? message;
    final computedSeverity = error != null
        ? ErrorMessageHelper.getSeverity(error)
        : ErrorSeverity.error;
    final resolvedSeverity = severity ??
        (computedSeverity == ErrorSeverity.info
            ? ErrorSeverity.error
            : computedSeverity);
    final color = resolvedSeverity.color;
    final text = error != null
        ? ErrorMessageHelper.getUserFriendlyMessage(
            error,
            operationContext: operationContext,
          )
        : message!;
    final suggestion =
        error != null ? ErrorMessageHelper.getSuggestedAction(error) : null;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ErrorMessageHelper.getIcon(source), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (suggestion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    suggestion,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        actionLabel ?? 'Retry',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
