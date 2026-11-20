import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/dashboard_screen.dart';
import 'package:smarteat/theme.dart';
import 'package:smarteat/widgets/dashboard/animated_dashboard_stack.dart';
import 'package:smarteat/widgets/dashboard/dashboard_back_handler.dart';

class _CounterTab extends StatefulWidget {
  const _CounterTab({required this.label});

  final String label;

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.label}:$_count'),
        ElevatedButton(
          onPressed: () => setState(() => _count++),
          child: Text('Increment ${widget.label}'),
        ),
      ],
    );
  }
}

class _StackHost extends StatefulWidget {
  const _StackHost();

  @override
  State<_StackHost> createState() => _StackHostState();
}

class _StackHostState extends State<_StackHost> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => setState(() => _index = 0),
                  child: const Text('Go A'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _index = 1),
                  child: const Text('Go B'),
                ),
              ],
            ),
            Expanded(
              child: AnimatedDashboardStack(
                index: _index,
                children: const [
                  const Center(child: _CounterTab(label: 'A')),
                  const Center(child: _CounterTab(label: 'B')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  test('DashboardTabHistory pushes, unwinds, and resets', () {
    final history = DashboardTabHistory(0);

    expect(history.current, 0);
    expect(history.canGoBack, isFalse);
    expect(history.back(), isFalse);
    expect(history.snapshot, [0]);

    history.push(2);
    history.push(2);
    history.push(5);
    expect(history.current, 5);
    expect(history.canGoBack, isTrue);
    expect(history.snapshot, [0, 2, 5]);

    expect(history.back(), isTrue);
    expect(history.current, 2);
    expect(history.back(), isTrue);
    expect(history.current, 0);
    expect(history.canGoBack, isFalse);

    history.push(4);
    history.reset(0);
    expect(history.snapshot, [0]);
  });

  test('DashboardBackHandler delegates unwind decisions', () {
    var canUnwind = false;
    var unwindCalls = 0;
    final handler = DashboardBackHandler(
      canUnwind: () => canUnwind,
      unwind: () {
        unwindCalls++;
        return true;
      },
    );

    expect(handler.canUnwind(), isFalse);
    canUnwind = true;
    expect(handler.canUnwind(), isTrue);
    expect(handler.unwind(), isTrue);
    expect(unwindCalls, 1);
  });

  test('dashboard theme uses the dark Sage palette', () {
    final theme = AppTheme.dashboardTheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppTheme.sageNavy);
    expect(theme.colorScheme.primary, AppTheme.sageAccent);
    expect(theme.colorScheme.secondary, AppTheme.sageCyan);
  });

  test('sidebar width is responsive on phone, tablet, and desktop', () {
    expect(dashboardSidebarWidth(390), 320);
    expect(dashboardSidebarWidth(200), 248);
    expect(dashboardSidebarWidth(768), 260);
    expect(dashboardSidebarWidth(1440), 260);
  });

  testWidgets('AnimatedDashboardStack animates tabs and preserves state',
      (WidgetTester tester) async {
    await tester.pumpWidget(const _StackHost());

    expect(find.text('A:0'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('A:0'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      1,
    );

    await tester.tap(find.text('Increment A'));
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);

    await tester.tap(find.text('Go B'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('A:1'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('B:0'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      1,
    );

    await tester.tap(find.text('Increment B'));
    await tester.pump();
    await tester.tap(find.text('Go A'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('A:1'), findsOneWidget);
    expect(find.text('B:1'), findsOneWidget);
  });
}
