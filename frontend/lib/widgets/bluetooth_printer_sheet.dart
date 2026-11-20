import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bluetooth_printer_service.dart';

Future<BluetoothPrinterDevice?> showBluetoothPrinterSheet(
  BuildContext context, {
  BluetoothPrinterDevice? savedPrinter,
}) {
  return showModalBottomSheet<BluetoothPrinterDevice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => BluetoothPrinterSheet(savedPrinter: savedPrinter),
  );
}

class BluetoothPrinterSheet extends StatefulWidget {
  const BluetoothPrinterSheet({super.key, this.savedPrinter});

  final BluetoothPrinterDevice? savedPrinter;

  @override
  State<BluetoothPrinterSheet> createState() => _BluetoothPrinterSheetState();
}

class _BluetoothPrinterSheetState extends State<BluetoothPrinterSheet> {
  final Map<String, BluetoothPrinterDevice> _devices = {};
  StreamSubscription<BluetoothPrinterScanEvent>? _subscription;
  Timer? _scanTimer;
  BluetoothPrinterAvailability? _availability;
  bool _scanning = true;
  bool _connecting = false;
  String? _connectingAddress;
  String? _message;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _subscription?.cancel();
    BluetoothPrinterService.stopDiscovery();
    super.dispose();
  }

  void _startScan() {
    _subscription?.cancel();
    _scanTimer?.cancel();
    setState(() {
      _devices.clear();
      _availability = null;
      _scanning = true;
      _message = null;
    });
    _subscription = BluetoothPrinterService.discovery.listen(
      _onEvent,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _availability = BluetoothPrinterAvailability.unsupported;
        });
      },
    );
    BluetoothPrinterService.getAvailability().then((availability) {
      if (!mounted ||
          availability != BluetoothPrinterAvailability.unsupported) {
        return;
      }
      _scanTimer?.cancel();
      _subscription?.cancel();
      setState(() {
        _scanning = false;
        _availability = BluetoothPrinterAvailability.unsupported;
      });
    });
    _scanTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() => _scanning = false);
    });
  }

  void _onEvent(BluetoothPrinterScanEvent event) {
    if (!mounted) return;
    if (event.availability != null) {
      setState(() {
        _availability = event.availability;
        if (event.availability != BluetoothPrinterAvailability.enabled) {
          _scanning = false;
        }
      });
    }
    if (event.device != null) {
      final device = event.device!;
      setState(() => _devices[device.address] = device);
    }
    if (event.scanStarted) {
      setState(() => _scanning = true);
    }
    if (event.scanFinished) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothPrinterDevice device) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _connectingAddress = device.address;
      _message = null;
    });
    await BluetoothPrinterService.stopDiscovery();
    final connected = await BluetoothPrinterService.connect(device.address);
    if (!mounted) return;
    if (connected) {
      await BluetoothPrinterService.savePrinter(device);
      if (!mounted) return;
      Navigator.of(context).pop(device);
      return;
    }
    setState(() {
      _connecting = false;
      _connectingAddress = null;
      _message =
          'Could not connect. Turn the printer on, pair it in Bluetooth settings, then try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.78;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bluetooth Printer',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Search for a nearby receipt printer and connect this device directly.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_message != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_availability == BluetoothPrinterAvailability.unsupported) {
      return _statusView(
        icon: Icons.bluetooth_disabled,
        title: 'Bluetooth setup unavailable',
        message:
            'Use the SmartEat Android app on the device connected to the printer.',
      );
    }

    if (_availability == BluetoothPrinterAvailability.permissionDenied) {
      return _statusView(
        icon: Icons.lock_outline,
        title: 'Bluetooth permission needed',
        message:
            'Allow nearby devices access so SmartEat can find and connect to the printer.',
        action: FilledButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Allow Bluetooth'),
        ),
      );
    }

    if (_availability == BluetoothPrinterAvailability.disabled) {
      return _statusView(
        icon: Icons.bluetooth_disabled,
        title: 'Bluetooth is off',
        message: 'Turn on Bluetooth, then search again for your printer.',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: BluetoothPrinterService.openBluetoothSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Bluetooth settings'),
            ),
            FilledButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Search again'),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return _emptyView();
    }

    final devices = _devices.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: devices.length + 1,
      separatorBuilder: (_, index) =>
          index == 0 ? const SizedBox(height: 4) : const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Text(
                  'Nearby devices',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (_scanning)
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Searching',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  )
                else
                  TextButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Search again'),
                  ),
              ],
            ),
          );
        }
        return _deviceTile(devices[index - 1]);
      },
    );
  }

  Widget _deviceTile(BluetoothPrinterDevice device) {
    final isConnecting = _connecting && _connectingAddress == device.address;
    final isSaved = widget.savedPrinter?.address == device.address;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(
          Icons.print_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        device.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        device.bonded ? 'Paired • ${device.address}' : device.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isConnecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isSaved
              ? Chip(
                  label: const Text('Saved'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Colors.grey.shade300),
                )
              : const Icon(Icons.chevron_right),
      enabled: !_connecting,
      onTap: () => _connect(device),
    );
  }

  Widget _emptyView() {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Searching for nearby printers...',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure the printer is turned on and nearby.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    return _statusView(
      icon: Icons.bluetooth_searching,
      title: 'No printers found',
      message:
          'Turn the printer on, keep it nearby, then search again. You can also pair it first in Bluetooth settings.',
      action: FilledButton.icon(
        onPressed: _startScan,
        icon: const Icon(Icons.refresh),
        label: const Text('Search again'),
      ),
    );
  }

  Widget _statusView({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
