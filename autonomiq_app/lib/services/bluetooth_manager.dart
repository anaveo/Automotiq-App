import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../services/ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService _bleService;

  // Look at this dumb naming scheme lol
  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService();

  DiscoveredDevice? _device;
  StreamSubscription<DeviceConnectionState>? _connectionSubscription;
  final StreamController<DeviceConnectionState> _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();

  // Expose connection state updates
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  bool _compareManufacturerData(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Scan for new OBD BLE devices by name (e.g., VEEPEAK, AUTONOMIQ)
  Future<List<DiscoveredDevice>> scanForNewObdDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = await _bleService.scanForDevices(timeout: timeout);
      return devices.where((device) {
        final name = device.name.toLowerCase();
        return name.contains('veepeak') || name.contains('autonomiq');
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.scanForNewObdDevices');
      throw Exception('Failed to scan for new OBD devices: $e');
    }
  }

  /// Scan for a specific OBD BLE device using name + manufacturerData fingerprint
  Future<DiscoveredDevice?> scanForSpecificObdDevice({
    required String expectedName,
    required Uint8List expectedManufacturerData,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = await _bleService.scanForDevices(timeout: timeout);

      final matchingDevices = devices.where(
        (device) =>
            device.name == expectedName &&
            _compareManufacturerData(device.manufacturerData, expectedManufacturerData),
      );

      return matchingDevices.isNotEmpty ? matchingDevices.first : null;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.scanForSpecificObdDevice');
      throw Exception('Failed to scan for specific OBD device: $e');
    }
  }

  Future<void> connectToDevice(DiscoveredDevice device) async {
    // try {
    //   _device = device;

    //   // Cancel any existing connection
    //   await _connectionSubscription?.cancel();

    //   // Connect and listen for state changes
    //   _connectionSubscription = _bleService.connectToDevice(device.id).listen(
    //     (state) {
    //       _connectionStateController.add(state);
    //       AppLogger.logInfo('Connection state: $state', 'BluetoothManager.connectToDevice');
    //     },
    //     onError: (error, stackTrace) {
    //       AppLogger.logError(error, stackTrace, 'BluetoothManager.connectToDevice');
    //       _connectionStateController.add(DeviceConnectionState.disconnected);
    //     },
    //   );
    // } catch (e, stackTrace) {
    //   AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
    //   rethrow;
    // }
  }

  /// Disconnect device
  Future<void> disconnectDevice() async {
    if (_device == null) return;

    try {
      await _bleService.disconnectDevice(_device!.id);
      _device = null;
      _connectionStateController.add(DeviceConnectionState.disconnected);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      rethrow;
    }
  }

  /// Clean up
  Future<void> dispose() async {
    await disconnectDevice(); // or disconnectDevice()
    await _connectionStateController.close();
  }
}