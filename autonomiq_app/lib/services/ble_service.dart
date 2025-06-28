import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  /// Scan for ELM327 or OBD devices
  Future<List<BluetoothDevice>> scanForElmDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Request permissions (runtime required for Android 12+)
    await _requestPermissions();

    final List<BluetoothDevice> devices = [];

    // Clear any existing scan
    FlutterBluePlus.stopScan();

    final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        final name = result.device.platformName.toLowerCase();
        if ((name.contains("elm") || name.contains("obd")) &&
            !devices.contains(result.device)) {
          devices.add(result.device);
        }
      }
    });

    // Start scan (no filter = all devices)
    FlutterBluePlus.startScan(timeout: timeout);

    // Wait for the scan to complete
    await Future.delayed(timeout);

    // Clean up
    FlutterBluePlus.stopScan();
    await scanSubscription.cancel();

    return devices;
  }

  /// Connect to a BLE device
  Future<void> connect(BluetoothDevice device) async {
    final state = await device.connectionState.first;
    if (state != BluetoothConnectionState.connected) {
      await device.connect(timeout: const Duration(seconds: 10));
    }
  }

  /// Disconnect from a BLE device
  Future<void> disconnect(BluetoothDevice device) async {
    final state = await device.connectionState.first;
    if (state == BluetoothConnectionState.connected) {
      await device.disconnect();
    }
  }

  /// Get current connection state of a device
  Future<BluetoothConnectionState> getDeviceState(BluetoothDevice device) async {
    return await device.connectionState.first;
  }

  /// List all currently connected BLE devices
  List<BluetoothDevice> getConnectedDevices() {
    return FlutterBluePlus.connectedDevices;
  }

  /// Request required permissions on Android
  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        await permission.request();
      }
    }
  }
}
