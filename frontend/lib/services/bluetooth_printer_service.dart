import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BluetoothPrinterAvailability {
  enabled,
  disabled,
  permissionDenied,
  unsupported,
}

class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({
    required this.address,
    this.name,
    this.bonded = false,
  });

  final String address;
  final String? name;
  final bool bonded;

  String get displayName {
    final value = (name ?? '').trim();
    return value.isEmpty ? 'Unknown printer' : value;
  }

  factory BluetoothPrinterDevice.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothPrinterDevice(
      address: (map['address'] ?? '').toString(),
      name: (map['name'] ?? '').toString().trim().isEmpty
          ? null
          : (map['name'] ?? '').toString().trim(),
      bonded: map['bonded'] == true,
    );
  }
}

class BluetoothPrinterScanEvent {
  const BluetoothPrinterScanEvent({
    this.device,
    this.availability,
    this.scanStarted = false,
    this.scanFinished = false,
  });

  final BluetoothPrinterDevice? device;
  final BluetoothPrinterAvailability? availability;
  final bool scanStarted;
  final bool scanFinished;
}

class BluetoothPrinterService {
  BluetoothPrinterService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.smarteat/bluetooth_printer');
  static const EventChannel _events =
      EventChannel('com.example.smarteat/bluetooth_printer/devices');
  static const String _addressKey = 'bluetooth_printer_address';
  static const String _nameKey = 'bluetooth_printer_name';

  static Stream<BluetoothPrinterScanEvent> get discovery {
    return _events.receiveBroadcastStream().map(_parseEvent);
  }

  static BluetoothPrinterScanEvent _parseEvent(dynamic raw) {
    final map = Map<dynamic, dynamic>.from(raw as Map);
    final type = (map['type'] ?? '').toString();

    switch (type) {
      case 'device':
        return BluetoothPrinterScanEvent(
          device: BluetoothPrinterDevice.fromMap(map),
        );
      case 'state':
        return BluetoothPrinterScanEvent(
          availability: _availabilityFromValue(map['state']),
        );
      case 'scanStarted':
        return const BluetoothPrinterScanEvent(scanStarted: true);
      case 'scanFinished':
        return const BluetoothPrinterScanEvent(scanFinished: true);
      default:
        return const BluetoothPrinterScanEvent();
    }
  }

  static BluetoothPrinterAvailability _availabilityFromValue(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'enabled':
        return BluetoothPrinterAvailability.enabled;
      case 'disabled':
        return BluetoothPrinterAvailability.disabled;
      case 'permission':
        return BluetoothPrinterAvailability.permissionDenied;
      default:
        return BluetoothPrinterAvailability.unsupported;
    }
  }

  static Future<BluetoothPrinterAvailability> getAvailability() async {
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('getState');
      if (state == null || state['supported'] != true) {
        return BluetoothPrinterAvailability.unsupported;
      }
      if (state['permissionGranted'] != true) {
        return BluetoothPrinterAvailability.permissionDenied;
      }
      if (state['enabled'] != true) {
        return BluetoothPrinterAvailability.disabled;
      }
      return BluetoothPrinterAvailability.enabled;
    } on MissingPluginException {
      return BluetoothPrinterAvailability.unsupported;
    } catch (_) {
      return BluetoothPrinterAvailability.unsupported;
    }
  }

  static Future<void> startDiscovery() async {
    try {
      await _channel.invokeMethod<void>('startDiscovery');
    } catch (_) {}
  }

  static Future<void> stopDiscovery() async {
    try {
      await _channel.invokeMethod<void>('stopDiscovery');
    } catch (_) {}
  }

  static Future<bool> connect(String address) async {
    try {
      return await _channel.invokeMethod<bool>(
            'connect',
            <String, dynamic>{'address': address},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> disconnect(String address) async {
    try {
      return await _channel.invokeMethod<bool>(
            'disconnect',
            <String, dynamic>{'address': address},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isConnected(String address) async {
    try {
      return await _channel.invokeMethod<bool>(
            'isConnected',
            <String, dynamic>{'address': address},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> printBytes(String address, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>(
            'print',
            <String, dynamic>{
              'address': address,
              'bytes': bytes,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openBluetoothSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  static Future<BluetoothPrinterDevice?> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_addressKey)?.trim() ?? '';
    if (address.isEmpty) return null;
    final name = prefs.getString(_nameKey)?.trim() ?? '';
    return BluetoothPrinterDevice(
      address: address,
      name: name.isEmpty ? null : name,
    );
  }

  static Future<void> savePrinter(BluetoothPrinterDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressKey, device.address);
    await prefs.setString(_nameKey, device.name ?? '');
  }

  static Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_addressKey);
    await prefs.remove(_nameKey);
  }
}
