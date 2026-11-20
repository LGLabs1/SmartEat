import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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
                borderRadius:
                    BorderRadius.circular(white / 2 - widget.size * 0.045),
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
