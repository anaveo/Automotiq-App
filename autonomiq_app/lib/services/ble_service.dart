import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autonomiq_app/services/permission_service.dart';
import 'package:autonomiq_app/utils/bluetooth_adapter.dart';
import 'package:autonomiq_app/utils/logger.dart';

class BleService {
  final BluetoothAdapter adapter;
  final PermissionService permissionService;

  /// Current connection state of the device
  DeviceConnectionState _currentState = DeviceConnectionState.disconnected;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final StreamController<DeviceConnectionState> _stateController =
      StreamController<DeviceConnectionState>.broadcast();

  BleService({
    BluetoothAdapter? adapter,
    PermissionService? permissionService,
  })  : adapter = adapter ?? ReactiveBleAdapter(),
        permissionService = permissionService ?? SystemPermissionService() {
    // Emit initial disconnected state
    _stateController.add(DeviceConnectionState.disconnected);
  }

  /// Expose connection state stream for UI
  Stream<DeviceConnectionState> get connectionStateStream {
    if (_stateController.isClosed) {
      throw StateError('Connection state stream is closed.');
    }
    return _stateController.stream;
  }

  void _updateConnectionState(DeviceConnectionState newState) {
    if (_currentState == newState) return;
    AppLogger.logInfo(
      'Connection state updated: $_currentState -> $newState',
      'BleService._updateConnectionState',
    );
    _currentState = newState;
    _stateController.add(_currentState);
  }

  /// Scan for BLE devices
  Future<List<DiscoveredDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 5),
    List<Uuid> withServices = const [],
  }) async {
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
      return devices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.scanForDevices');
      throw Exception('Failed to scan for devices: $e');
    } finally {
      await scanSubscription?.cancel();
    }
  }

  // TODO: Add proper timeout exception handling
  /// Connect to a BLE device
  Future<void> connectToDevice(
    String deviceId, {
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) async {
    try {
      await requestPermissions();
      _updateConnectionState(DeviceConnectionState.connecting);
      await _connectionSubscription?.cancel();
      _connectionSubscription = adapter
          .connectToDevice(
            id: deviceId,
            servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
            connectionTimeout: connectionTimeout,
          )
          .listen(
            (update) => _updateConnectionState(update.connectionState),
            onError: (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'BleService.connectToDevice');
              _updateConnectionState(DeviceConnectionState.disconnected);
            },
            onDone: () {
              _updateConnectionState(DeviceConnectionState.disconnected);
            },
          );
    } catch (e, stackTrace) {
      _updateConnectionState(DeviceConnectionState.disconnected);
      AppLogger.logError(e, stackTrace, 'BleService.connectToDevice');
      rethrow;
    }
  }

  /// Disconnect from a BLE device
  Future<void> disconnectDevice() async {
    try {
      _updateConnectionState(DeviceConnectionState.disconnecting);
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      _updateConnectionState(DeviceConnectionState.disconnected);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.disconnectDevice');
      _updateConnectionState(DeviceConnectionState.disconnected);
      throw Exception('Failed to disconnect device: $e');
    }
  }

  /// Get current connection state of a device
  DeviceConnectionState getDeviceState() {
    return _currentState;
  }

  /// Request MTU for a device
  Future<int> requestMtu({
    required int mtu,
    required String deviceId,
  }) async {
    try {
      final negotiatedMtu = await adapter.requestMtu(deviceId: deviceId, mtu: mtu);
      return negotiatedMtu;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.requestMtu');
      throw Exception('Failed to request MTU: $e');
    }
  }

  /// Clear GATT cache for a device
  Future<void> clearGattCache(String deviceId) async {
    try {
      await adapter.clearGattCache(deviceId);
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
      if (withResponse) {
        await adapter.writeCharacteristicWithResponse(characteristic, value: value);
      } else {
        await adapter.writeCharacteristicWithoutResponse(characteristic, value: value);
      }
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
      rethrow;
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      await disconnectDevice();
      await _stateController.close();
      AppLogger.logInfo('BleService disposed', 'BleService.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.dispose');
      throw Exception('Failed to dispose BleService: $e');
    }
  }
}