import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'permission_service.dart';
import '../utils/bluetooth_adapter.dart';
import '../utils/logger.dart';

class BleService {
  final BluetoothAdapter adapter;
  final PermissionService permissionService;

  BleService({
    required this.adapter,
    required this.permissionService,
  });

  /// Scan for BLE devices
  Future<List<DiscoveredDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 5),
    List<Uuid> withServices = const [],
  }) async {
    try {
      await requestPermissions();
      final devices = <DiscoveredDevice>[];
      StreamSubscription<DiscoveredDevice>? scanSubscription;

      try {
        scanSubscription = adapter.scanForDevices(withServices: withServices).listen(
          (device) {
            if (!devices.any((d) => d.id == device.id)) {
              devices.add(device);
            }
          },
          onError: (e, stackTrace) {
            AppLogger.logError(e, stackTrace, 'BleService.scanForDevices');
            throw Exception('Scan error: $e');
          },
        );

        await Future.delayed(timeout);
      } catch (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'BleService.scanForDevices');
        throw Exception('Failed to scan for devices: $e');
      } finally {
        await scanSubscription?.cancel();
      }

      return devices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.scanForDevices');
      throw Exception('Failed to scan for devices: $e');
    }
  }

  /// Reconnect to a device by ID
  Future<void> reconnectToDevice(String deviceId) async {
    try {
      await requestPermissions();
      await adapter.connectToDevice(deviceId);
      AppLogger.logInfo('Reconnected to device: $deviceId', 'BleService.reconnectToDevice');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.reconnectToDevice');
      throw Exception('Failed to reconnect to device: $e');
    }
  }

  /// Connect to a BLE device
  Future<void> connectToDevice(String deviceId) async {
    try {
      await adapter.connectToDevice(deviceId).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Connection timeout for device: $deviceId'),
      );
      AppLogger.logInfo('Connected to device: $deviceId', 'BleService.connectToDevice');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.connectToDevice');
      throw Exception('Failed to connect to device: $e');
    }
  }

  /// Disconnect from a BLE device
  Future<void> disconnectDevice(String deviceId) async {
    try {
      await adapter.disconnectDevice(deviceId).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Disconnection timeout for device: $deviceId'),
      );
      AppLogger.logInfo('Disconnected from device: $deviceId', 'BleService.disconnectDevice');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.disconnectDevice');
      throw Exception('Failed to disconnect from device: $e');
    }
  }

  /// Get current connection state of a device
  Future<DeviceConnectionState> getDeviceState(String deviceId) async {
    try {
      return await adapter
          .getConnectionStateStream(deviceId)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('Connection state timeout'))
          .then((state) => state.connectionState);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.getDeviceState');
      throw Exception('Failed to get device state: $e');
    }
  }

  /// Stream connection state of a device
  Stream<DeviceConnectionState> getDeviceStateStream(String deviceId) {
    try {
      return adapter.getConnectionStateStream(deviceId).map((state) => state.connectionState);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.getDeviceStateStream');
      throw Exception('Failed to stream device state: $e');
    }
  }

  /// Request MTU for a device
  Future<void> requestMtu(String deviceId, int mtu) async {
    try {
      await adapter.requestMtu(deviceId, mtu);
      AppLogger.logInfo('MTU set to $mtu for device: $deviceId', 'BleService.requestMtu');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.requestMtu');
      throw Exception('Failed to request MTU: $e');
    }
  }

  /// Clear GATT cache for a device
  Future<void> clearGattCache(String deviceId) async {
    try {
      await adapter.clearGattCache(deviceId);
      AppLogger.logInfo('GATT cache cleared for device: $deviceId', 'BleService.clearGattCache');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.clearGattCache');
      throw Exception('Failed to clear GATT cache: $e');
    }
  }

  /// Read from a characteristic
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) async {
    try {
      final value = await adapter.readCharacteristic(characteristic);
      AppLogger.logInfo('Read characteristic ${characteristic.characteristicId}: $value', 'BleService.readCharacteristic');
      return value;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.readCharacteristic');
      throw Exception('Failed to read characteristic: $e');
    }
  }

  /// Write to a characteristic
  Future<void> writeCharacteristic(QualifiedCharacteristic characteristic, List<int> value, {bool withResponse = true}) async {
    try {
      await adapter.writeCharacteristic(characteristic, value, withResponse: withResponse);
      AppLogger.logInfo('Wrote to characteristic ${characteristic.characteristicId}: $value', 'BleService.writeCharacteristic');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.writeCharacteristic');
      throw Exception('Failed to write characteristic: $e');
    }
  }

  /// Request required permissions for BLE operations
  Future<void> requestPermissions() async {
    try {
      final scan = await permissionService.bluetoothScanStatus;
      if (!scan.isGranted) {
        final result = await permissionService.requestBluetoothScan();
        if (!result.isGranted) throw Exception('Bluetooth scan permission denied');
      }

      final connect = await permissionService.bluetoothConnectStatus;
      if (!connect.isGranted) {
        final result = await permissionService.requestBluetoothConnect();
        if (!result.isGranted) throw Exception('Bluetooth connect permission denied');
      }

      final location = await permissionService.locationStatus;
      if (!location.isGranted) {
        final result = await permissionService.requestLocation();
        if (!result.isGranted) throw Exception('Location permission denied');
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.requestPermissions');
      throw Exception('Failed to request permissions: $e');
    }
  }
}