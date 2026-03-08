import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

const Color primaryColor = Color(0xFF1E88E5);
const Color primaryDarkColor = Color(0xFF1565C0);
const Color accentColor = Color(0xFF00B0FF);
const Color errorColor = Color(0xFFE53935);
const Color errorDarkColor = Color(0xFFC62828);

class AnimatedCircle extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final double beginScale;
  final double endScale;
  final Offset offset;
  final Curve curve;

  const AnimatedCircle({
    Key? key,
    required this.size,
    required this.color,
    required this.duration,
    this.beginScale = 0.8,
    this.endScale = 1.2,
    this.offset = Offset.zero,
    this.curve = Curves.easeInOut,
  }) : super(key: key);

  @override
  State<AnimatedCircle> createState() => _AnimatedCircleState();
}

class _AnimatedCircleState extends State<AnimatedCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<Offset> _position;
  late Animation<Offset> _drift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: widget.beginScale,
      end: widget.endScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.9), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.6), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    _position = Tween<Offset>(
      begin: widget.offset,
      end: widget.offset + const Offset(0.0, 0.1),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    _drift = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(24, -18),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: _position.value + _drift.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: widget.size > 220 ? 18 : 12,
                  sigmaY: widget.size > 220 ? 18 : 12,
                ),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withOpacity(0.12),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimatedGradientShimmer extends StatefulWidget {
  final Duration duration;

  const AnimatedGradientShimmer({
    Key? key,
    this.duration = const Duration(seconds: 14),
  }) : super(key: key);

  @override
  State<AnimatedGradientShimmer> createState() =>
      _AnimatedGradientShimmerState();
}

class _AnimatedGradientShimmerState extends State<AnimatedGradientShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;

        final begin = Alignment(-1.0 + (0.6 * v), -1.0 + (0.8 * v));
        final end = Alignment(1.0 - (0.8 * v), 1.0 - (0.6 * v));

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [
                const Color(0xFF0D47A1).withOpacity(0.08),
                const Color(0xFF1E88E5).withOpacity(0.10),
                const Color(0xFF00B0FF).withOpacity(0.06),
                const Color(0xFF5C6BC0).withOpacity(0.07),
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class FloatingIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Duration duration;
  final Offset offset;
  final double beginOffsetY;
  final double endOffsetY;
  final Curve curve;
  final bool rotate;

  const FloatingIcon({
    Key? key,
    required this.icon,
    required this.size,
    required this.color,
    this.duration = const Duration(seconds: 3),
    this.offset = Offset.zero,
    this.beginOffsetY = -0.05,
    this.endOffsetY = 0.05,
    this.curve = Curves.easeInOut,
    this.rotate = false,
  }) : super(key: key);

  @override
  State<FloatingIcon> createState() => _FloatingIconState();
}

class _FloatingIconState extends State<FloatingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _offsetAnimation = Tween<Offset>(
      begin: Offset(0, widget.beginOffsetY),
      end: Offset(0, widget.endOffsetY),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.9), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.6), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear,
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        Widget icon = Icon(
          widget.icon,
          size: widget.size,
          color: widget.color,
        );

        if (widget.rotate) {
          icon = Transform.rotate(
            angle: _rotationAnimation.value,
            child: icon,
          );
        }

        return Transform.translate(
          offset: widget.offset + _offsetAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: icon,
            ),
          ),
        );
      },
    );
  }
}
