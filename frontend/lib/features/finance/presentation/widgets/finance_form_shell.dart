import 'package:flutter/material.dart';

/// Responsive modal shell shared by the finance create/edit forms.
///
/// Provides a compact branded header, a scrollable body split into labelled
/// [FinanceFormSection]s, and a pinned action bar so the primary action is
/// always reachable regardless of device height. On wide screens the dialog
/// grows to a comfortable reading width; on phones it respects the viewport.
class FinanceFormShell extends StatelessWidget {
  const FinanceFormShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.children,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<Widget> children;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final String saveLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width >= 560 ? 520.0 : null;
    final maxHeight = media.size.height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, scheme, media),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            _actionBar(context, scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme, MediaQueryData media) {
    final compact = media.size.width < 380;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.14),
            accentColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (onDelete != null) ...[
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
            ),
            const Spacer(),
          ] else
            const Spacer(),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSave,
            child: Text(saveLabel),
          ),
        ],
      ),
    );
  }
}

/// A titled group of related form fields with optional helper [description].
class FinanceFormSection extends StatelessWidget {
  const FinanceFormSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.description,
  });

  final String title;
  final IconData? icon;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
              ],
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Small spacing helper used between stacked fields inside a section.
const Widget financeFieldGap = SizedBox(height: 12);
