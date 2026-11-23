import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/sage_header_button.dart';

class _AnchorHost extends StatefulWidget {
  const _AnchorHost({required this.onAnchorChanged});

  final ValueChanged<Rect?> onAnchorChanged;

  @override
  State<_AnchorHost> createState() => _AnchorHostState();
}

class _AnchorHostState extends State<_AnchorHost> {
  double _top = 40;
  bool _show = true;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 240,
      child: Stack(
        children: [
          if (_show)
            Positioned(
              left: 100,
              top: _top,
              child: SageAnchorPublisher(
                onAnchorChanged: widget.onAnchorChanged,
                child: const SizedBox(width: 34, height: 34),
              ),
            ),
          Positioned(
            left: 0,
            bottom: 0,
            child: TextButton(
              onPressed: () => setState(() => _top += 20),
              child: const Text('move'),
            ),
          ),
          Positioned(
            left: 100,
            bottom: 0,
            child: TextButton(
              onPressed: () => setState(() => _show = false),
              child: const Text('hide'),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  Finder findAnchorKey() => find.byWidgetPredicate(
        (widget) =>
            widget.key is GlobalKey &&
            widget.key.toString().contains('sage-header-anchor'),
      );

  testWidgets('publishes live rect, tracks layout changes, clears on dispose',
      (tester) async {
    final published = <Rect?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _AnchorHost(onAnchorChanged: published.add),
      ),
    ));
    await tester.pumpAndSettle();

    expect(published, [Rect.fromLTWH(100, 40, 34, 34)]);
    expect(findAnchorKey(), findsOneWidget);
    final key = tester.widget(findAnchorKey()).key;

    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();

    expect(published.last, Rect.fromLTWH(100, 60, 34, 34));
    expect(identical(tester.widget(findAnchorKey()).key, key), isTrue);

    await tester.tap(find.text('hide'));
    await tester.pumpAndSettle();

    expect(published.last, isNull);
    expect(findAnchorKey(), findsNothing);
  });
}
