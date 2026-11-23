import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

class SmartEatHeader extends StatelessWidget implements PreferredSizeWidget {
  const SmartEatHeader({
    Key? key,
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.toolbarHeight = 64,
    this.showBackButton = false,
  }) : super(key: key);

  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final double toolbarHeight;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final resolvedLeading = leading ??
        (showBackButton && Navigator.of(context).canPop()
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null);
    final resolvedTitle = title ??
        (titleText == null
            ? null
            : Text(
                titleText!,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ));

    return AppBar(
      automaticallyImplyLeading: false,
      leading: resolvedLeading,
      title: resolvedTitle,
      actions: actions,
      toolbarHeight: toolbarHeight,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
      flexibleSpace: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: const BoxDecoration(gradient: AppTheme.sageGradient),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight + 1);
}
