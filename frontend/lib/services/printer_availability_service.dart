import 'bluetooth_printer_service.dart';

class PrinterAvailabilityResult {
  const PrinterAvailabilityResult({
    required this.available,
    required this.message,
  });

  final bool available;
  final String message;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'available': available,
        'message': message,
      };
}

class PrinterAvailabilityService {
  PrinterAvailabilityService._();

  static Future<PrinterAvailabilityResult> resolve() async {
    BluetoothPrinterDevice? printer;
    try {
      printer = await BluetoothPrinterService.loadSavedPrinter();
    } catch (_) {
      return const PrinterAvailabilityResult(
        available: false,
        message: 'Could not read the saved printer. Check app storage access.',
      );
    }

    if (printer == null || printer.address.trim().isEmpty) {
      return const PrinterAvailabilityResult(
        available: false,
        message:
            'No printer selected. Connect one in Settings > Receipt Printing.',
      );
    }

    final availability = await BluetoothPrinterService.getAvailability();
    switch (availability) {
      case BluetoothPrinterAvailability.disabled:
        return const PrinterAvailabilityResult(
          available: false,
          message: 'Bluetooth is off. Turn it on and reconnect the printer.',
        );
      case BluetoothPrinterAvailability.permissionDenied:
        return const PrinterAvailabilityResult(
          available: false,
          message:
              'Bluetooth permission denied. Allow nearby devices access in Settings.',
        );
      case BluetoothPrinterAvailability.unsupported:
        return const PrinterAvailabilityResult(
          available: false,
          message: 'Bluetooth printing is not supported on this device.',
        );
      case BluetoothPrinterAvailability.enabled:
        break;
    }

    final connected =
        await BluetoothPrinterService.isConnected(printer.address);
    if (!connected) {
      return PrinterAvailabilityResult(
        available: false,
        message:
            '${printer.displayName} is disconnected. Turn it on and reconnect it in Settings.',
      );
    }

    return const PrinterAvailabilityResult(
      available: true,
      message: 'Printer is connected and ready.',
    );
  }
}
