import 'package:flutter/material.dart';

Color _skeletonBaseColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  return Color.lerp(
        scheme.surface,
        scheme.onSurface,
        isDark ? 0.10 : 0.07,
      ) ??
      (isDark ? const Color(0xFF2B3038) : const Color(0xFFE8EAF0));
}

Color _skeletonHighlightColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  return Color.lerp(
        _skeletonBaseColor(context),
        scheme.onSurface,
        isDark ? 0.17 : 0.13,
      ) ??
      (isDark ? const Color(0xFF3B414A) : const Color(0xFFF6F7FB));
}

/// Base shimmer loading widget with a narrow, animated highlight.
///
/// A single instance is meant to wrap a whole loading group (a list, grid or
/// panel) so a screen uses one controller rather than one per tiny block.
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
  });

  final Widget child;
  final bool isLoading;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;
  bool _animationsDisabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ShimmerLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading) _syncController();
  }

  void _syncController() {
    final shouldAnimate = widget.isLoading && !_animationsDisabled;
    if (shouldAnimate && _controller == null) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      );
      _animation = Tween<double>(begin: -1, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOutSine),
      );
      controller.repeat();
      _controller = controller;
    } else if (!shouldAnimate && _controller != null) {
      _controller!.dispose();
      _controller = null;
      _animation = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    final child = Semantics(label: 'Loading', child: widget.child);
    final animation = _animation;
    if (_controller == null || animation == null) return child;

    final base = _skeletonBaseColor(context);
    final highlight = _skeletonHighlightColor(context);

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, builtChild) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.44, 0.5, 0.56],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: builtChild ?? child,
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

/// Themed rectangular building block for skeleton layouts.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 14,
    this.margin,
    this.padding,
    this.color,
    this.child,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? _skeletonBaseColor(context),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}

/// Themed text-line building block for skeleton layouts.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 12,
    this.color,
    this.margin,
  });

  final double? width;
  final double height;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBlock(
      width: width,
      height: height,
      margin: margin,
      borderRadius: height / 2,
      color: color,
    );
  }
}

/// Themed circular building block for avatars and icon placeholders.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    this.diameter = 40,
    this.color,
  });

  final double diameter;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SkeletonBlock(
      width: diameter,
      height: diameter,
      borderRadius: diameter / 2,
      color: color,
    );
  }
}

/// Card skeleton for loading states.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 120,
    this.margin,
  });

  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SkeletonBlock(
        height: height,
        margin:
            margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderRadius: 16,
      ),
    );
  }
}

/// List tile skeleton.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({
    super.key,
    this.hasLeading = true,
    this.hasSubtitle = true,
    this.trailingWidth = 60,
  });

  final bool hasLeading;
  final bool hasSubtitle;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(child: _buildTile(context));
  }

  Widget _buildTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (hasLeading) ...[
            const SkeletonCircle(diameter: 48),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLine(width: double.infinity, height: 16),
                if (hasSubtitle) ...[
                  const SizedBox(height: 8),
                  const SkeletonLine(width: 120, height: 12),
                ],
              ],
            ),
          ),
          if (trailingWidth > 0) ...[
            const SizedBox(width: 12),
            SkeletonLine(width: trailingWidth, height: 24),
          ],
        ],
      ),
    );
  }
}

/// Grid item skeleton for menu/inventory items.
class SkeletonGridItem extends StatelessWidget {
  const SkeletonGridItem({
    super.key,
    this.hasImage = true,
  });

  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SkeletonBlock(
        padding: const EdgeInsets.all(12),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              const Expanded(child: SkeletonBlock(borderRadius: 12)),
              const SizedBox(height: 12),
            ],
            const SkeletonLine(width: double.infinity, height: 16),
            const SizedBox(height: 8),
            const SkeletonLine(width: 80, height: 14),
            const SizedBox(height: 8),
            Row(
              children: [
                const SkeletonLine(width: 50, height: 12),
                const Spacer(),
                SkeletonLine(
                  width: 80,
                  height: 32,
                  color: _skeletonBaseColor(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Stat card skeleton for dashboard.
class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: SkeletonBlock(
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonBlock(width: 40, height: 40, borderRadius: 12),
            SizedBox(height: 10),
            SkeletonLine(width: 80, height: 22),
            SizedBox(height: 6),
            SkeletonLine(width: 60, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Table row skeleton for data tables.
class SkeletonTableRow extends StatelessWidget {
  const SkeletonTableRow({
    super.key,
    this.columnCount = 5,
  });

  final int columnCount;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(child: _buildRow(columnCount));
  }

  static Widget _buildRow(int columnCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: List.generate(columnCount, (index) {
          final isLast = index == columnCount - 1;
          return Expanded(
            flex: isLast ? 0 : 1,
            child: Container(
              height: 16,
              width: isLast ? 60.0 : null,
              margin: EdgeInsets.only(right: isLast ? 0 : 16),
              child: const SkeletonLine(width: double.infinity, height: 16),
            ),
          );
        }),
      ),
    );
  }
}

Widget _skeletonKpiTile() {
  return SkeletonBlock(
    borderRadius: 16,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const SkeletonCircle(diameter: 18),
            const Spacer(),
            SkeletonLine(width: 24, height: 8),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: const SkeletonLine(width: double.infinity, height: 16),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 60),
          child: const SkeletonLine(width: double.infinity, height: 8),
        ),
      ],
    ),
  );
}

Widget _skeletonPanel({
  required Widget child,
  double? height,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return SkeletonBlock(
    height: height,
    padding: padding,
    borderRadius: 20,
    child: child,
  );
}

Widget _skeletonPanelHeader({double lineWidth = 120}) {
  return Row(
    children: [
      const SkeletonCircle(diameter: 28),
      const SizedBox(width: 10),
      SkeletonLine(width: lineWidth, height: 14),
      const Spacer(),
      SkeletonLine(width: 52, height: 11),
    ],
  );
}

Widget _skeletonRows(int count, {bool dense = false}) {
  return Column(
    children: List.generate(count, (index) {
      return Padding(
        padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : 12),
        child: Row(
          children: [
            const SkeletonCircle(diameter: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(
                    width: double.infinity,
                    height: dense ? 11 : 13,
                  ),
                  const SizedBox(height: 6),
                  SkeletonLine(width: 88, height: dense ? 9 : 11),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SkeletonLine(width: dense ? 52 : 64, height: dense ? 12 : 20),
          ],
        ),
      );
    }),
  );
}

Widget _skeletonChart({double height = 150}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _skeletonPanelHeader(lineWidth: 96),
      SizedBox(height: height > 100 ? 18 : 10),
      SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(7, (index) {
            final barHeight = 42.0 + (index % 3) * 32.0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: SkeletonBlock(
                  height: barHeight,
                  borderRadius: 8,
                ),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: 10),
      const SkeletonLine(width: 160, height: 10),
    ],
  );
}

Widget _skeletonSideBySide(Widget left, Widget right) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 16),
      Expanded(child: right),
    ],
  );
}

Widget _skeletonStacked(Widget top, Widget bottom) {
  return Column(
    children: [
      top,
      const SizedBox(height: 16),
      bottom,
    ],
  );
}

/// Responsive home-dashboard skeleton. Body content only: the owning screen
/// supplies the Scaffold, SafeArea and theme.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100 ? 4 : (width >= 300 ? 3 : 2);
        final aspectRatio = crossAxisCount == 4 ? 2.6 : 1.45;
        final wide = width >= 900;
        final kpis = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: aspectRatio,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => _skeletonKpiTile(),
        );

        final financeAndStock = _skeletonPanel(
          height: 210,
          child: _skeletonRows(3),
        );
        final stockAndMenu = _skeletonPanel(
          height: 210,
          child: _skeletonRows(4),
        );
        final menuPerformance = _skeletonPanel(
          height: 230,
          child: _skeletonRows(5, dense: true),
        );
        final salesTrend = _skeletonPanel(
          height: 230,
          child: _skeletonChart(height: 120),
        );

        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              kpis,
              const SizedBox(height: 16),
              _skeletonPanel(height: 104, child: _skeletonRows(1)),
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(financeAndStock, stockAndMenu)
                  : _skeletonStacked(financeAndStock, stockAndMenu),
              const SizedBox(height: 16),
              _skeletonPanel(height: 196, child: _skeletonRows(3)),
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(menuPerformance, salesTrend)
                  : _skeletonStacked(menuPerformance, salesTrend),
            ],
          ),
        );
      },
    );
  }
}

/// Finance-module skeleton. Body content only; the finance shell keeps its
/// AppBar and bottom navigation while this is shown.
class SkeletonFinance extends StatelessWidget {
  const SkeletonFinance({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final metrics = GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => _skeletonKpiTile(),
        );

        final ledger = _skeletonPanel(
          height: 260,
          child: _skeletonRows(5),
        );
        final chart = _skeletonPanel(
          height: 260,
          child: _skeletonChart(height: 150),
        );

        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              metrics,
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(chart, ledger)
                  : _skeletonStacked(chart, ledger),
              const SizedBox(height: 16),
              _skeletonPanel(height: 300, child: _skeletonRows(6)),
            ],
          ),
        );
      },
    );
  }
}

/// POS grid skeleton. Body content only; the POS screen renders the category
/// chips and owns the Scaffold/AppBar.
class SkeletonPOS extends StatelessWidget {
  const SkeletonPOS({
    super.key,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.85,
    this.isCompact = false,
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount < 1 ? 1 : crossAxisCount,
          childAspectRatio: childAspectRatio <= 0 ? 0.85 : childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: isCompact ? 6 : 8,
        itemBuilder: (_, __) => SkeletonBlock(
          padding: const EdgeInsets.all(12),
          borderRadius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SkeletonBlock(borderRadius: 12)),
              const SizedBox(height: 12),
              const SkeletonLine(width: double.infinity, height: 14),
              const SizedBox(height: 8),
              const SkeletonLine(width: 72, height: 12),
              const SizedBox(height: 12),
              Row(
                children: [
                  SkeletonLine(width: 44, height: 11),
                  const Spacer(),
                  SkeletonLine(
                    width: isCompact ? 60 : 76,
                    height: 30,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inventory table skeleton. Body content only.
class SkeletonInventory extends StatelessWidget {
  const SkeletonInventory({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SkeletonBlock(height: 56, borderRadius: 12),
          const SizedBox(height: 16),
          const SkeletonBlock(height: 44, borderRadius: 8),
          ...List.generate(
            8,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SkeletonCircle(diameter: 32),
                  const SizedBox(width: 12),
                  const Expanded(child: SkeletonLine(height: 14)),
                  const SizedBox(width: 12),
                  SkeletonLine(width: 56, height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
