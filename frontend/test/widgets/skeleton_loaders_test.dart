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

  final skeletons = <MapEntry<String, Widget>>[
    MapEntry('SkeletonDashboard', const SkeletonDashboard()),
    MapEntry('SkeletonFinance', const SkeletonFinance()),
    MapEntry('SkeletonPOS', const SkeletonPOS()),
    MapEntry('SkeletonMenu', const SkeletonMenu()),
    MapEntry('SkeletonOrders', const SkeletonOrders()),
    MapEntry('SkeletonAnalytics', const SkeletonAnalytics()),
    MapEntry('SkeletonStaff', const SkeletonStaff()),
    MapEntry('SkeletonProfile', const SkeletonProfile()),
    MapEntry('SkeletonSettings', const SkeletonSettings()),
    MapEntry('SkeletonNotifications', const SkeletonNotifications()),
    MapEntry('SkeletonRecipeList', const SkeletonRecipeList()),
    MapEntry('SkeletonReports', const SkeletonReports()),
    MapEntry('SkeletonPayroll', const SkeletonPayroll()),
    MapEntry('SkeletonItemDetail', const SkeletonItemDetail()),
    MapEntry('SkeletonDamagedItems', const SkeletonDamagedItems()),
    MapEntry('SkeletonInventory', const SkeletonInventory()),
  ];

  const expectedKeys = <String, List<String>>{
    'SkeletonDashboard': [
      'skeleton-dashboard-kpis',
      'skeleton-dashboard-briefing',
    ],
    'SkeletonFinance': [
      'skeleton-finance-kpis',
      'skeleton-finance-pnl',
    ],
    'SkeletonPOS': ['skeleton-pos-grid'],
    'SkeletonMenu': [
      'skeleton-menu-categories',
      'skeleton-menu-grid',
    ],
    'SkeletonOrders': [
      'skeleton-orders-kpis',
      'skeleton-orders-filters',
      'skeleton-orders-list',
    ],
    'SkeletonAnalytics': [
      'skeleton-analytics-kpis',
      'skeleton-analytics-summary',
      'skeleton-analytics-chart',
    ],
    'SkeletonStaff': ['skeleton-staff-list'],
    'SkeletonProfile': [
      'skeleton-profile-header',
      'skeleton-profile-attendance',
    ],
    'SkeletonSettings': ['skeleton-settings-list'],
    'SkeletonNotifications': [
      'skeleton-notifications-filters',
      'skeleton-notifications-list',
    ],
    'SkeletonRecipeList': [
      'skeleton-recipes-hero',
      'skeleton-recipes-list',
    ],
    'SkeletonReports': [
      'skeleton-reports-kpis',
      'skeleton-reports-pnl',
    ],
    'SkeletonPayroll': [
      'skeleton-payroll-list',
      'skeleton-payroll-summary',
      'skeleton-payroll-history',
    ],
    'SkeletonItemDetail': [
      'skeleton-item-detail-list',
      'skeleton-item-detail-header',
    ],
    'SkeletonDamagedItems': [
      'skeleton-damaged-list',
      'skeleton-damaged-summary',
    ],
    'SkeletonInventory': [
      'skeleton-inventory-overview',
      'skeleton-inventory-health',
      'skeleton-inventory-stat-chips',
    ],
  };

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

  Future<void> expectSkeleton(
    WidgetTester tester,
    Widget skeleton, {
    ThemeData? theme,
    bool disableAnimations = false,
    bool expectShimmer = true,
  }) async {
    await tester.pumpWidget(
      buildHost(
        skeleton,
        theme: theme,
        disableAnimations: disableAnimations,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ShimmerLoading), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(
      find.byType(ShaderMask),
      expectShimmer ? findsOneWidget : findsNothing,
    );
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    for (final skeleton in skeletons) {
      testWidgets('${skeleton.key} renders at $label', (tester) async {
        await setSurface(tester, size);
        await expectSkeleton(tester, skeleton.value);

        for (final key in expectedKeys[skeleton.key]!) {
          expect(find.byKey(Key(key)), findsOneWidget);
        }
      });
    }
  }

  testWidgets('SkeletonPOS respects supplied layout parameters',
      (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(buildHost(posForWidth(390)));
    await tester.pump();

    final grid =
        tester.widget<GridView>(find.byKey(const Key('skeleton-pos-grid')));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.childAspectRatio, closeTo(0.64, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonInventory switches section-specific bodies',
      (tester) async {
    await setSurface(tester, const Size(900, 1000));
    const sectionKeys = <String>[
      'skeleton-inventory-overview',
      'skeleton-inventory-items',
      'skeleton-inventory-movements',
      'skeleton-inventory-purchases',
      'skeleton-inventory-adjustments',
      'skeleton-inventory-reports',
    ];

    for (var section = 0; section < sectionKeys.length; section++) {
      await expectSkeleton(tester, SkeletonInventory(section: section));
      expect(find.byKey(Key(sectionKeys[section])), findsOneWidget);
    }
  });

  testWidgets('SkeletonStaff supports header and row options', (tester) async {
    await setSurface(tester, const Size(900, 1000));
    await expectSkeleton(tester, const SkeletonStaff(rows: 0));
    expect(find.byType(SkeletonCircle), findsNothing);

    await expectSkeleton(
      tester,
      const SkeletonStaff(rows: 2, includeHeader: true),
    );
    expect(find.byType(SkeletonCircle), findsNWidgets(2));
  });

  testWidgets('skeletons adapt to the light theme', (tester) async {
    await setSurface(tester, const Size(900, 1000));
    for (final skeleton in skeletons) {
      await expectSkeleton(
        tester,
        skeleton.value,
        theme: AppTheme.lightTheme,
      );
    }
  });

  testWidgets('disableAnimations removes shimmers from every skeleton',
      (tester) async {
    await setSurface(tester, const Size(390, 844));
    for (final skeleton in skeletons) {
      await expectSkeleton(
        tester,
        skeleton.value,
        disableAnimations: true,
        expectShimmer: false,
      );
    }
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
}
