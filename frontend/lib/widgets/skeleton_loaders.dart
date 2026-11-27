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

Widget _skeletonKpiGrid({
  Key? key,
  required int count,
  required int crossAxisCount,
  double childAspectRatio = 1.7,
  double spacing = 10,
}) {
  return GridView.builder(
    key: key,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount < 1 ? 1 : crossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
    ),
    itemCount: count,
    itemBuilder: (_, __) => _skeletonKpiTile(),
  );
}

Widget _skeletonPanel({
  Key? key,
  required Widget child,
  double? height,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return SkeletonBlock(
    key: key,
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

Widget _skeletonSectionTitle({double width = 140}) {
  return Row(
    children: [
      SkeletonBlock(width: 4, height: 16, borderRadius: 2),
      const SizedBox(width: 8),
      SkeletonLine(width: width, height: 14),
      const Spacer(),
      SkeletonLine(width: 48, height: 10),
    ],
  );
}

Widget _skeletonSearchBar({double height = 48}) {
  return SkeletonBlock(
    width: double.infinity,
    height: height,
    borderRadius: 12,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const SkeletonCircle(diameter: 18),
        const SizedBox(width: 10),
        const Expanded(child: SkeletonLine(width: double.infinity, height: 12)),
        const SizedBox(width: 8),
        SkeletonLine(width: 34, height: 24),
      ],
    ),
  );
}

Widget _skeletonChipStrip({
  Key? key,
  int count = 4,
  double chipWidth = 116,
  double height = 44,
}) {
  return SizedBox(
    key: key,
    height: height,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: count,
      itemBuilder: (_, __) => SkeletonBlock(
        width: chipWidth,
        height: height - 6,
        margin: const EdgeInsets.only(right: 8),
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const SkeletonCircle(diameter: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: double.infinity, height: 11),
                  const SizedBox(height: 4),
                  SkeletonLine(width: 40, height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _skeletonMetricTiles(int count, {double width = 180}) {
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    children: List.generate(
      count,
      (_) => SkeletonBlock(
        width: width,
        height: 66,
        borderRadius: 12,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkeletonLine(width: 110, height: 10),
            const SizedBox(height: 8),
            SkeletonLine(width: 70, height: 15),
          ],
        ),
      ),
    ),
  );
}

Widget _skeletonListRow({
  double avatar = 40,
  bool trailing = true,
  double trailingWidth = 64,
  bool dense = false,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: dense ? 5 : 8),
    child: Row(
      children: [
        SkeletonCircle(diameter: avatar),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(width: double.infinity, height: dense ? 11 : 14),
              const SizedBox(height: 6),
              SkeletonLine(width: dense ? 120 : 100, height: dense ? 9 : 11),
            ],
          ),
        ),
        if (trailing) ...[
          const SizedBox(width: 10),
          Flexible(
            child: SkeletonLine(width: trailingWidth, height: dense ? 12 : 20),
          ),
        ],
      ],
    ),
  );
}

Widget _skeletonInfoCard({
  Key? key,
  int rows = 3,
  double height = 150,
}) {
  return _skeletonPanel(
    key: key,
    height: height,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonPanelHeader(lineWidth: 110),
        const SizedBox(height: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              rows,
              (index) => Padding(
                padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SkeletonLine(
                        width: double.infinity,
                        height: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: SkeletonLine(
                        width: double.infinity,
                        height: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _skeletonToggleTile() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const SkeletonCircle(diameter: 24),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(width: double.infinity, height: 12),
              SizedBox(height: 6),
              SkeletonLine(width: 100, height: 9),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SkeletonBlock(width: 40, height: 22, borderRadius: 11),
      ],
    ),
  );
}

Widget _skeletonBriefingPanel() {
  return _skeletonPanel(
    key: const Key('skeleton-dashboard-briefing'),
    height: 200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonPanelHeader(lineWidth: 110),
        const SizedBox(height: 12),
        const SkeletonLine(width: 140, height: 10),
        const SizedBox(height: 10),
        const SkeletonLine(width: double.infinity, height: 12),
        const SizedBox(height: 6),
        const SkeletonLine(width: double.infinity, height: 12),
        const SizedBox(height: 6),
        const SkeletonLine(width: 180, height: 12),
        const SizedBox(height: 10),
        SkeletonBlock(
          width: double.infinity,
          height: 44,
          borderRadius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SkeletonLine(width: 120, height: 10),
              const Spacer(),
              SkeletonLine(width: 70, height: 9),
            ],
          ),
        ),
      ],
    ),
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
              _skeletonKpiGrid(
                key: const Key('skeleton-dashboard-kpis'),
                count: 9,
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
              ),
              const SizedBox(height: 16),
              _skeletonBriefingPanel(),
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
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 4 : (width >= 300 ? 3 : 2);
        final wide = width >= 900;

        final pnl = _skeletonPanel(
          key: const Key('skeleton-finance-pnl'),
          height: 190,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skeletonPanelHeader(lineWidth: 150),
              const SizedBox(height: 14),
              Expanded(child: _skeletonMetricTiles(9)),
            ],
          ),
        );
        final margin = _skeletonPanel(
          height: 180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skeletonPanelHeader(lineWidth: 170),
              const SizedBox(height: 12),
              const SkeletonLine(width: double.infinity, height: 10),
              const SizedBox(height: 12),
              Expanded(child: _skeletonMetricTiles(4)),
            ],
          ),
        );
        final cashflow = _skeletonPanel(
          height: 260,
          child: _skeletonChart(height: 150),
        );
        final category = _skeletonPanel(
          height: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skeletonPanelHeader(lineWidth: 130),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: SkeletonCircle(diameter: 110),
                ),
              ),
            ],
          ),
        );
        final bills = _skeletonPanel(height: 260, child: _skeletonRows(5));
        final expenses = _skeletonPanel(height: 280, child: _skeletonRows(6));

        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _skeletonKpiGrid(
                key: const Key('skeleton-finance-kpis'),
                count: 8,
                crossAxisCount: columns,
                childAspectRatio: columns == 4 ? 2.1 : 1.7,
              ),
              const SizedBox(height: 16),
              pnl,
              const SizedBox(height: 16),
              margin,
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(cashflow, category)
                  : _skeletonStacked(cashflow, category),
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(bills, expenses)
                  : _skeletonStacked(bills, expenses),
              const SizedBox(height: 16),
              _skeletonPanel(height: 220, child: _skeletonRows(4)),
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
        key: const Key('skeleton-pos-grid'),
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

Widget _skeletonMenuGrid(Key key, int columns) {
  final cardExtent = columns >= 5
      ? 160.0
      : columns == 4
          ? 170.0
          : 180.0;
  return GridView.builder(
    key: key,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      mainAxisExtent: cardExtent,
    ),
    itemCount: columns >= 4 ? 8 : 6,
    itemBuilder: (_, __) => SkeletonBlock(
      borderRadius: 16,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SkeletonBlock(
              width: double.infinity,
              borderRadius: 12,
            ),
          ),
          const SizedBox(height: 8),
          const SkeletonLine(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          const SkeletonLine(width: 90, height: 10),
          const SizedBox(height: 8),
          Row(
            children: [
              SkeletonLine(width: 52, height: 12),
              const Spacer(),
              SkeletonLine(width: 60, height: 22),
            ],
          ),
        ],
      ),
    ),
  );
}

class SkeletonMenu extends StatelessWidget {
  const SkeletonMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1200
            ? 5
            : width >= 900
                ? 4
                : width >= 600
                    ? 3
                    : 2;
        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              _skeletonChipStrip(
                key: const Key('skeleton-menu-categories'),
                count: 6,
                chipWidth: 104,
                height: 44,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _skeletonSectionTitle(width: 100),
              ),
              const SizedBox(height: 8),
              _skeletonMenuGrid(const Key('skeleton-menu-grid'), columns),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _skeletonSectionTitle(width: 130),
              ),
              const SizedBox(height: 8),
              _skeletonMenuGrid(
                  const Key('skeleton-menu-grid-secondary'), columns),
            ],
          ),
        );
      },
    );
  }
}

class SkeletonOrders extends StatelessWidget {
  const SkeletonOrders({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              SkeletonBlock(
                width: double.infinity,
                height: 42,
                borderRadius: 12,
              ),
              const SizedBox(height: 16),
              _skeletonKpiGrid(
                key: const Key('skeleton-orders-kpis'),
                count: 4,
                crossAxisCount: columns,
                childAspectRatio: 1.7,
              ),
              const SizedBox(height: 16),
              _skeletonSearchBar(),
              const SizedBox(height: 12),
              _skeletonChipStrip(
                  key: const Key('skeleton-orders-filters'), count: 5),
              const SizedBox(height: 16),
              _skeletonPanel(
                key: const Key('skeleton-orders-list'),
                height: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonPanelHeader(lineWidth: 120),
                    const SizedBox(height: 12),
                    ...List.generate(
                      5,
                      (_) => _skeletonListRow(avatar: 36, trailingWidth: 72),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _skeletonPanel(
                key: const Key('skeleton-orders-incomplete'),
                height: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonPanelHeader(lineWidth: 140),
                    const SizedBox(height: 12),
                    _skeletonListRow(avatar: 32, trailingWidth: 60),
                    _skeletonListRow(avatar: 32, trailingWidth: 60),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SkeletonAnalytics extends StatelessWidget {
  const SkeletonAnalytics({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 800;
        final summaryColumns = width >= 980 ? 4 : 2;
        final kpis = SizedBox(
          height: wide ? 72 : 128,
          child: wide
              ? ListView.builder(
                  key: const Key('skeleton-analytics-kpis'),
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  itemBuilder: (_, __) => SkeletonBlock(
                    width: 132,
                    height: 68,
                    margin: const EdgeInsets.only(right: 8),
                    borderRadius: 12,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLine(width: 60, height: 10),
                        const SizedBox(height: 8),
                        SkeletonLine(width: 90, height: 16),
                        const SizedBox(height: 6),
                        SkeletonLine(width: 48, height: 8),
                      ],
                    ),
                  ),
                )
              : _skeletonKpiGrid(
                  key: const Key('skeleton-analytics-kpis'),
                  count: 6,
                  crossAxisCount: 3,
                  childAspectRatio: 1.4,
                  spacing: 6,
                ),
        );
        final period = SkeletonBlock(
          width: wide ? 150 : double.infinity,
          height: 40,
          borderRadius: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonLine(width: 44, height: 11),
              const SizedBox(width: 8),
              SkeletonLine(width: 72, height: 20),
            ],
          ),
        );

        return ShimmerLoading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        period,
                        const SizedBox(width: 10),
                        Expanded(child: kpis),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        period,
                        const SizedBox(height: 8),
                        kpis,
                      ],
                    ),
              const SizedBox(height: 16),
              _skeletonKpiGrid(
                key: const Key('skeleton-analytics-summary'),
                count: 4,
                crossAxisCount: summaryColumns,
                childAspectRatio: 1.5,
              ),
              const SizedBox(height: 16),
              _skeletonPanel(
                key: const Key('skeleton-analytics-chart'),
                height: 280,
                child: _skeletonChart(height: 150),
              ),
              const SizedBox(height: 16),
              wide
                  ? _skeletonSideBySide(
                      _skeletonPanel(
                        height: 260,
                        child: _skeletonRows(5, dense: true),
                      ),
                      _skeletonPanel(
                        height: 260,
                        child: _skeletonMetricTiles(4),
                      ),
                    )
                  : _skeletonStacked(
                      _skeletonPanel(
                        height: 260,
                        child: _skeletonRows(5, dense: true),
                      ),
                      _skeletonPanel(
                        height: 240,
                        child: _skeletonMetricTiles(4),
                      ),
                    ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class SkeletonStaff extends StatelessWidget {
  const SkeletonStaff({
    super.key,
    this.rows = 5,
    this.includeHeader = false,
  });

  final int rows;
  final bool includeHeader;

  @override
  Widget build(BuildContext context) {
    final count = rows < 0 ? 0 : rows;
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-staff-list'),
        padding: const EdgeInsets.all(16),
        children: [
          if (includeHeader) ...[
            SkeletonBlock(
              width: double.infinity,
              height: 80,
              borderRadius: 16,
            ),
            const SizedBox(height: 16),
          ],
          ...List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const SkeletonCircle(diameter: 48),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLine(width: double.infinity, height: 16),
                        SizedBox(height: 8),
                        SkeletonLine(width: 120, height: 12),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SkeletonLine(width: 60, height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _skeletonPanel(
                    key: const Key('skeleton-profile-header'),
                    height: 130,
                    child: Row(
                      children: [
                        const SkeletonCircle(diameter: 64),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(
                                width: double.infinity,
                                height: 18,
                              ),
                              const SizedBox(height: 10),
                              SkeletonLine(width: 140, height: 12),
                              const SizedBox(height: 8),
                              SkeletonLine(width: 100, height: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _skeletonPanel(
                    height: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeletonPanelHeader(lineWidth: 120),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SkeletonBlock(
                                height: 58,
                                borderRadius: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SkeletonBlock(
                                height: 58,
                                borderRadius: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _skeletonPanel(
                    key: const Key('skeleton-profile-attendance'),
                    height: 250,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeletonPanelHeader(lineWidth: 140),
                        const SizedBox(height: 14),
                        Expanded(
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1,
                            ),
                            itemCount: 28,
                            itemBuilder: (_, __) => SkeletonBlock(
                              borderRadius: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _skeletonInfoCard(
                      key: const Key('skeleton-profile-personal'),
                      rows: 4,
                      height: 210),
                  const SizedBox(height: 16),
                  _skeletonInfoCard(rows: 3, height: 180),
                  const SizedBox(height: 16),
                  _skeletonPanel(
                    height: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeletonPanelHeader(lineWidth: 100),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SkeletonBlock(
                                height: 40,
                                borderRadius: 10,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SkeletonBlock(
                                height: 40,
                                borderRadius: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class SkeletonSettings extends StatelessWidget {
  const SkeletonSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-settings-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _skeletonPanel(
            height: 100,
            child: Row(
              children: [
                const SkeletonCircle(diameter: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: double.infinity, height: 15),
                      const SizedBox(height: 10),
                      SkeletonLine(width: 140, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(8, (section) {
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonLine(width: 120 + (section % 3) * 30.0, height: 14),
                  const SizedBox(height: 12),
                  _skeletonPanel(
                    height: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _skeletonToggleTile(),
                        _skeletonToggleTile(),
                        _skeletonToggleTile(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class SkeletonNotifications extends StatelessWidget {
  const SkeletonNotifications({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: ListView.builder(
              key: const Key('skeleton-notifications-filters'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 4,
              itemBuilder: (_, __) => Container(
                width: 88,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                child: SkeletonLine(width: double.infinity, height: 32),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('skeleton-notifications-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: 6,
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 84,
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _skeletonListRow(
                    avatar: 44,
                    trailingWidth: 40,
                    dense: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonRecipeList extends StatelessWidget {
  const SkeletonRecipeList({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-recipes-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _skeletonPanel(
            key: const Key('skeleton-recipes-hero'),
            height: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SkeletonCircle(diameter: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(width: double.infinity, height: 16),
                          const SizedBox(height: 8),
                          SkeletonLine(width: 130, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(
                    3,
                    (_) => SkeletonLine(width: 104, height: 32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _skeletonSearchBar(),
          const SizedBox(height: 14),
          ...List.generate(
            4,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SkeletonBlock(
                width: double.infinity,
                height: 152,
                borderRadius: 18,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SkeletonCircle(diameter: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(
                                width: double.infinity,
                                height: 15,
                              ),
                              const SizedBox(height: 8),
                              SkeletonLine(width: 120, height: 11),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SkeletonLine(width: double.infinity, height: 11),
                    const SizedBox(height: 6),
                    const SkeletonLine(width: 180, height: 11),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SkeletonLine(width: 80, height: 24),
                        const SizedBox(width: 8),
                        SkeletonLine(width: 100, height: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _skeletonReportBody() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SkeletonBlock(
        width: double.infinity,
        height: 52,
        borderRadius: 12,
        child: Row(
          children: [
            const SkeletonCircle(diameter: 20),
            const SizedBox(width: 10),
            const Expanded(
                child: SkeletonLine(width: double.infinity, height: 14)),
            SkeletonLine(width: 100, height: 24),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _skeletonPanel(height: 120, child: _skeletonRows(2)),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 4
              : constraints.maxWidth >= 300
                  ? 3
                  : 2;
          return _skeletonKpiGrid(
            key: const Key('skeleton-reports-kpis'),
            count: 4,
            crossAxisCount: columns,
            childAspectRatio: 1.7,
          );
        },
      ),
      const SizedBox(height: 16),
      _skeletonPanel(
        key: const Key('skeleton-reports-pnl'),
        height: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonPanelHeader(lineWidth: 150),
            const SizedBox(height: 12),
            ...List.generate(
              7,
              (_) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: SkeletonLine(width: double.infinity, height: 11),
                    ),
                    const SizedBox(width: 12),
                    SkeletonLine(width: 72, height: 11),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _skeletonPanel(
        height: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonPanelHeader(lineWidth: 170),
            const SizedBox(height: 12),
            Expanded(child: _skeletonMetricTiles(8)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _skeletonPanel(height: 300, child: _skeletonRows(6, dense: true)),
      const SizedBox(height: 16),
      _skeletonPanel(
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonPanelHeader(lineWidth: 130),
            const SizedBox(height: 16),
            Expanded(
              child: Center(child: SkeletonCircle(diameter: 110)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: SkeletonLine(width: double.infinity, height: 40)),
          const SizedBox(width: 12),
          Expanded(child: SkeletonLine(width: double.infinity, height: 40)),
        ],
      ),
      const SizedBox(height: 24),
    ],
  );
}

class SkeletonReports extends StatelessWidget {
  const SkeletonReports({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-reports-list'),
        padding: const EdgeInsets.all(16),
        children: [_skeletonReportBody()],
      ),
    );
  }
}

class SkeletonPayroll extends StatelessWidget {
  const SkeletonPayroll({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-payroll-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _skeletonPanel(
            key: const Key('skeleton-payroll-summary'),
            height: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonPanelHeader(lineWidth: 130),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SkeletonBlock(
                        height: 64,
                        borderRadius: 10,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(width: 80, height: 10),
                            const SizedBox(height: 8),
                            SkeletonLine(width: 100, height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SkeletonBlock(
                        height: 64,
                        borderRadius: 10,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(width: 60, height: 10),
                            const SizedBox(height: 8),
                            SkeletonLine(width: 80, height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _skeletonPanel(
            key: const Key('skeleton-payroll-history'),
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonPanelHeader(lineWidth: 120),
                const SizedBox(height: 12),
                ...List.generate(
                  5,
                  (_) => _skeletonListRow(
                    avatar: 36,
                    trailingWidth: 80,
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonItemDetail extends StatelessWidget {
  const SkeletonItemDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 760 ? 4 : 2;
        return ShimmerLoading(
          child: ListView(
            key: const Key('skeleton-item-detail-list'),
            padding: const EdgeInsets.all(12),
            children: [
              _skeletonPanel(
                key: const Key('skeleton-item-detail-header'),
                height: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SkeletonCircle(diameter: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(width: double.infinity, height: 16),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  SkeletonLine(width: 64, height: 20),
                                  SkeletonLine(width: 72, height: 20),
                                  SkeletonLine(width: 58, height: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SkeletonBlock(
                      width: double.infinity,
                      height: 8,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SkeletonLine(width: 100, height: 10),
              const SizedBox(height: 8),
              _skeletonKpiGrid(
                key: const Key('skeleton-item-detail-stock'),
                count: 4,
                crossAxisCount: columns,
                childAspectRatio: 1.5,
              ),
              const SizedBox(height: 12),
              const SkeletonLine(width: 110, height: 10),
              const SizedBox(height: 8),
              _skeletonKpiGrid(
                key: const Key('skeleton-item-detail-cost'),
                count: 3,
                crossAxisCount: columns,
                childAspectRatio: 1.5,
              ),
              const SizedBox(height: 12),
              const SkeletonLine(width: 120, height: 10),
              const SizedBox(height: 8),
              _skeletonKpiGrid(
                key: const Key('skeleton-item-detail-supplier'),
                count: 4,
                crossAxisCount: columns,
                childAspectRatio: 1.5,
              ),
              const SizedBox(height: 12),
              _skeletonPanel(height: 110, child: _skeletonRows(2)),
              const SizedBox(height: 12),
              _skeletonPanel(
                key: const Key('skeleton-item-detail-movements'),
                height: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonPanelHeader(lineWidth: 150),
                    const SizedBox(height: 12),
                    ...List.generate(
                      5,
                      (_) => _skeletonListRow(
                        avatar: 24,
                        trailingWidth: 64,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _skeletonPanel(
                key: const Key('skeleton-item-detail-usage'),
                height: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonPanelHeader(lineWidth: 170),
                    const SizedBox(height: 10),
                    const SkeletonLine(width: double.infinity, height: 10),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SkeletonLine(width: 100, height: 44),
                        const SizedBox(width: 8),
                        SkeletonLine(width: 100, height: 44),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(
                      3,
                      (_) => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: SkeletonLine(
                                width: double.infinity,
                                height: 11,
                              ),
                            ),
                            SizedBox(width: 12),
                            SkeletonLine(width: 60, height: 11),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SkeletonDamagedItems extends StatelessWidget {
  const SkeletonDamagedItems({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        key: const Key('skeleton-damaged-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _skeletonPanel(
            key: const Key('skeleton-damaged-summary'),
            height: 110,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SkeletonLine(width: 130, height: 11),
                      const SizedBox(height: 10),
                      SkeletonLine(width: 100, height: 22),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SkeletonLine(width: 96, height: 40),
              ],
            ),
          ),
          ...List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SkeletonBlock(
                width: double.infinity,
                height: 128,
                borderRadius: 16,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(width: double.infinity, height: 16),
                              const SizedBox(height: 8),
                              SkeletonLine(width: 110, height: 11),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SkeletonLine(width: 72, height: 14),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SkeletonLine(width: 150, height: 11),
                    const SizedBox(height: 8),
                    const SkeletonLine(width: 120, height: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonInventory extends StatelessWidget {
  const SkeletonInventory({
    super.key,
    this.section = 0,
  });

  final int section;

  @override
  Widget build(BuildContext context) {
    final active = section < 0 ? 0 : (section > 5 ? 5 : section);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 4 : (width >= 800 ? 3 : 2);

        Widget body;
        switch (active) {
          case 0:
            body = ListView(
              key: const Key('skeleton-inventory-overview'),
              padding: const EdgeInsets.all(16),
              children: [
                _skeletonPanel(
                  key: const Key('skeleton-inventory-health'),
                  height: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonPanelHeader(lineWidth: 140),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          SkeletonLine(width: 56, height: 32),
                          const SizedBox(width: 12),
                          SkeletonLine(width: 90, height: 18),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _skeletonChipStrip(
                  key: const Key('skeleton-inventory-stat-chips'),
                  count: 6,
                  chipWidth: 132,
                  height: 60,
                ),
                const SizedBox(height: 24),
                const SkeletonLine(width: 140, height: 14),
                const SizedBox(height: 8),
                _skeletonPanel(
                  key: const Key('skeleton-inventory-activity'),
                  height: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonPanelHeader(lineWidth: 110),
                      const SizedBox(height: 12),
                      ...List.generate(
                        5,
                        (_) => _skeletonListRow(
                          avatar: 28,
                          trailingWidth: 48,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SkeletonLine(width: 160, height: 14),
                const SizedBox(height: 8),
                _skeletonPanel(
                  key: const Key('skeleton-inventory-restock'),
                  height: 230,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonLine(width: double.infinity, height: 10),
                      const SizedBox(height: 6),
                      const SkeletonLine(width: 220, height: 10),
                      const SizedBox(height: 14),
                      ...List.generate(
                        4,
                        (_) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: SkeletonLine(
                                  width: double.infinity,
                                  height: 12,
                                ),
                              ),
                              SizedBox(width: 12),
                              SkeletonLine(width: 72, height: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            break;
          case 1:
            body = ListView(
              key: const Key('skeleton-inventory-items'),
              padding: const EdgeInsets.all(16),
              children: [
                _skeletonKpiGrid(
                  key: const Key('skeleton-inventory-status-cards'),
                  count: 4,
                  crossAxisCount: columns,
                  childAspectRatio: 1.9,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _skeletonKpiGrid(
                  key: const Key('skeleton-inventory-category-cards'),
                  count: 8,
                  crossAxisCount: columns,
                  childAspectRatio: 2.2,
                ),
              ],
            );
            break;
          case 2:
            body = ListView(
              key: const Key('skeleton-inventory-movements'),
              padding: const EdgeInsets.all(16),
              children: [
                _skeletonSearchBar(),
                const SizedBox(height: 16),
                _skeletonChipStrip(
                    key: const Key('skeleton-inventory-movement-filters'),
                    count: 5),
                const SizedBox(height: 16),
                _skeletonPanel(
                  height: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonPanelHeader(lineWidth: 130),
                      const SizedBox(height: 12),
                      ...List.generate(
                        7,
                        (_) => _skeletonListRow(
                          avatar: 30,
                          trailingWidth: 56,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            break;
          case 3:
            body = ListView(
              key: const Key('skeleton-inventory-purchases'),
              padding: const EdgeInsets.all(16),
              children: [
                _skeletonSearchBar(),
                const SizedBox(height: 16),
                _skeletonPanel(
                  height: 120,
                  child: _skeletonRows(2),
                ),
                const SizedBox(height: 16),
                _skeletonPanel(
                  key: const Key('skeleton-inventory-purchase-rows'),
                  height: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonPanelHeader(lineWidth: 140),
                      const SizedBox(height: 12),
                      ...List.generate(
                        6,
                        (_) => _skeletonListRow(
                          avatar: 32,
                          trailingWidth: 80,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            break;
          case 4:
            body = ListView(
              key: const Key('skeleton-inventory-adjustments'),
              padding: const EdgeInsets.all(16),
              children: [
                _skeletonSearchBar(),
                const SizedBox(height: 16),
                _skeletonPanel(
                  key: const Key('skeleton-inventory-adjustment-rows'),
                  height: 400,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonPanelHeader(lineWidth: 150),
                      const SizedBox(height: 12),
                      ...List.generate(
                        7,
                        (_) => _skeletonListRow(
                          avatar: 28,
                          trailingWidth: 64,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            break;
          default:
            body = ListView(
              key: const Key('skeleton-inventory-reports'),
              padding: const EdgeInsets.all(16),
              children: [_skeletonReportBody()],
            );
            break;
        }

        return ShimmerLoading(child: body);
      },
    );
  }
}
