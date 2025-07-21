import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../services/ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService _bleService;
  String? _deviceId;

  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService();

  /// Get the current connection state of the device
  DeviceConnectionState getDeviceState() => _bleService.getDeviceState();

  /// Expose BleService's connection state stream for UI
  Stream<DeviceConnectionState> get connectionStateStream => _bleService.connectionStateStream;

  /// Get the currently connected device ID, if any
  String? get currentDeviceId => _deviceId;

  /// Compare manufacturer data for device identification
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
      final obdDevices = devices.where((device) {
        final name = device.name.toLowerCase();
        return name.contains('veepeak') || name.contains('autonomiq');
      }).toList();
      AppLogger.logInfo(
        'Found ${obdDevices.length} OBD devices: ${obdDevices.map((d) => d.name).toList()}',
        'BluetoothManager.scanForNewObdDevices',
      );
      return obdDevices;
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
      final device = matchingDevices.isNotEmpty ? matchingDevices.first : null;
      AppLogger.logInfo(
        device != null
            ? 'Found specific OBD device: ${device.name}'
            : 'No matching OBD device found for name: $expectedName',
        'BluetoothManager.scanForSpecificObdDevice',
      );
      return device;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.scanForSpecificObdDevice');
      throw Exception('Failed to scan for specific OBD device: $e');
    }
  }

  /// Connect to a BLE device
  Future<void> connectToDevice(String deviceId, {bool autoReconnect = false}) async {
    try {
      if (_deviceId == deviceId && _bleService.getDeviceState() == DeviceConnectionState.connected) {
        AppLogger.logInfo(
          'Already connected to device: $deviceId',
          'BluetoothManager.connectToDevice',
        );
        return;
      }

      _deviceId = deviceId;
      await _bleService.connectToDevice(deviceId, connectionTimeout: const Duration(seconds: 10));

      if (autoReconnect) {
        // Listen to the connection state stream for auto-reconnect logic
        final subscription = _bleService.connectionStateStream.listen(
          (state) async {
            if (state == DeviceConnectionState.disconnected && _deviceId != null) {
              AppLogger.logInfo('Attempting to reconnect to $deviceId', 'BluetoothManager.connectToDevice');
              try {
                await _bleService.connectToDevice(deviceId);
              } catch (e, stackTrace) {
                AppLogger.logError(e, stackTrace, 'BluetoothManager.reconnect');
                _deviceId = null;
              }
            }
          },
          onError: (e, stackTrace) {
            AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
            _deviceId = null;
          },
        );

        // Cancel the subscription when disconnecting or disposing
        _bleService.connectionStateStream.listen(null).onDone(() {
          subscription.cancel();
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
      _deviceId = null;
      throw Exception('Failed to connect to device: $e');
    }
  }

  /// Disconnect from the current device
  Future<void> disconnectDevice() async {
    if (_deviceId == null) {
      AppLogger.logInfo('No device to disconnect', 'BluetoothManager.disconnectDevice');
      return;
    }

    try {
      await _bleService.disconnectDevice();
      _deviceId = null;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      _deviceId = null;
      throw Exception('Failed to disconnect device: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      await disconnectDevice();
      AppLogger.logInfo('BluetoothManager disposed', 'BluetoothManager.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.dispose');
      throw Exception('Failed to dispose BluetoothManager: $e');
    }
  }
}