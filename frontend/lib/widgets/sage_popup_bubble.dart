import 'package:flutter/material.dart';

import '../theme.dart';

/// Where a passive Sage bubble should sit relative to its live header anchor.
class SageBubblePlacement {
  const SageBubblePlacement({
    required this.rect,
    required this.tailAtTop,
    required this.tailDx,
  });

  /// Bubble bounds in screen coordinates (already clamped to the safe area).
  final Rect rect;

  /// True when the tail sits on the bubble's top edge, i.e. the bubble is
  /// below the anchor. False when the bubble was flipped above the anchor.
  final bool tailAtTop;

  /// Horizontal tail offset relative to [rect].left.
  final double tailDx;
}

/// Pure, testable placement logic shared by the shell and its widget tests.
///
/// [anchor] is the live Rect of the visible Sage header avatar/button,
/// [screen] is the MediaQuery size and [safeArea] its padding.
SageBubblePlacement computeSageBubblePlacement(
  Rect anchor,
  Size screen,
  EdgeInsets safeArea, {
  double bubbleWidth = 260,
  double bubbleHeight = 56,
  double gap = 10,
}) {
  final safeLeft = safeArea.left.clamp(0.0, screen.width);
  final safeTop = safeArea.top.clamp(0.0, screen.height);
  final safeWidth =
      (screen.width - safeArea.left - safeArea.right).clamp(0.0, screen.width);
  final safeHeight = (screen.height - safeArea.top - safeArea.bottom)
      .clamp(0.0, screen.height);
  final safeRight = safeLeft + safeWidth;
  final safeBottom = safeTop + safeHeight;

  final width = bubbleWidth.clamp(0.0, safeWidth);
  final height = bubbleHeight.clamp(0.0, safeHeight);

  final left =
      (anchor.center.dx - width / 2).clamp(safeLeft, safeRight - width);
  const tailInset = 16.0;
  final tailDx = width <= tailInset * 2
      ? width / 2
      : (anchor.center.dx - left).clamp(tailInset, width - tailInset);

  final belowTop = anchor.bottom + gap;
  final aboveTop = anchor.top - gap - height;
  final fitsBelow = belowTop + height <= safeBottom;
  final fitsAbove = aboveTop >= safeTop;

  double top;
  if (fitsBelow) {
    top = belowTop;
  } else if (fitsAbove) {
    top = aboveTop;
  } else {
    final overflowBelow = belowTop + height - safeBottom;
    final overflowAbove = safeTop - aboveTop;
    top = overflowBelow <= overflowAbove ? belowTop : aboveTop;
  }
  top = top.clamp(safeTop, safeBottom - height);

  final rect = Rect.fromLTWH(left, top, width, height);
  return SageBubblePlacement(
    rect: rect,
    tailAtTop: rect.center.dy >= anchor.center.dy,
    tailDx: tailDx,
  );
}

/// Transient passive Sage message. Positions itself using the live header
/// anchor instead of the legacy draggable-button position.
class SagePopupBubble extends StatelessWidget {
  const SagePopupBubble({
    Key? key,
    required this.anchor,
    required this.message,
    required this.onOpen,
    required this.onDismiss,
  }) : super(key: key);

  final Rect anchor;
  final String message;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final placement =
        computeSageBubblePlacement(anchor, media.size, media.padding);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    final bubbleColor = AppTheme.sageNavy.withValues(alpha: 0.96);
    final bubbleWidth = placement.rect.width;
    final tailLeft = bubbleWidth >= 16
        ? (placement.tailDx - 8).clamp(8.0, bubbleWidth - 16.0)
        : 0.0;
    Widget bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: tailLeft,
          top: placement.tailAtTop ? -6 : null,
          bottom: placement.tailAtTop ? null : -6,
          child: CustomPaint(
            size: const Size(16, 7),
            painter: _SageTailPainter(
              color: bubbleColor,
              tailAtTop: placement.tailAtTop,
            ),
          ),
        ),
        Positioned.fill(
          child: Semantics(
            container: true,
            label: 'Sage says: $message',
            button: true,
            child: Material(
              color: Colors.transparent,
              child: Container(
                key: const Key('sage-popup-bubble'),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.sageCyan.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onOpen,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('sage-popup-close'),
                      onPressed: onDismiss,
                      tooltip: 'Dismiss Sage message',
                      icon: const Icon(Icons.close, size: 16),
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 30, height: 30),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (!animationsDisabled) {
      final tailFraction =
          bubbleWidth > 0 ? placement.tailDx / bubbleWidth : 0.5;
      final alignment = Alignment(
        (tailFraction * 2 - 1).clamp(-1.0, 1.0),
        placement.tailAtTop ? -1.0 : 1.0,
      );
      bubble = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (context, scale, child) => Opacity(
          opacity: ((scale - 0.96) / 0.04).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            alignment: alignment,
            child: child,
          ),
        ),
        child: bubble,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (!placement.rect.contains(event.localPosition)) {
                onDismiss();
              }
            },
          ),
        ),
        Positioned.fromRect(rect: placement.rect, child: bubble),
      ],
    );
  }
}

class _SageTailPainter extends CustomPainter {
  const _SageTailPainter({required this.color, required this.tailAtTop});

  final Color color;
  final bool tailAtTop;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (tailAtTop) {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width / 2, 0);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SageTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.tailAtTop != tailAtTop;
}
