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

  // OBD2 service and characteristic UUIDs for Veepeak OBDCheck BLE+
  static final _obdServiceUuid = Uuid.parse('0000fff0-0000-1000-8000-00805f9b34fb');
  static final _writeCharacteristicUuid = Uuid.parse('0000fff2-0000-1000-8000-00805f9b34fb');
  static final _notifyCharacteristicUuid = Uuid.parse('0000fff1-0000-1000-8000-00805f9b34fb');

  BluetoothManager({
    BleService? bleService,
  }) : _bleService = bleService ?? BleService();

  /// Get the current connection state of the device
  DeviceConnectionState getDeviceState() => _bleService.getDeviceState();

  /// Expose BleService's connection state stream for UI
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

  Future<void> initializeObdConnection() async {
    AppLogger.logInfo('Initializing OBD2 connection...', 'BluetoothManager.initializeObdConnection');
    if (_deviceId == null) throw Exception('No device connected');

    try {
      // Clear GATT cache to avoid stale data
      await _bleService.clearGattCache(_deviceId!);
      AppLogger.logInfo('GATT cache cleared for device: $_deviceId', 'BluetoothManager.initializeObdConnection');

      // Discover all services
      await _bleService.adapter.discoverAllServices(deviceId: _deviceId!);
      final services = await _bleService.adapter.getDiscoveredServices(deviceId: _deviceId!);
      AppLogger.logInfo('Discovered services: ${services.map((s) => s.id.toString()).toList()}', 'BluetoothManager.initializeObdConnection');

      // Find OBD2 service
      final obdService = services.firstWhere(
        (s) => s.id == _obdServiceUuid,
        orElse: () => throw Exception('OBD2 service $_obdServiceUuid not found'),
      );

      // Log characteristics for debugging
      AppLogger.logInfo(
        'Characteristics in service $_obdServiceUuid: ${obdService.characteristics.map((c) => "${c.id} (write=${c.isWritableWithResponse}, writeWithoutResponse=${c.isWritableWithoutResponse}, notify=${c.isNotifiable}, read=${c.isReadable})").toList()}',
        'BluetoothManager.initializeObdConnection',
      );

      // Select write characteristic (0000fff2)
      final writeChar = obdService.characteristics.firstWhere(
        (c) => c.id == _writeCharacteristicUuid && (c.isWritableWithResponse || c.isWritableWithoutResponse),
        orElse: () => throw Exception('Write characteristic $_writeCharacteristicUuid not found or not writable'),
      );

      // Select notify characteristic (0000fff1)
      final notifyChar = obdService.characteristics.firstWhere(
        (c) => c.id == _notifyCharacteristicUuid,
        orElse: () => throw Exception('Notify characteristic $_notifyCharacteristicUuid not found'),
      );

      _obdCharacteristic = QualifiedCharacteristic(
        deviceId: _deviceId!,
        serviceId: _obdServiceUuid,
        characteristicId: writeChar.id,
      );

      _notifyCharacteristic = QualifiedCharacteristic(
        deviceId: _deviceId!,
        serviceId: _obdServiceUuid,
        characteristicId: notifyChar.id,
      );

      // Subscribe to notifications
      if (notifyChar.isNotifiable) {
        _notificationSub?.cancel();
        _notificationSub = _bleService.adapter
            .subscribeToCharacteristic(_notifyCharacteristic!)
            .listen(_onObdNotification, onError: (e, stackTrace) {
          AppLogger.logError('Notification error: $e', stackTrace, 'BluetoothManager.initializeObdConnection');
        });
        AppLogger.logInfo('Subscribed to notifications on ${_notifyCharacteristic!.characteristicId}', 'BluetoothManager.initializeObdConnection');
      } else {
        AppLogger.logWarning('Characteristic ${_notifyCharacteristic!.characteristicId} not notifiable, initialization may fail', 'BluetoothManager.initializeObdConnection');
        throw Exception('Notify characteristic $_notifyCharacteristicUuid is not notifiable');
      }

      // Initialize OBD2 device with retries
      await _sendAndVerifyCommandWithRetry('ATI\r', expectedResponse: 'ELM327', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));
      await _sendAndVerifyCommandWithRetry('ATZ\r', expectedResponse: 'ELM327', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));
      await _sendAndVerifyCommandWithRetry('ATE0\r', expectedResponse: 'OK', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));
      await _sendAndVerifyCommandWithRetry('ATL0\r', expectedResponse: 'OK', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));
      await _sendAndVerifyCommandWithRetry('ATS0\r', expectedResponse: 'OK', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));
      await _sendAndVerifyCommandWithRetry('ATH1\r', expectedResponse: 'OK', useWriteWithoutResponse: writeChar.isWritableWithoutResponse);
      await Future.delayed(const Duration(milliseconds: 200));

      AppLogger.logInfo('OBD2 connection initialized successfully for device: $_deviceId', 'BluetoothManager.initializeObdConnection');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.initializeObdConnection');
      _obdCharacteristic = null;
      _notifyCharacteristic = null;
      _notificationSub?.cancel();
      _notificationBuffer.clear();
      _notificationCompleter = null;
      throw Exception('Failed to initialize OBD2 connection: $e');
    }
  }

  Future<void> _sendAndVerifyCommandWithRetry(
    String command, {
    required String expectedResponse,
    bool useWriteWithoutResponse = false,
    int retries = 3,
  }) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final response = await sendObdCommand(command, useWriteWithoutResponse: useWriteWithoutResponse);
        if (response.isNotEmpty && response.contains(expectedResponse)) {
          AppLogger.logInfo('Command $command succeeded with response: $response', 'BluetoothManager._sendAndVerifyCommandWithRetry');
          return;
        }
        AppLogger.logWarning('Unexpected response for command $command: $response', 'BluetoothManager._sendAndVerifyCommandWithRetry');
      } catch (e, stackTrace) {
        AppLogger.logWarning(
          'Attempt $attempt/$retries failed for command $command: $e',
          'BluetoothManager._sendAndVerifyCommandWithRetry',
        );
        if (attempt == retries) {
          throw Exception('Failed to send command $command after $retries attempts: $e');
        }
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }
  }

  Future<String> sendObdCommand(String command, {bool useWriteWithoutResponse = false}) async {
    if (_deviceId == null || _obdCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception('OBD2 device not initialized or connected');
    }

    try {
      // Clear any existing notification buffer and completer
      _notificationBuffer.clear();
      if (_notificationCompleter != null && !_notificationCompleter!.isCompleted) {
        _notificationCompleter!.completeError(Exception('New command issued before previous completed'));
      }
      _notificationCompleter = Completer<String>();

      // Write command to characteristic
      final commandBytes = Uint8List.fromList('$command\r'.codeUnits);
      await _bleService.writeCharacteristic(
        _obdCharacteristic!,
        commandBytes,
        withResponse: !useWriteWithoutResponse,
      );
      AppLogger.logInfo('Wrote command $command to ${_obdCharacteristic!.characteristicId}', 'BluetoothManager.sendObdCommand');

      // Wait for notification response
      final response = await _notificationCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _notificationBuffer.clear();
          _notificationCompleter = null;
          throw Exception('OBD2 command response timeout');
        },
      );

      AppLogger.logInfo('OBD2 command: $command, response: $response', 'BluetoothManager.sendObdCommand');
      return response;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.sendObdCommand');
      _notificationBuffer.clear();
      _notificationCompleter = null;
      throw Exception('Failed to send OBD2 command: $e');
    }
  }

  void _onObdNotification(List<int> data) {
    AppLogger.logInfo('Received notification: raw=$data, string="${String.fromCharCodes(data)}"', 'BluetoothManager._onObdNotification');
    _notificationBuffer.addAll(data);

    // Check for response termination (\r\r or >)
    final responseString = String.fromCharCodes(_notificationBuffer).trim();
    if (_notificationBuffer.contains(13) && _notificationBuffer.contains(62)) {
      // Full response with prompt (>)
      AppLogger.logInfo('Complete response: $responseString', 'BluetoothManager._onObdNotification');
      if (_notificationCompleter != null && !_notificationCompleter!.isCompleted) {
        _notificationCompleter!.complete(responseString);
        _notificationCompleter = null;
      }
      _notificationBuffer.clear();
    } else if (_notificationBuffer.where((b) => b == 13).length >= 2) {
      // At least two \r, likely includes command echo and response
      if (responseString.contains('ELM327') || responseString.contains('OK')) {
        AppLogger.logInfo('Complete response: $responseString', 'BluetoothManager._onObdNotification');
        if (_notificationCompleter != null && !_notificationCompleter!.isCompleted) {
          _notificationCompleter!.complete(responseString);
          _notificationCompleter = null;
        }
        _notificationBuffer.clear();
      }
    }
  }

  Future<double> getBatteryVoltage() async {
    AppLogger.logInfo('Requesting battery voltage...', 'BluetoothManager.getBatteryVoltage');
    if (_deviceId == null || _obdCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception('OBD2 device not initialized or connected');
    }

    try {
      final response = await sendObdCommand('ATRV\r', useWriteWithoutResponse: _obdCharacteristic!.characteristicId == _writeCharacteristicUuid);
      AppLogger.logInfo('Battery voltage response: $response', 'BluetoothManager.getBatteryVoltage');

      // Check for error responses
      if (response.contains('NO DATA') || response.contains('ERROR') || response.contains('?')) {
        throw Exception('Failed to retrieve battery voltage: $response');
      }

      // Parse response (e.g., "41 42 XX YY" for PID 0142)
      final parts = response.trim().split(' ');
      if (parts.length < 4 || parts[0] != '41' || parts[1] != '42') {
        throw Exception('Invalid battery voltage response format: $response');
      }

      // Convert hex bytes to voltage: ((XX * 256) + YY) / 1000
      final xx = int.parse(parts[2], radix: 16);
      final yy = int.parse(parts[3], radix: 16);
      final voltage = ((xx * 256) + yy) / 1000.0;

      AppLogger.logInfo('Parsed battery voltage: $voltage V', 'BluetoothManager.getBatteryVoltage');
      return voltage;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.getBatteryVoltage');
      throw Exception('Failed to retrieve battery voltage: $e');
    }
  }

  Future<void> connectToDevice(String deviceId, {bool autoReconnect = false}) async {
    try {
      if (_deviceId == deviceId && _bleService.getDeviceState() == DeviceConnectionState.connected) {
        AppLogger.logInfo(
          'Already connected to device: $deviceId',
          'BluetoothManager.connectToDevice',
        );
        return;
      }

      _deviceId = deviceId;
      await _bleService.connectToDevice(deviceId, connectionTimeout: const Duration(seconds: 10));

      if (autoReconnect) {
        final subscription = _bleService.connectionStateStream.listen(
          (state) async {
            if (state == DeviceConnectionState.disconnected && _deviceId != null) {
              AppLogger.logInfo('Attempting to reconnect to $deviceId', 'BluetoothManager.connectToDevice');
              try {
                await _bleService.connectToDevice(deviceId);
              } catch (e, stackTrace) {
                AppLogger.logError(e, stackTrace, 'BluetoothManager.reconnect');
                _deviceId = null;
                _obdCharacteristic = null;
                _notifyCharacteristic = null;
                _notificationSub?.cancel();
              }
            }
          },
          onError: (e, stackTrace) {
            AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
            _deviceId = null;
            _obdCharacteristic = null;
            _notifyCharacteristic = null;
            _notificationSub?.cancel();
          },
        );

        _bleService.connectionStateStream.listen(null).onDone(() {
          subscription.cancel();
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.connectToDevice');
      _deviceId = null;
      _obdCharacteristic = null;
      _notifyCharacteristic = null;
      _notificationSub?.cancel();
      throw Exception('Failed to connect to device: $e');
    }
  }

  Future<void> disconnectDevice() async {
    if (_deviceId == null) {
      AppLogger.logInfo('No device to disconnect', 'BluetoothManager.disconnectDevice');
      return;
    }

    try {
      await _bleService.disconnectDevice();
      _notificationSub?.cancel();
      _notificationBuffer.clear();
      _notificationCompleter = null;
      _deviceId = null;
      _obdCharacteristic = null;
      _notifyCharacteristic = null;
      AppLogger.logInfo('Disconnected device', 'BluetoothManager.disconnectDevice');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.disconnectDevice');
      _deviceId = null;
      _obdCharacteristic = null;
      _notifyCharacteristic = null;
      _notificationSub?.cancel();
      throw Exception('Failed to disconnect device: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await disconnectDevice();
      AppLogger.logInfo('BluetoothManager disposed', 'BluetoothManager.dispose');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BluetoothManager.dispose');
      throw Exception('Failed to dispose BluetoothManager: $e');
    }
  }
}