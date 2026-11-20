import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 56,
    this.width,
    this.padding = EdgeInsets.zero,
    this.backgroundColor = Colors.transparent,
    this.borderRadius = 0,
  });

  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Image.asset(
        'assets/SmartEat_logo.png',
        height: height,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'SmartEat logo',
      ),
    );
  }
}
