import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/payment_method_dialog.dart';

void main() {
  // The dialog with every section shown is taller than the default 800x600
  // test surface — give the tests room so nothing is clipped off-screen.
  Future<void> _open(
    WidgetTester tester, {
    double totalAmount = 450,
    bool askForReceipt = false,
    void Function(PaymentDetails? result)? onResult,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showPaymentDetailsDialog(
                context,
                totalAmount: totalAmount,
                askForReceipt: askForReceipt,
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cash: computes change and completes with tendered amount',
      (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextField), '500');
    await tester.pump();
    expect(find.text('₱50.00'), findsOneWidget);

    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'cash');
    expect(result!.amountReceived, 500);
    expect(result!.change, 50);
    expect(result!.paymentStatus, 'paid');
    expect(result!.referenceNumber, isNull);
  });

  testWidgets('cash: insufficient amount blocks completion', (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextField), '400');
    await tester.pump();

    // Completing stays blocked while the amount is below the order total.
    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Payment Method'), findsOneWidget);
  });

  testWidgets('cash: exact amount quick-fill', (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.tap(find.text('Exact amount'));
    await tester.pump();
    expect(find.text('₱0.00'), findsOneWidget);

    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amountReceived, 450);
    expect(result!.change, 0);
  });

  testWidgets('gcash: optional reference and paid by default', (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.tap(find.text('GCash'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'REF-12345');
    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'gcash');
    expect(result!.referenceNumber, 'REF-12345');
    expect(result!.paymentStatus, 'paid');
    expect(result!.amountReceived, isNull);
    expect(result!.change, isNull);
  });

  testWidgets('e-wallet: status can be set to pending', (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.tap(find.text('Other E-Wallet'));
    await tester.pump();
    await tester.tap(find.text('Pending'));
    await tester.pump();

    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'other');
    expect(result!.referenceNumber, isNull);
    expect(result!.paymentStatus, 'pending');
  });

  testWidgets('cancel returns null', (tester) async {
    PaymentDetails? result;
    await _open(tester, onResult: (r) => result = r);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('receipt offer only appears when asked for', (tester) async {
    await _open(tester, askForReceipt: true);
    expect(find.text('Print a receipt for this order?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _open(tester, askForReceipt: false);
    expect(find.text('Print a receipt for this order?'), findsNothing);
  });

  testWidgets('receipt answer is carried on the result', (tester) async {
    PaymentDetails? result;
    await _open(tester, askForReceipt: true, onResult: (r) => result = r);

    await tester.tap(find.text('Print a receipt for this order?'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '450');
    await tester.pump();

    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.wantsReceipt, isTrue);
  });

  test('paymentMethodLabel maps stored values to display labels', () {
    expect(paymentMethodLabel('cash'), 'Cash');
    expect(paymentMethodLabel('gcash'), 'GCash');
    expect(paymentMethodLabel('other'), 'Other E-Wallet');
    // Unknown / legacy values fall back to Cash.
    expect(paymentMethodLabel(''), 'Cash');
  });
}
