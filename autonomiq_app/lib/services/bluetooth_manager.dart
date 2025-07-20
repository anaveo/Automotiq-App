import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../services/ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService _bleService;
  String? _deviceId;
  StreamSubscription<DeviceConnectionState>? _bleServiceSubscription;
  final StreamController<DeviceConnectionState> _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();

  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService() {
    // Emit initial disconnected state for UI
    _connectionStateController.add(DeviceConnectionState.disconnected);
  }

  /// Expose connection state updates for UI
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

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
        _connectionStateController.add(DeviceConnectionState.connected);
        return;
      }

      _deviceId = deviceId;

      // Cancel any existing subscription
      await _bleServiceSubscription?.cancel();

      // Subscribe to BleService's connection state stream
      _bleServiceSubscription = _bleService.connectionStateStream.listen(
        (state) async {
          _connectionStateController.add(state);
          AppLogger.logInfo(
            'Connection state for ${deviceId}: $state',
            'BluetoothManager.connectToDevice',
          );
          if (state == DeviceConnectionState.disconnected) {
            _deviceId = null;
            if (autoReconnect) {
              AppLogger.logInfo('Attempting to reconnect to $deviceId', 'BluetoothManager.connectToDevice');
              try {
                await _bleService.connectToDevice(deviceId);
              } catch (e, stackTrace) {
                AppLogger.logError(e, stackTrace, 'BluetoothManager.reconnect');
                _connectionStateController.add(DeviceConnectionState.disconnected);
              }
            }
          }
        },
        onError: (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
          _connectionStateController.add(DeviceConnectionState.disconnected);
          _deviceId = null;
        },
      );

      // Initiate connection
      await _bleService.connectToDevice(deviceId);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
      _connectionStateController.add(DeviceConnectionState.disconnected);
      _deviceId = null;
      throw Exception('Failed to connect to device: $e');
    }
  }

  /// Disconnect from the current device
  Future<void> disconnectDevice() async {
    if (_deviceId == null) {
      AppLogger.logInfo('No device to disconnect', 'BluetoothManager.disconnectDevice');
      _connectionStateController.add(DeviceConnectionState.disconnected);
      return;
    }

    try {
      await _bleService.disconnectDevice();
      _deviceId = null;
      _connectionStateController.add(DeviceConnectionState.disconnected);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      _deviceId = null;
      _connectionStateController.add(DeviceConnectionState.disconnected);
      throw Exception('Failed to disconnect device: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      await disconnectDevice();
      await _bleServiceSubscription?.cancel();
      await _connectionStateController.close();
      AppLogger.logInfo('BluetoothManager disposed', 'BluetoothManager.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.dispose');
      throw Exception('Failed to dispose BluetoothManager: $e');
    }
  }
}