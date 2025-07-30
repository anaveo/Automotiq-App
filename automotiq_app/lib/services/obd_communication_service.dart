import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble_service.dart';
import '../utils/logger.dart';

class ObdCommunicationService {
  final BleService bleService;
  final String deviceId;
  QualifiedCharacteristic? _characteristic;
  final StreamController<String> _dataController = StreamController.broadcast();
  StreamSubscription<List<int>>? _notificationSubscription;

  ObdCommunicationService({required this.bleService, required this.deviceId});

  /// Initialize OBD2 communication
  Future<void> initialize() async {
    // try {
    //   // Discover services
    //   final services = await bleService.discoverServices(deviceId);

    //   // Find the OBD2 communication service
    //   final obdService = services.firstWhere(
    //     (s) => s.serviceId.toString().toLowerCase() == '00006287-3c17-d293-8e48-14fe2e4da212',
    //     orElse: () => throw Exception('OBD2 service not found'),
    //   );

    //   // Get the single read+write+notify characteristic
    //   final characteristic = obdService.characteristicIds.firstWhere(
    //     (c) => c.toString().toLowerCase() == '00006487-3c17-d293-8e48-14fe2e4da212',
    //     orElse: () => throw Exception('OBD2 characteristic not found'),
    //   );

    //   _characteristic = QualifiedCharacteristic(
    //     serviceId: obdService.serviceId,
    //     characteristicId: characteristic,
    //     deviceId: deviceId,
    //   );

    //   // Enable notifications
    //   _notificationSubscription = bleService.subscribeToCharacteristic(_characteristic!).listen(
    //     (data) {
    //       final chunk = String.fromCharCodes(data);
    //       final buffer = StringBuffer();
    //       buffer.write(chunk);
    //       if (chunk.contains('>')) {
    //         _dataController.add(buffer.toString().trim());
    //         buffer.clear();
    //       }
    //     },
    //     onError: (e) {
    //       AppLogger.logError(e);
    //       _dataController.addError(e);
    //     },
    //   );
    // } catch (e) {
    //   AppLogger.logError(e);
    //   rethrow;
    // }
  }

  /// Send OBD2 command (e.g., PID request)
  Future<void> sendCommand(String command) async {
    if (_characteristic == null) {
      throw Exception('Service not initialized');
    }
    try {
      await bleService.writeCharacteristic(_characteristic!, command.codeUnits, withResponse: true);
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    }
  }

  /// Stream for OBD2 responses
  Stream<String> get obdDataStream => _dataController.stream;

  /// Clean up
  Future<void> dispose() async {
    await _notificationSubscription?.cancel();
    await _dataController.close();
  }
}