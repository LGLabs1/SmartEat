import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';

class FloatingAIAssistantButton extends StatefulWidget {
  const FloatingAIAssistantButton({super.key});

  @override
  State<FloatingAIAssistantButton> createState() => _FloatingAIAssistantButtonState();
}

class _FloatingAIAssistantButtonState extends State<FloatingAIAssistantButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
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
    final provider = context.watch<AIAssistantProvider>();
    final hasBadge = provider.hasNewImportantInsight;

    return GestureDetector(
      onTap: provider.togglePanel,
      onLongPress: () {
        // Show quick status popup built from provider state
        final content = provider.popupContent ?? (provider.activeInsights.isNotEmpty
            ? provider.activeInsights.first.message
            : 'No alerts');
        provider.displayPopup(content);
      },
      onPanUpdate: (details) {
        final base = provider.buttonPosition ?? const Offset(24, 24);
        final nextPosition = provider.clampButtonPosition(base + details.delta);
        provider.updateButtonPosition(nextPosition);
      },
      onPanEnd: (_) {
        provider.snapButtonToEdge();
      },
      child: ScaleTransition(
        scale: _pulse,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      width: 2.5,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.12),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Lottie.asset(
                        'assets/animations/E V E.json',
                        fit: BoxFit.cover,
                        repeat: true,
                        animate: true,
                      ),
                    ),
                  ),
                ),
                if (hasBadge)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact, fixed-size Sage avatar for the side-panel / full-screen headers.
/// Purely decorative — the drag / tap / long-press behaviors live only on the
/// floating [FloatingAIAssistantButton] form.
class SageAvatar extends StatefulWidget {
  const SageAvatar({super.key, this.size = 40, this.showBadge = false});

  final double size;
  final bool showBadge;

  @override
  State<SageAvatar> createState() => _SageAvatarState();
}

class _SageAvatarState extends State<SageAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
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
    final white = widget.size * 6 / 7;
    final lottie = widget.size * 5 / 7;

    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          borderRadius: BorderRadius.circular(widget.size / 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: white,
              height: white,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(white / 2),
                border: Border.all(
                  width: widget.size * 0.045,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.12),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(white / 2 - widget.size * 0.045),
                child: SizedBox(
                  width: lottie,
                  height: lottie,
                  child: Lottie.asset(
                    'assets/animations/E V E.json',
                    fit: BoxFit.cover,
                    repeat: true,
                    animate: true,
                  ),
                ),
              ),
            ),
            if (widget.showBadge)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: widget.size * 0.22,
                  height: widget.size * 0.22,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
