import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:rxdart/rxdart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:automotiq_app/services/permission_service.dart';
import 'package:automotiq_app/utils/bluetooth_adapter.dart';
import 'package:automotiq_app/utils/logger.dart';

class BleService {
  final BluetoothAdapter adapter;
  final PermissionService permissionService;

  /// Current connection state of the device
  DeviceConnectionState _currentState = DeviceConnectionState.disconnected;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final BehaviorSubject<DeviceConnectionState> _stateSubject =
      BehaviorSubject<DeviceConnectionState>.seeded(DeviceConnectionState.disconnected);

  BleService({
    BluetoothAdapter? adapter,
    PermissionService? permissionService,
  }) : adapter = adapter ?? ReactiveBleAdapter(),
       permissionService = permissionService ?? SystemPermissionService() {
    // Initialize connection state subscription
    _connectionSubscription = adapter?.connectedDeviceStream.listen(
      (update) {
        _updateConnectionState(update.connectionState);
      },
      onError: (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'BleService.connectionStateStream');
        _updateConnectionState(DeviceConnectionState.disconnected);
      },
      onDone: () {
        _updateConnectionState(DeviceConnectionState.disconnected);
      },
    );
  }

  /// Expose connection state stream for UI
  Stream<DeviceConnectionState> get connectionStateStream {
    if (_stateSubject.isClosed) {
      throw StateError('Connection state stream is closed.');
    }
    return _stateSubject.stream;
  }

  void _updateConnectionState(DeviceConnectionState newState) {
    if (_currentState == newState) return;
    AppLogger.logInfo(
      'Connection state updated: $_currentState -> $newState',
      'BleService._updateConnectionState',
    );
    _currentState = newState;
    _stateSubject.add(_currentState);
  }

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

      // Create a completer to wait for the connected state
      final completer = Completer<void>();
      _connectionSubscription = adapter
          .connectToDevice(
            id: deviceId,
            servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
            connectionTimeout: connectionTimeout ?? const Duration(seconds: 10),
          )
          .listen(
            (update) {
              _updateConnectionState(update.connectionState);
              if (update.connectionState == DeviceConnectionState.connected) {
                if (!completer.isCompleted) {
                  completer.complete();
                }
              }
            },
            onError: (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'BleService.connectToDevice');
              _updateConnectionState(DeviceConnectionState.disconnected);
              if (!completer.isCompleted) {
                completer.completeError(e, stackTrace);
              }
            },
            onDone: () {
              _updateConnectionState(DeviceConnectionState.disconnected);
              if (!completer.isCompleted) {
                completer.completeError(Exception('Connection stream closed unexpectedly'));
              }
            },
          );

      // Wait for the connected state or timeout
      await completer.future;
      AppLogger.logInfo('Successfully connected to device: $deviceId', 'BleService.connectToDevice');
    } catch (e, stackTrace) {
      _updateConnectionState(DeviceConnectionState.disconnected);
      AppLogger.logError(e, stackTrace, 'BleService.connectToDevice');
      throw Exception('Failed to connect to device: $e');
    }
  }

  /// Scan for BLE devices
  Future<List<DiscoveredDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 5),
    List<Uuid> withServices = const [],
  }) async {
    const method = 'BleService.scanForDevices';

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
      );

      await Future.delayed(timeout);
      return devices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, method);
      rethrow;
    } finally {
      await scanSubscription?.cancel();
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
  Future<void> writeCharacteristic(
    QualifiedCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  }) async {
    if (withResponse) {
      await adapter.writeCharacteristicWithResponse(characteristic, value: value);
    } else {
      await adapter.writeCharacteristicWithoutResponse(characteristic, value: value);
    }
  }

  /// Request required permissions for BLE operations
  Future<void> requestPermissions() async {
    const method = 'BleService.requestPermissions';

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
      AppLogger.logError(e, stackTrace, method);
      rethrow;
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    try {
      await disconnectDevice();
      await _stateSubject.close();
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      AppLogger.logInfo('BleService disposed', 'BleService.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleService.dispose');
      throw Exception('Failed to dispose BleService: $e');
    }
  }
}