import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/receipt_printer_service.dart';

void main() {
  String textOf(List<int> bytes) => latin1.decode(bytes);

  test('builds an ESC/POS receipt with header, items, total, and cut', () {
    final bytes = ReceiptPrinterService.buildOrderReceipt(
      orderId: 'A1B2C3D4E5',
      items: [
        {
          'name': 'Chicken Rice',
          'quantity': 2,
          'price': 50.0,
          'subtotal': 100.0
        },
      ],
      totalAmount: 100,
      paymentMethod: 'cash',
      amountReceived: 200,
      change: 100,
      paymentStatus: 'paid',
      createdAt: DateTime(2026, 11, 16, 14, 5),
      eateryName: 'SmartEat Kitchen',
      address: '123 Main St',
      cashierName: 'Ana',
    );

    final text = textOf(bytes);

    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(bytes.length - 7),
        [0x1B, 0x64, 0x04, 0x1D, 0x56, 0x42, 0x00]);
    expect(text, contains('SMARTEAT KITCHEN'));
    expect(text, contains('123 Main St'));
    expect(text, contains('Order #A1B2C3D4'));
    expect(text, contains('Chicken Rice'));
    expect(text, contains('2x PHP 50.00'));
    expect(text, contains('PHP 100.00'));
    expect(text, contains('Cashier: Ana'));
    expect(text, contains('Payment: Cash'));
    expect(text, contains('Amount Received'));
    expect(text, contains('Change'));
    expect(text, contains('Thank you!'));
  });

  test('sanitizes non-ASCII characters for the printer code page', () {
    final bytes = ReceiptPrinterService.buildOrderReceipt(
      orderId: 'X1',
      items: [
        {'name': 'Café ñ', 'quantity': 1, 'price': 10, 'subtotal': 10},
      ],
      totalAmount: 10,
      paymentMethod: 'gcash',
      referenceNumber: '₱12345',
      paymentStatus: 'pending',
      createdAt: DateTime(2026, 1, 2, 3, 4),
      eateryName: 'Café Ñ',
    );

    final text = textOf(bytes);

    expect(text, contains('CAFE N'));
    expect(text, contains('Cafe n'));
    expect(text, contains('PHP 12345'));
    expect(text, contains('Status: PENDING'));
    expect(text, isNot(contains('₱')));
  });

  test('omits the cashier line when no name is supplied', () {
    final bytes = ReceiptPrinterService.buildOrderReceipt(
      orderId: 'X2',
      items: [
        {'name': 'Water', 'quantity': 1, 'price': 20, 'subtotal': 20},
      ],
      totalAmount: 20,
      paymentMethod: 'cash',
      createdAt: DateTime(2026, 1, 2, 3, 4),
    );

    expect(textOf(bytes), isNot(contains('Cashier:')));
  });
}
