import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/dashboard_screen.dart';

Widget _host({
  required double width,
  required double textScale,
  double total = 1234.5,
  bool completing = false,
  VoidCallback? onComplete,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: IncompleteOrderRow(
            orderId: 'ABCDEF0123456789',
            total: total,
            dateText: '3 days ago',
            isCompleting: completing,
            onTap: () {},
            onComplete: onComplete ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  // The overflow this guards against: the "Complete" button reporting more
  // height than the space it was given.
  final widths = <double>[320, 360, 400, 419, 420, 500, 768, 1024, 1440];
  final scales = <double>[1.0, 1.3, 1.5, 2.0];
  final totals = <double>[0, 99.99, 1234.56, 987654.32];

  group('IncompleteOrderRow does not overflow', () {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('width=$width textScale=$scale', (tester) async {
          await tester.pumpWidget(_host(width: width, textScale: scale));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final total in totals) {
      testWidgets('long amount total=$total', (tester) async {
        await tester
            .pumpWidget(_host(width: 360, textScale: 1.0, total: total));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('while completing', (tester) async {
      await tester.pumpWidget(
          _host(width: 360, textScale: 1.5, completing: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('IncompleteOrderRow behaviour', () {
    testWidgets('Complete fires on tap (wide)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
          width: 800, textScale: 1.0, onComplete: () => taps++));
      await tester.pump();
      await tester.tap(find.text('Complete'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('Complete fires via icon on narrow', (tester) async {
      var taps = 0;
      // 360 < _wideLayoutMinWidth (242) is false, so 360 is actually "wide".
      // Use a width that truly forces the icon-only layout.
      await tester.pumpWidget(_host(
          width: 200, textScale: 1.0, onComplete: () => taps++));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Complete'), findsNothing);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('action is disabled while completing', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        width: 800,
        textScale: 1.0,
        completing: true,
        onComplete: () => taps++,
      ));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}