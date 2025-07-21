import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../services/ble_service.dart';
import '../utils/logger.dart';

class BluetoothManager {
  final BleService _bleService;
  String? _deviceId;
  QualifiedCharacteristic? _obdCharacteristic;
  QualifiedCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<int>>? _notificationSub;
  final List<int> _notificationBuffer = [];
  Completer<String>? _notificationCompleter;
  StreamSubscription<DeviceConnectionState>? _connectionStateSubscription;

  // OBD2 service and characteristic UUIDs for Veepeak OBDCheck BLE+
  static final _obdServiceUuid = Uuid.parse('0000fff0-0000-1000-8000-00805f9b34fb');
  static final _writeCharacteristicUuid = Uuid.parse('0000fff2-0000-1000-8000-00805f9b34fb');
  static final _notifyCharacteristicUuid = Uuid.parse('0000fff1-0000-1000-8000-00805f9b34fb');

  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService();

  Future<void> initializeObdConnection() async {
    if (_deviceId == null) {
      throw Exception('No device connected. Call connectToDevice first.');
    }

    try {
      AppLogger.logInfo('Initializing OBD2 connection for device: $_deviceId', 'BluetoothManager.initializeObdConnection');

      // Discover OBD service and characteristics
      await _bleService.adapter.discoverAllServices(deviceId: _deviceId!);
      final services = await _bleService.adapter.getDiscoveredServices(deviceId: _deviceId!);
      final _ = services.firstWhere(
        (s) => s.id == _obdServiceUuid,
        orElse: () => throw Exception('OBD service not found'),
      );

      _obdCharacteristic = QualifiedCharacteristic(
        serviceId: _obdServiceUuid,
        characteristicId: _writeCharacteristicUuid,
        deviceId: _deviceId!,
      );
      _notifyCharacteristic = QualifiedCharacteristic(
        serviceId: _obdServiceUuid,
        characteristicId: _notifyCharacteristicUuid,
        deviceId: _deviceId!,
      );

      // Subscribe to notifications with retry
      const maxSubRetries = 3;
      for (var attempt = 1; attempt <= maxSubRetries; attempt++) {
        try {
          _notificationSub?.cancel();
          _notificationBuffer.clear();
          _notificationCompleter = Completer<String>();
          _notificationSub = _bleService.adapter.subscribeToCharacteristic(_notifyCharacteristic!).listen(
            (data) {
              _notificationBuffer.addAll(data);
              final response = String.fromCharCodes(_notificationBuffer);
              AppLogger.logInfo('Raw notification data: $data ($response)', 'BluetoothManager.initializeObdConnection');
              // Complete only if response contains '>' and is not just the command echo
              final trimmedResponse = response.trim();
              final commandEcho = trimmedResponse.startsWith('AT') && !trimmedResponse.contains('ELM327') && !trimmedResponse.contains('OK');
              if (!_notificationCompleter!.isCompleted && trimmedResponse.contains('>') && !commandEcho) {
                // Clean response: remove command echo, extra \r, and >
                final cleanResponse = trimmedResponse
                    .replaceAll(RegExp(r'^AT[A-Z0-9]+\r*'), '') // Remove command echo
                    .replaceAll(RegExp(r'\r+'), '') // Remove extra \r
                    .replaceAll('>', '') // Remove prompt
                    .trim();
                AppLogger.logInfo('Completing with response: $cleanResponse', 'BluetoothManager.initializeObdConnection');
                _notificationCompleter!.complete(cleanResponse);
                _notificationBuffer.clear();
              }
            },
            onError: (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'BluetoothManager.notification');
              if (!_notificationCompleter!.isCompleted) {
                AppLogger.logInfo('Completing with error: $e', 'BluetoothManager.initializeObdConnection');
                _notificationCompleter!.completeError(e, stackTrace);
              }
              _notificationBuffer.clear();
            },
          );
          await Future.delayed(const Duration(milliseconds: 1000)); // Wait for subscription to stabilize
          break; // Success, exit retry loop
        } catch (e){
          AppLogger.logWarning('Attempt $attempt/$maxSubRetries to subscribe to notifications failed: $e', 'BluetoothManager.initializeObdConnection');
          if (attempt == maxSubRetries) {
            throw Exception('Failed to subscribe to notifications after $maxSubRetries attempts: $e');
          }
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }

      // ELM327 initialization sequence
      const commands = [
        'ATZ\r', // Reset all
        'ATI\r', // Identify ELM327
        'ATE0\r', // Echo off
        'ATL0\r', // Linefeeds off
        'ATS0\r', // Spaces off
        'ATH1\r', // Headers on
        'ATSP0\r', // Auto protocol
        // 'ATDPN\r', // Describe protocol number
        'ATRV\r', // Read battery voltage
        '0100\r', // Supported PIDs 00-1F
      ];

      const maxRetries = 3;
      const commandDelay = Duration(milliseconds: 1000);
      const nominalVoltageRange = {'min': 12.0, 'max': 15.0};

      for (final command in commands) {
        String? response;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            response = await _sendObdCommand(command, timeout: const Duration(seconds: 15));
            AppLogger.logInfo('Command $command response: $response', 'BluetoothManager.initializeObdConnection');

            // Validate response
            if (command == 'ATZ\r' || command == 'ATI\r') {
              if (!response.contains('ELM327')) {
                AppLogger.logWarning('Validation failed for $command: Expected ELM327, got $response', 'BluetoothManager.initializeObdConnection');
                throw Exception('Invalid response for $command: $response');
              }
            } else if (command == 'ATE0\r' || command == 'ATL0\r' || command == 'ATS0\r' || command == 'ATH1\r' || command == 'ATSP0\r') {
              if (response != 'OK') {
                AppLogger.logWarning('Validation failed for $command: Expected OK, got $response', 'BluetoothManager.initializeObdConnection');
                throw Exception('Invalid response for $command: $response');
              }
            } else if (command == 'ATDPN\r') {
              if (!RegExp(r'^\d+$').hasMatch(response)) {
                AppLogger.logWarning('Validation failed for $command: Expected numeric protocol, got $response', 'BluetoothManager.initializeObdConnection');
                throw Exception('Invalid protocol number for $command: $response');
              }
            } else if (command == 'ATRV\r') {
              final voltageMatch = RegExp(r'^(\d+\.\d)V$').firstMatch(response);
              if (voltageMatch == null) {
                AppLogger.logWarning('Invalid voltage response for $command: $response', 'BluetoothManager.initializeObdConnection');
                throw Exception('Invalid voltage response: $response');
              }
              final voltage = double.parse(voltageMatch.group(1)!);
              if (voltage < nominalVoltageRange['min']! || voltage > nominalVoltageRange['max']!) {
                AppLogger.logWarning(
                  'Battery voltage $voltage V is outside nominal range (${nominalVoltageRange['min']}–${nominalVoltageRange['max']} V)',
                  'BluetoothManager.initializeObdConnection',
                );
              } else {
                AppLogger.logInfo('Battery voltage: $voltage V (nominal)', 'BluetoothManager.initializeObdConnection');
              }
            } else if (command == '0100\r') {
              if (!response.startsWith('4100')) {
                AppLogger.logWarning('Validation failed for $command: Expected 4100..., got $response', 'BluetoothManager.initializeObdConnection');
                throw Exception('Invalid PID response for $command: $response');
              }
            }
            break; // Success, exit retry loop
          } catch (e) {
            AppLogger.logWarning('Attempt $attempt/$maxRetries for $command failed: $e', 'BluetoothManager.initializeObdConnection');
            if (attempt == maxRetries) {
              throw Exception('Failed to execute $command after $maxRetries attempts: $e');
            }
            await Future.delayed(commandDelay);
          }
        }
        await Future.delayed(commandDelay);
      }

      AppLogger.logInfo('OBD2 connection initialized successfully for device: $_deviceId', 'BluetoothManager.initializeObdConnection');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.initializeObdConnection');
      await _cleanup();
      throw Exception('Failed to initialize OBD2 connection: $e');
    }
  }

  Future<String> _sendObdCommand(String command, {required Duration timeout}) async {
    if (_obdCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception('OBD characteristics not initialized');
    }

    // Initialize a new completer for each command
    _notificationCompleter = Completer<String>();
    _notificationBuffer.clear();

    try {
      AppLogger.logInfo('Sending command: $command', 'BluetoothManager._sendObdCommand');
      await _bleService.writeCharacteristic(_obdCharacteristic!, Uint8List.fromList(command.codeUnits));
      final response = await _notificationCompleter!.future.timeout(timeout, onTimeout: () {
        throw TimeoutException('No response for $command after ${timeout.inSeconds}s');
      });
      if (response.isEmpty || response == '?' || response == 'NO DATA') {
        throw Exception('Invalid response for $command: $response');
      }
      return response;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager._sendObdCommand');
      if (!_notificationCompleter!.isCompleted) {
        _notificationCompleter!.completeError(e, stackTrace);
      }
      throw Exception('Failed to send command $command: $e');
    }
  }

  /// Get the current connection state of the device
  DeviceConnectionState getDeviceState() => _bleService.getDeviceState();

  /// Expose connection state stream for UI
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

  /// Retrieve BLE-related data (services, characteristics, UUIDs) for the connected device
  Future<Map<String, dynamic>> getBleDeviceInfo() async {
    if (_deviceId == null) {
      throw Exception('No device connected');
    }

    try {
      await _bleService.adapter.discoverAllServices(deviceId: _deviceId!);
      final services = await _bleService.adapter.getDiscoveredServices(deviceId: _deviceId!);
      final serviceData = services.map((service) {
        return {
          'serviceUuid': service.id.toString(),
          'characteristics': service.characteristics.map((c) => {
                'uuid': c.id.toString(),
                'isReadable': c.isReadable,
                'isWritableWithResponse': c.isWritableWithResponse,
                'isWritableWithoutResponse': c.isWritableWithoutResponse,
                'isNotifiable': c.isNotifiable,
              }).toList(),
        };
      }).toList();

      final bleInfo = {
        'deviceId': _deviceId,
        'services': serviceData,
        'mtu': await _bleService.requestMtu(deviceId: _deviceId!, mtu: 512).catchError((e) => -1),
      };

      AppLogger.logInfo('BLE Device ID: ${_deviceId}', 'BluetoothManager.getBleDeviceInfo');
      for (var i = 0; i < serviceData.length; i++) {
        AppLogger.logInfo('Service ${i + 1}: ${serviceData[i]}', 'BluetoothManager.getBleDeviceInfo');
      }
      AppLogger.logInfo('MTU: ${bleInfo['mtu']}', 'BluetoothManager.getBleDeviceInfo');

      return bleInfo;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.getBleDeviceInfo');
      throw Exception('Failed to retrieve BLE device info: $e');
    }
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
  
  Future<void> connectToDevice(String deviceId, {bool autoReconnect = false}) async {
    try {
      if (_deviceId == deviceId && _bleService.getDeviceState() == DeviceConnectionState.connected) {
        AppLogger.logInfo('Already connected to device: $deviceId', 'BluetoothManager.connectToDevice');
        return;
      }

      // Clean up any existing connection
      await _cleanup();

      _deviceId = deviceId;
      await _bleService.connectToDevice(deviceId, connectionTimeout: const Duration(seconds: 10));
      AppLogger.logInfo('Connected to device: $deviceId', 'BluetoothManager.connectToDevice');

      // Initialize OBD connection after successful BLE connection
      await initializeObdConnection();

      if (autoReconnect) {
        _connectionStateSubscription?.cancel();
        _connectionStateSubscription = _bleService.connectionStateStream.listen(
          (state) async {
            if (state == DeviceConnectionState.disconnected && _deviceId != null) {
              AppLogger.logInfo('Device disconnected, attempting reconnect to $_deviceId', 'BluetoothManager.connectToDevice');
              await _attemptReconnect(deviceId);
            }
          },
          onError: (e, stackTrace) async {
            AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
            await _cleanup();
          },
        );
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
      await _cleanup();
      throw Exception('Failed to connect to device: $e');
    }
  }

  Future<void> _attemptReconnect(String deviceId) async {
    const maxAttempts = 5;
    var attempt = 0;
    var delay = const Duration(seconds: 1);

    while (attempt < maxAttempts && _deviceId != null) {
      try {
        AppLogger.logInfo('Reconnect attempt ${attempt + 1}/$maxAttempts to $deviceId', 'BluetoothManager._attemptReconnect');
        await _bleService.connectToDevice(deviceId, connectionTimeout: const Duration(seconds: 10));
        AppLogger.logInfo('Reconnected to device: $deviceId', 'BluetoothManager._attemptReconnect');

        // Reinitialize OBD connection after successful reconnect
        await initializeObdConnection();
        return;
      } catch (e) {
        attempt++;
        AppLogger.logWarning('Reconnect attempt $attempt/$maxAttempts failed: $e', 'BluetoothManager._attemptReconnect');
        if (attempt < maxAttempts) {
          await Future.delayed(delay);
          delay = Duration(seconds: delay.inSeconds * 2); // Exponential backoff
        }
      }
    }

    if (attempt >= maxAttempts) {
      AppLogger.logError('Failed to reconnect to $deviceId after $maxAttempts attempts', null, 'BluetoothManager._attemptReconnect');
      await _cleanup();
    }
  }

  Future<void> _cleanup() async {
    _deviceId = null;
    _obdCharacteristic = null;
    _notifyCharacteristic = null;
    _notificationSub?.cancel();
    _notificationSub = null;
    _notificationBuffer.clear();
    if (_notificationCompleter != null && !_notificationCompleter!.isCompleted) {
      _notificationCompleter!.completeError(Exception('Connection cleanup'));
    }
    _notificationCompleter = null;
  }

  Future<void> disconnectDevice() async {
    try {
      await _bleService.disconnectDevice();
      await _cleanup();
      AppLogger.logInfo('Disconnected device', 'BluetoothManager.disconnectDevice');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      await _cleanup();
      throw Exception('Failed to disconnect device: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await disconnectDevice();
      _connectionStateSubscription?.cancel();
      AppLogger.logInfo('BluetoothManager disposed', 'BluetoothManager.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.dispose');
      throw Exception('Failed to dispose BluetoothManager: $e');
    }
  }
}