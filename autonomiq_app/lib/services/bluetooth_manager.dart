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

  // OBD intialization state
  bool _obdInitialized = false;

  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService();

  /// Get the current connection state of the device
  DeviceConnectionState getDeviceState() => _bleService.getDeviceState();

  /// Expose connection state stream for UI
  Stream<DeviceConnectionState> get connectionStateStream => _bleService.connectionStateStream;

  /// Check if the device is ready for OBD operations
  bool get _deviceReady => _deviceId != null && getDeviceState() == DeviceConnectionState.connected && _obdInitialized;

  /// Scan for new BLE devices by name (e.g., VEEPEAK, AUTONOMIQ)
  Future<List<DiscoveredDevice>> scanForNewDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    const method = 'BluetoothManager.scanForNewDevices';

    try {
      final devices = await _bleService.scanForDevices(timeout: timeout);

      final obdDevices = devices.where((device) {
        final name = device.name.toLowerCase();
        return name.contains('veepeak') || name.contains('autonomiq');
      }).toList();

      AppLogger.logInfo(
        'Found ${obdDevices.length} OBD devices: ${obdDevices.map((d) => d.name).toList()}',
        method,
      );

      return obdDevices;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, method);
      rethrow;
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
      await _initializeObdConnection();

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
        // await initializeObdConnection();
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

  ///  ------- OBD METHODS -------

  /// Initialize OBD connection
  Future<void> _initializeObdConnection() async {
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
          await Future.delayed(const Duration(milliseconds: 250)); // Wait for subscription to stabilize
          break; // Success, exit retry loop
        } catch (e){
          AppLogger.logWarning('Attempt $attempt/$maxSubRetries to subscribe to notifications failed: $e', 'BluetoothManager.initializeObdConnection');
          if (attempt == maxSubRetries) {
            throw Exception('Failed to subscribe to notifications after $maxSubRetries attempts: $e');
          }
          await Future.delayed(const Duration(milliseconds: 250));
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
        // 'ATDPN\r', // Describe protocol number TODO: add back
        'ATRV\r', // Read battery voltage
        // '0100\r', // Supported PIDs 00-1F TODO: add back
      ];

      const maxRetries = 3;
      const commandDelay = Duration(milliseconds: 100);
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

             // OBD initialization successful
            _obdInitialized = true;
            break;
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
    } catch (e) {
      _obdInitialized = false;
      await _cleanup();
      throw Exception('Failed to initialize OBD2 connection: $e');
    }
  }

  /// Send an OBD command and wait for the response
  Future<String> _sendObdCommand(String command, {required Duration timeout}) async {
    if (_obdCharacteristic == null || _notifyCharacteristic == null) {
      throw StateError('OBD characteristics not initialized');
    }

    _notificationCompleter = Completer<String>();
    _notificationBuffer.clear();

    AppLogger.logInfo('Sending command: $command', 'BluetoothManager._sendObdCommand');

    await _bleService.writeCharacteristic(
      _obdCharacteristic!,
      Uint8List.fromList(command.codeUnits),
    );

    final response = await _notificationCompleter!.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('No response for $command after ${timeout.inSeconds}s'),
    );

    if (response.isEmpty || response == '?' || response == 'NO DATA') {
      throw FormatException('Invalid response: $response');
    }

    return response;
  }

  ///  ------- VEHICLE DATA RETRIEVAL METHODS -------

  /// Get vehicle Diagnostic Trouble Codes (DTCs)
  Future<List<String>> getVehicleDTCs({bool coolOff = true}) async {
    const command = '03\r';
    const commandDelay = Duration(milliseconds: 250);
    const method = 'BluetoothManager.getVehicleDTCs';
  
    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady) throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(command, timeout: const Duration(seconds: 15));
      AppLogger.logInfo('DTC response: $response', 'BluetoothManager.getVehicleDTCs');

      // Handle NO DATA case (no DTCs or no vehicle connection)
      if (response == 'NO DATA' || response == '?') {
        AppLogger.logInfo('No DTCs found or no vehicle connected', 'BluetoothManager.getVehicleDTCs');
        return [];
      }

      // Expect response like "43 XX YY ..." where XX YY are DTC hex pairs
      if (!response.startsWith('43')) {
        throw FormatException('Invalid DTC response: $response');
      }

      // Extract hex data after "43" and remove whitespace
      final hexData = response.substring(2).replaceAll(RegExp(r'\s+'), '');
      if (hexData.length % 4 != 0 || hexData.isEmpty) {
        throw FormatException('Invalid DTC hex format: $hexData');
      }

      // Decode DTCs (each DTC is 4 hex digits)
      final dtcs = <String>[];
      for (var i = 0; i < hexData.length; i += 4) {
        final dtcHex = hexData.substring(i, i + 4);
        if (!RegExp(r'^[0-9A-F]{4}$').hasMatch(dtcHex)) {
          throw FormatException('Invalid DTC hex: $dtcHex');
        }

        // Decode first two bits of first byte for DTC type
        final firstByte = int.parse(dtcHex.substring(0, 2), radix: 16);
        final dtcType = switch (firstByte >> 6) {
          0 => 'P', // Powertrain
          1 => 'C', // Chassis
          2 => 'B', // Body
          3 => 'U', // Network
          _ => 'Unknown',
        };
        if (dtcType == 'Unknown') {
          throw FormatException('Invalid DTC type: $dtcHex');
        }

        // Extract remaining digits
        final code = dtcHex.substring(0, 2).substring(2 - (firstByte >> 6)) + dtcHex.substring(2);
        final dtc = '$dtcType${int.parse(code, radix: 16).toString().padLeft(4, '0')}';
        dtcs.add(dtc);
      }

      AppLogger.logInfo('Retrieved DTCs: $dtcs', 'BluetoothManager.getVehicleDTCs');
      return dtcs;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, method);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the system battery voltage 
  Future<double> getSystemBatteryVoltage({bool coolOff = true}) async {
    const command = 'ATRV\r';
    const commandDelay = Duration(milliseconds: 250);
    const nominalMin = 12.0;
    const nominalMax = 15.0;
    const method = 'BluetoothManager.getSystemBatteryVoltage';

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady) throw StateError('Device not ready for OBD operations');
      
      final response = await _sendObdCommand(command, timeout: const Duration(seconds: 15));
      final match = RegExp(r'^(\d+\.\d)V$').firstMatch(response);

      if (match == null) throw FormatException('Unexpected format: $response');

      final voltage = double.parse(match.group(1)!);

      if (voltage < nominalMin || voltage > nominalMax) {
        AppLogger.logWarning('Voltage $voltage V out of range ($nominalMin–$nominalMax V)', method);
      } else {
        AppLogger.logInfo('Battery voltage: $voltage V', method);
      }

      return voltage;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, method);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the Vehicle Identification Number (VIN)
  Future<String> getVin({bool coolOff = true}) async {
    const command = '0902\r';
    const commandDelay = Duration(milliseconds: 250);
    const method = 'BluetoothManager.getVin';

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady) throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(command, timeout: const Duration(seconds: 15));

      if (!response.startsWith('4902')) {
        throw FormatException('Unexpected response format: $response');
      }

      final hexVin = response.substring(4).replaceAll(RegExp(r'\s+'), '');

      if (hexVin.length < 34) { // 17 characters * 2 (hex)
        throw FormatException('VIN too short: $hexVin');
      }

      final vin = String.fromCharCodes(
        List.generate(
          hexVin.length ~/ 2,
          (i) => int.parse(hexVin.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );

      AppLogger.logInfo('VIN: $vin', method);
      return vin;
    } catch (e, stack) {
      AppLogger.logError(e, stack, method);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the actual battery voltage
  Future<double> getActualBatteryVoltage({bool coolOff = true}) async {
    const command = '010B\r';
    const commandDelay = Duration(milliseconds: 250);
    const method = 'BluetoothManager.getActualBatteryVoltage';

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady) throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(command, timeout: const Duration(seconds: 15));

      if (!response.startsWith('410B')) {
        throw FormatException('Unexpected response format: $response');
      }

      final hexVoltage = response.substring(4).trim();

      if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(hexVoltage)) {
        throw FormatException('Invalid hex format: $hexVoltage');
      }

      final voltage = int.parse(hexVoltage, radix: 16).toDouble();

      AppLogger.logInfo('Actual battery voltage: $voltage V', method);
      return voltage;
    } catch (e, stack) {
      AppLogger.logError(e, stack, method);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }
}