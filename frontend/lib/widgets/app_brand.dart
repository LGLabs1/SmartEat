import 'package:flutter/material.dart';
import '../theme.dart';
import 'app_logo.dart';

enum AppBrandSize { compact, full }

class AppBrand extends StatelessWidget {
  const AppBrand({
    Key? key,
    this.eateryName,
    this.compact = false,
    this.size = AppBrandSize.full,
    this.logoHeight,
  }) : super(key: key ?? const Key('app-brand'));

  final String? eateryName;
  final bool compact;
  final AppBrandSize size;
  final double? logoHeight;

  @override
  Widget build(BuildContext context) {
    final isCompact = compact || size == AppBrandSize.compact;
    final height = logoHeight ?? (isCompact ? 22.0 : 28.0);
    final label = eateryName?.trim() ?? '';
    final showLabel = !isCompact && label.isNotEmpty;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 5 : 8,
        vertical: isCompact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(isCompact ? 8 : 12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogo(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            backgroundColor: AppTheme.sagePanel,
            borderRadius: isCompact ? 5 : 7,
          ),
          if (showLabel) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.sageCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
