import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService bleService;
  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _subscription;
  final StreamController<BluetoothConnectionState> _stateController =
      StreamController<BluetoothConnectionState>.broadcast();

  BluetoothManager({required this.bleService});

  /// Scan for ELM327 or OBD devices
  Future<List<BluetoothDevice>> scanForElmDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = await bleService.scanForDevices(timeout: timeout);
      return devices.where((device) {
        final name = device.platformName.toLowerCase();
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
      if (_device != null && _device!.id.id == deviceId) return;

      await disconnectDevice();
      _device = await bleService.reconnectToDevice(deviceId);

      _subscription?.cancel();
      _subscription = _device!.connectionState.listen(
        (state) {
          _stateController.add(state);
          if (state == BluetoothConnectionState.disconnected) {
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
  Stream<BluetoothConnectionState> getConnectionStateStream() {
    if (_device == null) {
      throw Exception('No device initialized');
    }
    return _stateController.stream;
  }

  /// Get current device
  BluetoothDevice? getCurrentDevice() => _device;

  /// Auto-reconnect with exponential backoff
  Future<void> _startAutoReconnect(String deviceId) async {
    int retryCount = 0;
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 5);

    while (retryCount < maxRetries) {
      try {
        _device = await bleService.reconnectToDevice(deviceId);
        _stateController.add(BluetoothConnectionState.connected);
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
        await bleService.disconnect(_device!);
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