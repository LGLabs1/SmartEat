import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/sage_popup_bubble.dart';

void main() {
  group('computeSageBubblePlacement', () {
    test('places the bubble below a centred header avatar', () {
      final anchor = Rect.fromLTWH(380, 20, 34, 34);
      final placement = computeSageBubblePlacement(
        anchor,
        const Size(800, 600),
        EdgeInsets.zero,
      );

      expect(placement.rect.width, 260);
      expect(placement.rect.height, 56);
      expect(placement.rect.top, anchor.bottom + 10);
      expect(placement.rect.center.dx, anchor.center.dx);
      expect(placement.tailAtTop, isTrue);
      expect(placement.tailDx, 130);
    });

    test('flips above the avatar near the bottom edge', () {
      final anchor = Rect.fromLTWH(380, 520, 34, 34);
      final placement = computeSageBubblePlacement(
        anchor,
        const Size(800, 600),
        EdgeInsets.zero,
      );

      expect(placement.rect.bottom, lessThan(anchor.top));
      expect(placement.tailAtTop, isFalse);
    });

    test('clamps horizontally into the safe area on narrow screens', () {
      final anchor = Rect.fromLTWH(300, 40, 30, 30);
      final placement = computeSageBubblePlacement(
        anchor,
        const Size(320, 700),
        const EdgeInsets.symmetric(horizontal: 8),
      );

      expect(placement.rect.left, 52);
      expect(placement.rect.right, 312);
      expect(placement.tailDx, 244);
      expect(placement.tailDx, lessThan(placement.rect.width - 8));
    });

    test('shrinks the bubble when the safe width is smaller than 260', () {
      final placement = computeSageBubblePlacement(
        Rect.fromLTWH(90, 20, 30, 30),
        const Size(200, 500),
        const EdgeInsets.symmetric(horizontal: 8),
      );

      expect(placement.rect.width, 184);
      expect(placement.rect.left, 8);
      expect(placement.rect.right, 192);
    });

    test('never leaves the top and bottom safe insets', () {
      final placement = computeSageBubblePlacement(
        Rect.fromLTWH(300, 8, 34, 34),
        const Size(800, 120),
        const EdgeInsets.fromLTRB(0, 24, 0, 16),
      );

      expect(placement.rect.top, greaterThanOrEqualTo(24));
      expect(placement.rect.bottom, lessThanOrEqualTo(120 - 16));
    });
  });

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildBubble({
    required Rect anchor,
    required VoidCallback onOpen,
    required VoidCallback onDismiss,
  }) {
    return MaterialApp(
      home: Stack(
        children: [
          SagePopupBubble(
            anchor: anchor,
            message: 'Check the stock',
            onOpen: onOpen,
            onDismiss: onDismiss,
          ),
        ],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    );
  }

  testWidgets('bubble renders at the computed anchor rect with semantics',
      (tester) async {
    await setSurface(tester, const Size(800, 600));
    final anchor = Rect.fromLTWH(380, 20, 34, 34);
    await tester.pumpWidget(buildBubble(
      anchor: anchor,
      onOpen: () {},
      onDismiss: () {},
    ));
    final semanticsHandle = tester.ensureSemantics();
    await tester.pump();

    final expected = computeSageBubblePlacement(
        anchor, const Size(800, 600), EdgeInsets.zero);
    expect(tester.getRect(find.byKey(const Key('sage-popup-bubble'))),
        expected.rect);
    expect(find.text('Check the stock'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Sage says: Check the stock',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Sage says: Check the stock')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sage-popup-close')), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets('message tap opens, close and outside tap dismiss',
      (tester) async {
    await setSurface(tester, const Size(800, 600));
    var opens = 0;
    var dismissals = 0;
    await tester.pumpWidget(buildBubble(
      anchor: const Rect.fromLTWH(380, 20, 34, 34),
      onOpen: () => opens++,
      onDismiss: () => dismissals++,
    ));

    await tester.tap(find.text('Check the stock'));
    expect(opens, 1);
    expect(dismissals, 0);

    await tester.tap(find.byKey(const Key('sage-popup-close')));
    expect(dismissals, 1);

    await tester.tapAt(const Offset(12, 540));
    expect(dismissals, 2);
  });
}
