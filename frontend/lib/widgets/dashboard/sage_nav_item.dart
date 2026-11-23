import 'package:flutter/material.dart';
import '../../theme.dart';

class SageNavItem extends StatefulWidget {
  const SageNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
    this.danger = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool danger;
  final int badgeCount;

  @override
  State<SageNavItem> createState() => _SageNavItemState();
}

class _SageNavItemState extends State<SageNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger
        ? const Color(0xFFFF6B6B)
        : widget.selected
            ? AppTheme.sageAccent
            : Colors.white.withValues(alpha: 0.62);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        transform: _hovered && widget.onTap != null
            ? Matrix4.translationValues(3, 0, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: widget.selected
              ? AppTheme.sageBlue.withValues(alpha: 0.2)
              : _hovered
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.selected
                ? AppTheme.sageAccent.withValues(alpha: 0.38)
                : Colors.transparent,
          ),
        ),
        child: ListTile(
          selected: widget.selected,
          leading: widget.badgeCount > 0
              ? Badge(
                  label: Text('${widget.badgeCount > 99 ? '99+' : widget.badgeCount}'),
                  backgroundColor: AppTheme.error,
                  child: Icon(
                    widget.icon,
                    color: widget.selected ? AppTheme.sageCyan : accent,
                  ),
                )
              : Icon(
                  widget.icon,
                  color: widget.selected ? AppTheme.sageCyan : accent,
                ),
          title: Text(
            widget.label,
            style: TextStyle(
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected ? Colors.white : accent,
            ),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
