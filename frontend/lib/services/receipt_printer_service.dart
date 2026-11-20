import 'dart:convert';
import 'dart:typed_data';

import 'bluetooth_printer_service.dart';
import 'firebase_service.dart';

class ReceiptPrintResult {
  const ReceiptPrintResult._(this.printed, [this.error]);

  final bool printed;
  final String? error;

  factory ReceiptPrintResult.success() => const ReceiptPrintResult._(true);

  factory ReceiptPrintResult.failure(String error) =>
      ReceiptPrintResult._(false, error);
}

/// Sends ESC/POS receipts to the saved Bluetooth Classic printer.
class ReceiptPrinterService {
  ReceiptPrinterService._();

  static const int _paperWidth = 32;

  static Future<ReceiptPrintResult> printOrder({
    required String orderId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    double? amountReceived,
    double? change,
    String? referenceNumber,
    String paymentStatus = 'paid',
    DateTime? createdAt,
    String cashierName = '',
  }) async {
    final printer = await BluetoothPrinterService.loadSavedPrinter();
    if (printer == null) {
      return ReceiptPrintResult.failure(
        'No Bluetooth printer selected. Open Settings > Receipt Printing.',
      );
    }

    var connected = await BluetoothPrinterService.isConnected(printer.address);
    if (!connected) {
      connected = await BluetoothPrinterService.connect(printer.address);
    }
    if (!connected) {
      return ReceiptPrintResult.failure(
        'Could not connect to ${printer.displayName}. Make sure it is on and nearby.',
      );
    }

    var eateryName = '';
    var address = '';
    try {
      final eateryId = await FirebaseService.getCurrentEateryId();
      if (eateryId != null && eateryId.trim().isNotEmpty) {
        final eatery = await FirebaseService.getEatery(eateryId.trim());
        eateryName = (eatery?['name'] ?? '').toString().trim();
        address = (eatery?['address'] ?? '').toString().trim();
      }
    } catch (_) {
      // Receipt still prints with whatever header data was available.
    }

    final bytes = buildOrderReceipt(
      orderId: orderId,
      items: items,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
      amountReceived: amountReceived,
      change: change,
      referenceNumber: referenceNumber,
      paymentStatus: paymentStatus,
      createdAt: createdAt ?? DateTime.now(),
      eateryName: eateryName,
      address: address,
      cashierName: cashierName.trim(),
    );

    final printed =
        await BluetoothPrinterService.printBytes(printer.address, bytes);
    if (!printed) {
      return ReceiptPrintResult.failure(
        'Could not send the receipt to ${printer.displayName}.',
      );
    }
    return ReceiptPrintResult.success();
  }

  static Uint8List buildOrderReceipt({
    required String orderId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    required DateTime createdAt,
    double? amountReceived,
    double? change,
    String? referenceNumber,
    String paymentStatus = 'paid',
    String eateryName = '',
    String address = '',
    String cashierName = '',
  }) {
    final builder = BytesBuilder();

    void add(List<int> bytes) => builder.add(bytes);
    void line(String value) => add(ascii.encode('${_ascii(value)}\n'));

    void twoColumn(String left, String right) {
      final leftText = _ascii(left);
      final rightText = _ascii(right);
      if (rightText.length >= _paperWidth) {
        line(rightText);
        return;
      }
      if (leftText.length + rightText.length + 1 <= _paperWidth) {
        line('$leftText'
            '${' ' * (_paperWidth - leftText.length - rightText.length)}'
            '$rightText');
      } else {
        line(leftText);
        line('${' ' * (_paperWidth - rightText.length)}$rightText');
      }
    }

    void divider() => line('-' * _paperWidth);

    // Initialize, select PC437, and reset any previous formatting.
    add([0x1B, 0x40]);
    add([0x1B, 0x74, 0x00]);

    add([0x1B, 0x61, 0x01]);
    add([0x1B, 0x45, 0x01]);
    add([0x1D, 0x21, 0x11]);
    final header = eateryName.isEmpty ? 'SMARTEAT' : eateryName.toUpperCase();
    for (final part in _wrap(_ascii(header), _paperWidth ~/ 2)) {
      line(part);
    }
    add([0x1D, 0x21, 0x00]);
    add([0x1B, 0x45, 0x00]);

    if (address.isNotEmpty) {
      for (final part in _wrap(_ascii(address), _paperWidth)) {
        line(part);
      }
    }
    line('SALES RECEIPT');
    line('');
    add([0x1B, 0x61, 0x00]);

    final shortId = orderId.trim();
    line('Order #${shortId.length <= 8 ? shortId : shortId.substring(0, 8)}');
    line('Date: ${_formatDateTime(createdAt)}');
    if (cashierName.isNotEmpty) {
      line('Cashier: $cashierName');
    }
    divider();

    for (final item in items) {
      final name = (item['name'] ?? 'Item').toString().trim();
      final qty = _asInt(item['quantity']);
      final price = _asDouble(item['price']);
      final subtotal =
          item['subtotal'] != null ? _asDouble(item['subtotal']) : price * qty;
      for (final part in _wrap(_ascii(name), _paperWidth)) {
        line(part);
      }
      twoColumn(
        '  ${qty}x ${_money(price)}',
        _money(subtotal),
      );
    }

    divider();
    add([0x1B, 0x45, 0x01]);
    add([0x1D, 0x21, 0x01]);
    twoColumn('TOTAL', _money(totalAmount));
    add([0x1D, 0x21, 0x00]);
    add([0x1B, 0x45, 0x00]);

    line('Payment: ${_paymentLabel(paymentMethod)}');
    if (paymentStatus.toLowerCase() != 'paid') {
      line('Status: ${paymentStatus.toUpperCase()}');
    }
    if (amountReceived != null) {
      twoColumn('Amount Received', _money(amountReceived));
    }
    if (change != null) {
      twoColumn('Change', _money(change));
    }
    final reference = (referenceNumber ?? '').trim();
    if (reference.isNotEmpty) {
      for (final part in _wrap('Ref: $reference', _paperWidth)) {
        line(part);
      }
    }

    line('');
    add([0x1B, 0x61, 0x01]);
    line('Thank you!');
    line('Powered by SmartEat');

    // Feed enough paper for the cutter and cut.
    add([0x1B, 0x64, 0x04]);
    add([0x1D, 0x56, 0x42, 0x00]);

    return builder.toBytes();
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0.0;
  }

  static String _money(double value) => 'PHP ${value.toStringAsFixed(2)}';

  static String _paymentLabel(String method) {
    switch (method.trim().toLowerCase()) {
      case 'gcash':
        return 'GCash';
      case 'other':
        return 'Other E-Wallet';
      default:
        return 'Cash';
    }
  }

  static String _formatDateTime(DateTime value) {
    final hour =
        value.hour > 12 ? value.hour - 12 : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month/$day/${value.year} $hour:$minute $period';
  }

  static String _ascii(String value) {
    const replacements = <String, String>{
      '₱': 'PHP ',
      '–': '-',
      '—': '-',
      '•': '*',
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
      '…': '...',
      'ñ': 'n',
      'Ñ': 'N',
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
    };

    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCodes([rune]);
      final replacement = replacements[char];
      if (replacement != null) {
        buffer.write(replacement);
      } else if (rune >= 32 && rune <= 126) {
        buffer.write(char);
      } else if (rune == 10 || rune == 13 || rune == 9) {
        buffer.write(' ');
      } else {
        buffer.write('?');
      }
    }
    return buffer.toString();
  }

  static List<String> _wrap(String value, int width) {
    final words = value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        for (var i = 0; i < word.length; i += width) {
          lines.add(word.substring(
              i, i + width > word.length ? word.length : i + width));
        }
        continue;
      }
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? const [''] : lines;
  }
}
