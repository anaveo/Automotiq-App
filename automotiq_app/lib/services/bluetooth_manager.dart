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
  static final _obdServiceUuid = Uuid.parse(
    '0000fff0-0000-1000-8000-00805f9b34fb',
  );
  static final _writeCharacteristicUuid = Uuid.parse(
    '0000fff2-0000-1000-8000-00805f9b34fb',
  );
  static final _notifyCharacteristicUuid = Uuid.parse(
    '0000fff1-0000-1000-8000-00805f9b34fb',
  );

  // OBD intialization state
  bool _obdInitialized = false;

  BluetoothManager({BleService? bleService})
    : _bleService = bleService ?? BleService();

  /// Get the current connection state of the device
  DeviceConnectionState getDeviceState() => _bleService.getDeviceState();

  /// Expose connection state stream for UI
  Stream<DeviceConnectionState> get connectionStateStream =>
      _bleService.connectionStateStream;

  /// Check if the device is ready for OBD operations
  bool get _deviceReady =>
      _deviceId != null &&
      getDeviceState() == DeviceConnectionState.connected &&
      _obdInitialized;

  /// Scan for new BLE devices by name (e.g., VEEPEAK, AUTOMOTIQ)
  Future<List<DiscoveredDevice>> scanForNewDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = await _bleService.scanForDevices(timeout: timeout);

      final obdDevices = devices.where((device) {
        final name = device.name.toLowerCase();
        return name.contains('veepeak') || name.contains('automotiq');
      }).toList();

      AppLogger.logInfo(
        'Found ${obdDevices.length} OBD devices: ${obdDevices.map((d) => d.name).toList()}',
      );

      return obdDevices;
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    }
  }

  Future<void> connectToDevice(
    String deviceId, {
    bool autoReconnect = false,
  }) async {
    try {
      if (_deviceId == deviceId &&
          _bleService.getDeviceState() == DeviceConnectionState.connected) {
        AppLogger.logInfo('Already connected to device: $deviceId');
        return;
      }

      // Clean up any existing connection
      await _cleanup();

      _deviceId = deviceId;
      await _bleService.connectToDevice(
        deviceId,
        connectionTimeout: const Duration(seconds: 10),
      );
      AppLogger.logInfo('Connected to device: $deviceId');

      // Initialize OBD connection after successful BLE connection
      await _initializeObdConnection();

      if (autoReconnect) {
        _connectionStateSubscription?.cancel();
        _connectionStateSubscription = _bleService.connectionStateStream.listen(
          (state) async {
            if (state == DeviceConnectionState.disconnected &&
                _deviceId != null) {
              AppLogger.logInfo(
                'Device disconnected, attempting reconnect to $_deviceId',
              );
              await _attemptReconnect(deviceId);
            }
          },
          onError: (e) async {
            AppLogger.logError(e);
            await _cleanup();
          },
        );
      }
    } catch (e) {
      AppLogger.logError(e);
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
        AppLogger.logInfo(
          'Reconnect attempt ${attempt + 1}/$maxAttempts to $deviceId',
        );
        await _bleService.connectToDevice(
          deviceId,
          connectionTimeout: const Duration(seconds: 10),
        );
        AppLogger.logInfo('Reconnected to device: $deviceId');

        // Reinitialize OBD connection after successful reconnect
        // await initializeObdConnection();
        return;
      } catch (e) {
        attempt++;
        AppLogger.logWarning(
          'Reconnect attempt $attempt/$maxAttempts failed: $e',
        );
        if (attempt < maxAttempts) {
          await Future.delayed(delay);
          delay = Duration(seconds: delay.inSeconds * 2); // Exponential backoff
        }
      }
    }

    if (attempt >= maxAttempts) {
      AppLogger.logError(
        'Failed to reconnect to $deviceId after $maxAttempts attempts',
      );
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
    if (_notificationCompleter != null &&
        !_notificationCompleter!.isCompleted) {
      _notificationCompleter!.completeError(Exception('Connection cleanup'));
    }
    _notificationCompleter = null;
  }

  Future<void> disconnectDevice() async {
    try {
      await _bleService.disconnectDevice();
      await _cleanup();
      AppLogger.logInfo('Disconnected device');
    } catch (e) {
      AppLogger.logError(e);
      await _cleanup();
      throw Exception('Failed to disconnect device: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await disconnectDevice();
      _connectionStateSubscription?.cancel();
      AppLogger.logInfo('BluetoothManager disposed');
    } catch (e) {
      AppLogger.logError(e);
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
      AppLogger.logInfo('Initializing OBD2 connection for device: $_deviceId');

      // Discover OBD service and characteristics
      await _bleService.adapter.discoverAllServices(deviceId: _deviceId!);
      final services = await _bleService.adapter.getDiscoveredServices(
        deviceId: _deviceId!,
      );
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
          _notificationSub = _bleService.adapter
              .subscribeToCharacteristic(_notifyCharacteristic!)
              .listen(
                (data) {
                  _notificationBuffer.addAll(data);
                  final response = String.fromCharCodes(_notificationBuffer);
                  AppLogger.logInfo('Raw notification data: $data ($response)');
                  // Complete only if response contains '>' and is not just the command echo
                  final trimmedResponse = response.trim();
                  final commandEcho =
                      trimmedResponse.startsWith('AT') &&
                      !trimmedResponse.contains('ELM327') &&
                      !trimmedResponse.contains('OK');
                  if (!_notificationCompleter!.isCompleted &&
                      trimmedResponse.contains('>') &&
                      !commandEcho) {
                    // Clean response: remove command echo, extra \r, and >
                    final cleanResponse = trimmedResponse
                        .replaceAll(
                          RegExp(r'^AT[A-Z0-9]+\r*'),
                          '',
                        ) // Remove command echo
                        .replaceAll(RegExp(r'\r+'), '') // Remove extra \r
                        .replaceAll('>', '') // Remove prompt
                        .trim();
                    AppLogger.logInfo(
                      'Completing with response: $cleanResponse',
                    );
                    _notificationCompleter!.complete(cleanResponse);
                    _notificationBuffer.clear();
                  }
                },
                onError: (e) {
                  AppLogger.logError(e);
                  if (!_notificationCompleter!.isCompleted) {
                    AppLogger.logInfo('Completing with error: $e');
                    _notificationCompleter!.completeError(e);
                  }
                  _notificationBuffer.clear();
                },
              );
          await Future.delayed(
            const Duration(milliseconds: 250),
          ); // Wait for subscription to stabilize
          break; // Success, exit retry loop
        } catch (e) {
          AppLogger.logWarning(
            'Attempt $attempt/$maxSubRetries to subscribe to notifications failed: $e',
          );
          if (attempt == maxSubRetries) {
            throw Exception(
              'Failed to subscribe to notifications after $maxSubRetries attempts: $e',
            );
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
        'ATDPN\r', // Describe protocol number
        'ATRV\r', // Read battery voltage
        '0100\r', // Supported PIDs 00-1F
      ];

      const maxRetries = 3;
      const commandDelay = Duration(milliseconds: 100);
      const nominalVoltageRange = {'min': 12.0, 'max': 15.0};

      for (final command in commands) {
        String? response;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            response = await _sendObdCommand(
              command,
              timeout: const Duration(seconds: 15),
            );
            AppLogger.logInfo('Command $command response: $response');

            // Validate response
            if (command == 'ATZ\r' || command == 'ATI\r') {
              if (!response.contains('ELM327')) {
                AppLogger.logWarning(
                  'Validation failed for $command: Expected ELM327, got $response',
                );
                throw Exception('Invalid response for $command: $response');
              }
            } else if (command == 'ATE0\r' ||
                command == 'ATL0\r' ||
                command == 'ATS0\r' ||
                command == 'ATH1\r' ||
                command == 'ATSP0\r') {
              if (response != 'OK') {
                AppLogger.logWarning(
                  'Validation failed for $command: Expected OK, got $response',
                );
                throw Exception('Invalid response for $command: $response');
              }
            } else if (command == 'ATDPN\r') {
              if (!RegExp(r'^[A-Z]?\d+$').hasMatch(response)) {
                AppLogger.logWarning(
                  'Validation failed for $command: Expected numeric protocol, got $response',
                );
                throw Exception(
                  'Invalid protocol number for $command: $response',
                );
              }
            } else if (command == 'ATRV\r') {
              final voltageMatch = RegExp(r'^(\d+\.\d)V$').firstMatch(response);
              if (voltageMatch == null) {
                AppLogger.logWarning(
                  'Invalid voltage response for $command: $response',
                );
                throw Exception('Invalid voltage response: $response');
              }
              final voltage = double.parse(voltageMatch.group(1)!);
              if (voltage < nominalVoltageRange['min']! ||
                  voltage > nominalVoltageRange['max']!) {
                AppLogger.logWarning(
                  'Battery voltage $voltage V is outside nominal range (${nominalVoltageRange['min']}–${nominalVoltageRange['max']} V)',
                );
              } else {
                AppLogger.logInfo('Battery voltage: $voltage V (nominal)');
              }
            } else if (command == '0100\r') {
              final cleaned = response
                  .replaceAll(
                    RegExp(r'SEARCHING\.{0,3}', caseSensitive: false),
                    '',
                  )
                  .replaceAll('\r', '')
                  .replaceAll('\n', '')
                  .trim();

              if (!cleaned.contains('4100')) {
                AppLogger.logWarning(
                  'Validation failed for $command: Expected 4100..., got "$cleaned"',
                );
                throw Exception('Invalid PID response for $command: $cleaned');
              }
            }

            // OBD initialization successful
            _obdInitialized = true;
            break;
          } catch (e) {
            AppLogger.logWarning(
              'Attempt $attempt/$maxRetries for $command failed: $e',
            );
            if (attempt == maxRetries) {
              throw Exception(
                'Failed to execute $command after $maxRetries attempts: $e',
              );
            }
            await Future.delayed(commandDelay);
          }
        }
        await Future.delayed(commandDelay);
      }

      AppLogger.logInfo(
        'OBD2 connection initialized successfully for device: $_deviceId',
      );
    } catch (e) {
      _obdInitialized = false;
      await _cleanup();
      throw Exception('Failed to initialize OBD2 connection: $e');
    }
  }

  /// Send an OBD command and wait for the response
  Future<String> _sendObdCommand(
    String command, {
    required Duration timeout,
  }) async {
    if (_obdCharacteristic == null || _notifyCharacteristic == null) {
      throw StateError('OBD characteristics not initialized');
    }

    _notificationCompleter = Completer<String>();
    _notificationBuffer.clear();

    AppLogger.logInfo('Sending command: $command');

    await _bleService.writeCharacteristic(
      _obdCharacteristic!,
      Uint8List.fromList(command.codeUnits),
    );

    final response = await _notificationCompleter!.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'No response for $command after ${timeout.inSeconds}s',
      ),
    );

    if (response.isEmpty || response == '?' || response == 'NO DATA') {
      throw FormatException('Invalid response: $response');
    }

    return response;
  }

  ///  ------- VEHICLE DATA RETRIEVAL METHODS -------

  /// Get vehicle Diagnostic Trouble Codes (DTCs)
  Future<List<String>> getVehicleDTCs() async {
    const command = '03\r';
    try {
      AppLogger.logInfo('Requesting DTCs with command: $command');
      final response = await _sendObdCommand(
        command,
        timeout: const Duration(seconds: 15),
      );
      AppLogger.logInfo('DTC raw response: $response');

      final dtcs = _validateAndParseDtcResponse(command, response);
      AppLogger.logInfo('Found ${dtcs.length} DTCs: $dtcs');

      return dtcs;
    } catch (e) {
      AppLogger.logError('Failed to retrieve DTCs: $e');
      throw Exception('Failed to retrieve DTCs: $e');
    }
  }

  List<String> _validateAndParseDtcResponse(String command, String response) {
    // Remove any whitespace and normalize the response
    final cleaned = response.replaceAll(RegExp(r'\s+'), '');

    // Find the start of the actual DTC response (after any headers or frame data)
    final dtcStart = cleaned.indexOf('43');
    if (dtcStart == -1) {
      AppLogger.logWarning(
        'Validation failed for $command: Expected response containing 43, got $cleaned',
      );
      throw Exception('Invalid response for $command: $cleaned');
    }

    // Extract the DTC payload starting from '43'
    final payload = cleaned.substring(dtcStart + 2);

    // Process DTCs in groups of 4 hex characters until we hit '0000' or invalid data
    final dtcs = <String>[];
    for (var i = 0; i < payload.length - 3; i += 4) {
      // Stop if we don't have enough characters for a full DTC
      if (i + 4 > payload.length) {
        break;
      }

      final hex = payload.substring(i, i + 4);
      // Stop processing if we hit padding or invalid data
      if (hex == '0000' || !RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(hex)) {
        break;
      }

      final dtc = _decodeDtc(hex);
      dtcs.add(dtc);
    }

    if (dtcs.isEmpty && payload != '0000') {
      AppLogger.logWarning('No valid DTCs found in payload: $payload');
      throw FormatException('No valid DTCs found in response: $payload');
    }

    return dtcs;
  }

  String _decodeDtc(String code) {
    final b1 = int.parse(code.substring(0, 2), radix: 16);
    final b2 = code.substring(2);

    final type = ['P', 'C', 'B', 'U'][(b1 & 0xC0) >> 6];
    final digit1 = ((b1 & 0x30) >> 4).toString();
    final digit2 = (b1 & 0x0F).toRadixString(16).toUpperCase();

    return '$type$digit1$digit2$b2';
  }

  /// Get the system battery voltage
  Future<double> getSystemBatteryVoltage({bool coolOff = true}) async {
    const command = 'ATRV\r';
    const commandDelay = Duration(milliseconds: 250);
    const nominalMin = 12.0;
    const nominalMax = 15.0;

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady)
        throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(
        command,
        timeout: const Duration(seconds: 15),
      );
      final match = RegExp(r'^(\d+\.\d)V$').firstMatch(response);

      if (match == null) throw FormatException('Unexpected format: $response');

      final voltage = double.parse(match.group(1)!);

      if (voltage < nominalMin || voltage > nominalMax) {
        AppLogger.logWarning(
          'Voltage $voltage V out of range ($nominalMin–$nominalMax V)',
        );
      } else {
        AppLogger.logInfo('Battery voltage: $voltage V');
      }

      return voltage;
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the odometer reading (in kilometers) from the vehicle
  Future<int> getOdometer({bool coolOff = true}) async {
    const command = '01A6\r'; // Mode 01, PID A6 for odometer (if supported)
    const commandDelay = Duration(milliseconds: 250);

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady)
        throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(
        command,
        timeout: const Duration(seconds: 15),
      );

      AppLogger.logInfo('Raw odometer response: $response');

      // Handle NO DATA or invalid response
      if (response == 'NO DATA' || response == '?') {
        AppLogger.logWarning('Odometer data not available from ECU');
        return 0; // Return 0 if odometer is not supported
      }

      // Check for valid response starting with '41A6'
      if (!response.startsWith('41A6')) {
        AppLogger.logWarning('Unexpected odometer response format: $response');
        throw FormatException('Unexpected response format: $response');
      }

      // Extract hex data after '41A6'
      final hexData = response.substring(4).replaceAll(RegExp(r'\s+'), '');

      // Expect 8 hex digits (4 bytes) for odometer in kilometers
      if (hexData.length != 8 ||
          !RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(hexData)) {
        AppLogger.logWarning(
          'Invalid odometer data length or format: $hexData',
        );
        throw FormatException('Invalid odometer data: $hexData');
      }

      // Convert hex to integer (kilometers)
      final odometerKm = int.parse(hexData, radix: 16);

      // Convert to miles (1 km = 0.621371 miles) and round to nearest integer
      final odometerMiles = (odometerKm * 0.621371).round();

      AppLogger.logInfo('Odometer: $odometerMiles miles ($odometerKm km)');
      return odometerMiles;
    } catch (e) {
      AppLogger.logError('Failed to retrieve odometer: $e');
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the Vehicle Identification Number (VIN)
  Future<String> getVin({bool coolOff = true}) async {
    const command = '0902\r';
    const commandDelay = Duration(milliseconds: 250);

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady)
        throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(
        command,
        timeout: const Duration(seconds: 15),
      );

      AppLogger.logInfo('Raw VIN response: $response');

      // Handle NO DATA response
      if (response == 'NO DATA' || response == '?') {
        AppLogger.logWarning('VIN not available from ECU');
        return '';
      }

      // Check for valid response starting with '4902'
      if (!response.startsWith('4902')) {
        AppLogger.logWarning('Unexpected VIN response format: $response');
        throw FormatException('Unexpected response format: $response');
      }

      // Extract hex VIN and remove whitespace
      final hexVin = response.substring(4).replaceAll(RegExp(r'\s+'), '');

      // Check for minimum length (17 characters * 2 = 34 hex digits)
      if (hexVin.length < 34) {
        AppLogger.logWarning('VIN too short: $hexVin');
        throw FormatException('VIN too short: $hexVin');
      }

      // Convert hex to ASCII
      final vin = String.fromCharCodes(
        List.generate(
          hexVin.length ~/ 2,
          (i) => int.parse(hexVin.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );

      // Validate VIN length (should be 17 characters)
      if (vin.length != 17) {
        AppLogger.logWarning('Invalid VIN length: ${vin.length} characters');
        throw FormatException('Invalid VIN length: ${vin.length}');
      }

      AppLogger.logInfo('VIN: $vin');
      return vin;
    } catch (e) {
      AppLogger.logError('Failed to retrieve VIN: $e');
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }

  /// Get the actual battery voltage
  Future<double> getActualBatteryVoltage({bool coolOff = true}) async {
    const command = '010B\r';
    const commandDelay = Duration(milliseconds: 250);

    try {
      // Ensure OBD connection is initialized
      if (!_deviceReady)
        throw StateError('Device not ready for OBD operations');

      final response = await _sendObdCommand(
        command,
        timeout: const Duration(seconds: 15),
      );

      if (!response.startsWith('410B')) {
        throw FormatException('Unexpected response format: $response');
      }

      final hexVoltage = response.substring(4).trim();

      if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(hexVoltage)) {
        throw FormatException('Invalid hex format: $hexVoltage');
      }

      final voltage = int.parse(hexVoltage, radix: 16).toDouble();

      AppLogger.logInfo('Actual battery voltage: $voltage V');
      return voltage;
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      if (coolOff) await Future.delayed(commandDelay);
    }
  }
}
