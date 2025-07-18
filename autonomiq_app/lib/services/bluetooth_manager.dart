import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService bleService;
  DiscoveredDevice? _device;
  StreamSubscription<DeviceConnectionState>? _subscription;
  final StreamController<DeviceConnectionState> _stateController =
      StreamController<DeviceConnectionState>.broadcast();

  BluetoothManager({required this.bleService});

  /// Scan for ELM327 or OBD devices
  Future<List<DiscoveredDevice>> scanForElmDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = await bleService.scanForDevices(timeout: timeout);
      return devices.where((device) {
        final name = device.name.toLowerCase();
        return name.contains('veepeak') || name.contains('autonomiq');
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.scanForElmDevices');
      throw Exception('Failed to scan for ELM devices: $e');
    }
  }

  /// Initialize connection for a device by ID
  Future<void> initializeDevice(String deviceId) async {
    try {
      if (_device != null && _device!.id == deviceId) return;

      await disconnectDevice();
      await bleService.connectToDevice(deviceId);
      _device = (await bleService.scanForDevices(timeout: const Duration(seconds: 1)))
          .firstWhere((d) => d.id == deviceId, orElse: () => throw Exception('Device not found'));

      _subscription?.cancel();
      _subscription = bleService.getDeviceStateStream(deviceId).listen(
        (state) {
          _stateController.add(state);
          if (state == DeviceConnectionState.disconnected) {
            _startAutoReconnect(deviceId);
          }
        },
        onError: (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'BluetoothManager.connectionState');
          _stateController.addError(e, stackTrace);
        },
      );
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.initializeDevice');
      _stateController.addError(e, stackTrace);
      rethrow;
    }
  }

  /// Get connection state stream
  Stream<DeviceConnectionState> getConnectionStateStream() {
    if (_device == null) {
      throw Exception('No device initialized');
    }
    return _stateController.stream;
  }

  /// Get current device
  DiscoveredDevice? getCurrentDevice() => _device;

  /// Auto-reconnect with exponential backoff
  Future<void> _startAutoReconnect(String deviceId) async {
    int retryCount = 0;
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 5);

    while (retryCount < maxRetries) {
      try {
        await bleService.connectToDevice(deviceId);
        _device = (await bleService.scanForDevices(timeout: const Duration(seconds: 1)))
            .firstWhere((d) => d.id == deviceId, orElse: () => throw Exception('Device not found'));
        _stateController.add(DeviceConnectionState.connected);
        return;
      } catch (e, stackTrace) {
        retryCount++;
        AppLogger.logError(e, stackTrace, 'BluetoothManager.autoReconnect');
        if (retryCount < maxRetries) {
          await Future.delayed(baseDelay * (1 << retryCount));
        }
      }
    }
    _stateController.addError(Exception('Failed to reconnect after $maxRetries attempts'));
  }

  /// Disconnect and clean up
  Future<void> disconnectDevice() async {
    try {
      if (_device != null) {
        await bleService.disconnectDevice(_device!.id);
        await _subscription?.cancel();
        _device = null;
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      _stateController.addError(e, stackTrace);
      rethrow;
    }
  }

  /// Clean up
  Future<void> dispose() async {
    await disconnectDevice();
    await _stateController.close();
  }
}