import 'package:flutter/material.dart';
import '../../theme.dart';

class SageHoverCard extends StatefulWidget {
  const SageHoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20,
    this.accent = AppTheme.sageAccent,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color accent;

  @override
  State<SageHoverCard> createState() => _SageHoverCardState();
}

class _SageHoverCardState extends State<SageHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: widget.margin,
        transform: _hovered && widget.onTap != null
            ? Matrix4.translationValues(0, -2, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: _hovered
              ? AppTheme.sagePanel.withValues(alpha: 0.98)
              : AppTheme.sagePanel.withValues(alpha: 0.9),
          borderRadius: radius,
          border: Border.all(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.22)
                  : AppTheme.sageBlue.withValues(alpha: 0.1),
              blurRadius: _hovered ? 28 : 18,
              offset: Offset(0, _hovered ? 12 : 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
