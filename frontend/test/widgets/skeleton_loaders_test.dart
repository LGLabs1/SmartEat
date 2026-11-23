import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/theme.dart';
import 'package:smarteat/widgets/skeleton_loaders.dart';

void main() {
  const sizes = <Size>[
    Size(390, 844),
    Size(900, 1000),
    Size(1280, 800),
  ];

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildHost(
    Widget child, {
    ThemeData? theme,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      theme: theme ?? AppTheme.dashboardTheme,
      home: Builder(
        builder: (context) {
          final query = MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          );
          return Scaffold(
            body: MediaQuery(data: query, child: child),
          );
        },
      ),
    );
  }

  Widget posForWidth(double width) {
    final crossAxisCount = width < 520
        ? 2
        : width >= 1100
            ? 4
            : width >= 820
                ? 3
                : 2;
    final ratio = width < 520
        ? 0.64
        : crossAxisCount == 2
            ? 0.68
            : crossAxisCount == 3
                ? 0.74
                : 0.82;
    return SkeletonPOS(
      crossAxisCount: crossAxisCount,
      childAspectRatio: ratio,
      isCompact: width < 780,
    );
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('SkeletonDashboard renders at $label', (tester) async {
      await setSurface(tester, size);
      await tester.pumpWidget(buildHost(const SkeletonDashboard()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('SkeletonFinance renders at $label', (tester) async {
      await setSurface(tester, size);
      await tester.pumpWidget(buildHost(const SkeletonFinance()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('SkeletonPOS renders at $label', (tester) async {
      await setSurface(tester, size);
      await tester.pumpWidget(buildHost(posForWidth(size.width)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });
  }

  testWidgets('skeletons adapt to the light theme', (tester) async {
    await setSurface(tester, const Size(900, 1000));
    await tester.pumpWidget(
      buildHost(const SkeletonDashboard(), theme: AppTheme.lightTheme),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('ShimmerLoading exposes loading semantics only when loading',
      (tester) async {
    await tester.pumpWidget(
      buildHost(const ShimmerLoading(child: SizedBox(width: 20, height: 20))),
    );
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    await tester.pumpWidget(
      buildHost(
        const ShimmerLoading(
          isLoading: false,
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading'), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('disableAnimations removes the shimmer but keeps semantics',
      (tester) async {
    await tester.pumpWidget(
      buildHost(
        const SkeletonDashboard(),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });
}
