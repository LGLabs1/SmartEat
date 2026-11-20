import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/pos/receipt_printer_hint.dart';

void main() {
  testWidgets('renders the unavailable title and detail', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReceiptPrinterHint(
            message: 'No Bluetooth printer paired.',
          ),
        ),
      ),
    );

    expect(find.text('Receipt printer unavailable'), findsOneWidget);
    expect(find.text('No Bluetooth printer paired.'), findsOneWidget);
    expect(find.byIcon(Icons.print_disabled_outlined), findsOneWidget);
  });

  testWidgets('hides the detail when the message is blank', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReceiptPrinterHint(message: '   '),
        ),
      ),
    );

    expect(find.text('Receipt printer unavailable'), findsOneWidget);
    expect(find.text('   '), findsNothing);
  });
}
