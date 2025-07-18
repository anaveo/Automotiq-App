import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  /// Scan for Bluetooth devices
  Future<List<BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // Request permissions
      await requestPermissions();

      final List<BluetoothDevice> devices = [];
      StreamSubscription? scanSubscription;

      try {
        // Clear any existing scan
        await adapter.stopScan();

        // Listen for scan results
        scanSubscription = adapter.scanResults.listen((results) {
          for (ScanResult result in results) {
            if (!devices.contains(result.device)) {
              devices.add(result.device);
            }
          }
        });

        // Start scan
        await adapter.startScan(timeout: timeout);

        // Wait for scan to complete
        await Future.delayed(timeout);
      } finally {
        // Ensure scan is stopped and subscription is cancelled
        await adapter.stopScan();
        await scanSubscription?.cancel();
      }

      return devices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.scanForDevices');
      throw Exception('Failed to scan for devices: $e');
    }
  }

  /// Reconnect to a device by MAC address
  Future<BluetoothDevice> reconnectToDevice(String deviceId) async {
    try {
      await requestPermissions();
      final devices = await scanForDevices(timeout: const Duration(seconds: 5));
      final targetDevice = devices.firstWhere(
        (device) => device.remoteId.str == deviceId,
        orElse: () => throw Exception('Device with ID $deviceId not found'),
      );
      await connect(targetDevice);
      return targetDevice;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.reconnectToDevice');
      throw Exception('Failed to reconnect to device: $e');
    }
  }

  /// Connect to a BLE device
  Future<void> connect(BluetoothDevice device) async {
    try {
      final state = await device.connectionState.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Connection state timeout'),
      );

      if (state != BluetoothConnectionState.connected) {
        await device.connect(timeout: const Duration(seconds: 10));
      }
    } on TimeoutException {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.connect');
      throw Exception('Failed to connect to device: $e');
    }
  }

  /// Disconnect from a BLE device
  Future<void> disconnect(BluetoothDevice device) async {
    try {
      final state = await device.connectionState.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Connection state timeout'),
      );

      if (state == BluetoothConnectionState.connected) {
        await device.disconnect();
      }
    } on TimeoutException {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.disconnect');
      throw Exception('Failed to disconnect from device: $e');
    }
  }

  /// Get current connection state of a device
  Future<BluetoothConnectionState> getDeviceState(BluetoothDevice device) async {
    try {
      return await device.connectionState
          .first.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.getDeviceState');
      throw Exception('Failed to get device state: $e');
    }
  }

  /// Stream connection state of a device
  Stream<BluetoothConnectionState> getDeviceStateStream(BluetoothDevice device) {
    try {
      return device.connectionState;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.getDeviceStateStream');
      throw Exception('Failed to stream device state: $e');
    }
  }

  /// List all currently connected BLE devices
  Future<List<BluetoothDevice>> getConnectedDevices() async {
    try {
      return await adapter.connectedDevices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.getConnectedDevices');
      throw Exception('Failed to get connected devices: $e');
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