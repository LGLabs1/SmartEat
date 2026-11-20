import 'package:flutter/material.dart';

class AnimatedDashboardStack extends StatelessWidget {
  const AnimatedDashboardStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: ExcludeSemantics(
              excluding: i != index,
              child: IgnorePointer(
                ignoring: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSlide(
                    offset: i == index ? Offset.zero : const Offset(0, 0.015),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: children[i],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
