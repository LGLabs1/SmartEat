import 'package:flutter/material.dart';

/// Shimmer gradient colors
const List<Color> _shimmerGradientColors = [
  Color(0xFFEBEBF4),
  Color(0xFFF4F4F9),
  Color(0xFFEBEBF4),
];

/// Base shimmer loading widget with animated gradient
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    Key? key,
    required this.child,
    this.isLoading = true,
  }) : super(key: key);

  final Widget child;
  final bool isLoading;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -1, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: _shimmerGradientColors,
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.percent);

  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

/// Card skeleton for loading states
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    Key? key,
    this.height = 120,
    this.margin,
  }) : super(key: key);

  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        height: height,
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// List tile skeleton
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({
    Key? key,
    this.hasLeading = true,
    this.hasSubtitle = true,
    this.trailingWidth = 60,
  }) : super(key: key);

  final bool hasLeading;
  final bool hasSubtitle;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (hasLeading) ...[
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingWidth > 0) ...[
              const SizedBox(width: 12),
              Container(
                height: 24,
                width: trailingWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grid item skeleton for menu/inventory items
class SkeletonGridItem extends StatelessWidget {
  const SkeletonGridItem({
    Key? key,
    this.hasImage = true,
  }) : super(key: key);

  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 14,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  height: 12,
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 32,
                  width: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Stat card skeleton for dashboard
class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 28,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 14,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Table row skeleton for data tables
class SkeletonTableRow extends StatelessWidget {
  const SkeletonTableRow({
    Key? key,
    this.columnCount = 5,
  }) : super(key: key);

  final int columnCount;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: List.generate(columnCount, (index) {
            final isLast = index == columnCount - 1;
            final width = isLast ? 60.0 : null;
            return Expanded(
              flex: isLast ? 0 : 1,
              child: Container(
                height: 16,
                width: width,
                margin: EdgeInsets.only(right: isLast ? 0 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Full page skeleton for initial loading
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header skeleton
            ShimmerLoading(
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                Expanded(child: SkeletonStatCard()),
                const SizedBox(width: 8),
                Expanded(child: SkeletonStatCard()),
                const SizedBox(width: 8),
                Expanded(child: SkeletonStatCard()),
              ],
            ),
            const SizedBox(height: 16),
            // Card skeletons
            SkeletonCard(height: 200),
            const SizedBox(height: 16),
            SkeletonCard(height: 300),
          ],
        ),
      ),
    );
  }
}

/// POS screen skeleton
class SkeletonPOS extends StatelessWidget {
  const SkeletonPOS({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // Category chips skeleton
            ShimmerLoading(
              child: Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, __) => Container(
                    width: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            // Grid skeleton
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 6,
                itemBuilder: (_, __) => SkeletonGridItem(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inventory screen skeleton
class SkeletonInventory extends StatelessWidget {
  const SkeletonInventory({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            ShimmerLoading(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Table header
            Container(
              height: 44,
              color: Colors.grey.shade200,
              child: SkeletonTableRow(columnCount: 5),
            ),
            // Table rows
            ...List.generate(8, (_) => SkeletonTableRow(columnCount: 5)),
          ],
        ),
      ),
    );
  }
}
