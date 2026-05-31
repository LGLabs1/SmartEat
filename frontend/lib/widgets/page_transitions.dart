import 'package:flutter/material.dart';

/// Custom page transitions for SmartEat
class PageTransitions {
  /// Fade transition - subtle, professional
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }

  /// Slide from right - for forward navigation
  static Widget slideFromRight(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOutCubic;

    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);

    return SlideTransition(
      position: offsetAnimation,
      child: child,
    );
  }

  /// Slide from bottom - for modals, sheets
  static Widget slideFromBottom(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeOutCubic;

    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);

    return SlideTransition(
      position: offsetAnimation,
      child: child,
    );
  }

  /// Scale transition - for dialogs, emphasis
  static Widget scaleTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: child,
    );
  }

  /// Fade through transition - for related content
  static Widget fadeThrough(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
      child: child,
    );
  }
}

/// Route with custom transition
class CustomPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final RouteTransitionsBuilder transitionsBuilder;
  final Duration transitionDuration;

  CustomPageRoute({
    required this.child,
    required this.transitionsBuilder,
    this.transitionDuration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: transitionsBuilder,
          transitionDuration: transitionDuration,
          reverseTransitionDuration: const Duration(milliseconds: 200),
        );
}

/// Animated route generator
class AnimatedRoutes {
  /// Navigate with fade
  static Route<T> fade<T>(Widget page) {
    return CustomPageRoute<T>(
      child: page,
      transitionsBuilder: PageTransitions.fadeTransition,
      transitionDuration: const Duration(milliseconds: 250),
    );
  }

  /// Navigate with slide from right
  static Route<T> slideRight<T>(Widget page) {
    return CustomPageRoute<T>(
      child: page,
      transitionsBuilder: PageTransitions.slideFromRight,
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  /// Navigate with slide from bottom
  static Route<T> slideBottom<T>(Widget page) {
    return CustomPageRoute<T>(
      child: page,
      transitionsBuilder: PageTransitions.slideFromBottom,
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  /// Navigate with scale
  static Route<T> scale<T>(Widget page) {
    return CustomPageRoute<T>(
      child: page,
      transitionsBuilder: PageTransitions.scaleTransition,
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

/// Extension for easy navigation with animations
extension AnimatedNavigation on BuildContext {
  /// Push with fade
  Future<T?> pushFade<T>(Widget page) {
    return Navigator.of(this).push(AnimatedRoutes.fade(page));
  }

  /// Push with slide from right
  Future<T?> pushSlide<T>(Widget page) {
    return Navigator.of(this).push(AnimatedRoutes.slideRight(page));
  }

  /// Push with slide from bottom
  Future<T?> pushBottom<T>(Widget page) {
    return Navigator.of(this).push(AnimatedRoutes.slideBottom(page));
  }

  /// Push replacement with fade
  Future<T?> pushReplacementFade<T>(Widget page) {
    return Navigator.of(this).pushReplacement(AnimatedRoutes.fade(page));
  }

  /// Present like a modal
  Future<T?> present<T>(Widget page) {
    return Navigator.of(this).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return PageTransitions.slideFromBottom(
            context,
            animation,
            secondaryAnimation,
            child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        opaque: false,
      ),
    );
  }
}

/// Animated tab switcher for dashboard
class AnimatedTabSwitcher extends StatelessWidget {
  final Widget child;
  final int selectedIndex;

  const AnimatedTabSwitcher({
    Key? key,
    required this.child,
    required this.selectedIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(selectedIndex),
        child: child,
      ),
    );
  }
}

/// Animated list item for smooth list updates
class AnimatedListItem extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const AnimatedListItem({
    Key? key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 50),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * delay.inMilliseconds)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 20),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Pulse animation for attention
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const PulseAnimation({
    Key? key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  }) : super(key: key);

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
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
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
