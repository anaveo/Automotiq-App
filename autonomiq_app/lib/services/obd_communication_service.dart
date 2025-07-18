import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/logger.dart';

class ObdCommunicationService {
  final BluetoothDevice device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  final StreamController<String> _dataController = StreamController.broadcast();

  ObdCommunicationService({required this.device});

  /// Initialize OBD2 communication
  Future<void> initialize() async {
    try {
      final services = await device.discoverServices();

      // Find the OBD2 communication service
      final obdService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == '00006287-3c17-d293-8e48-14fe2e4da212',
        orElse: () => throw Exception('OBD2 service not found'),
      );

      // Get the single read+write+notify characteristic
      final characteristic = obdService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == '00006487-3c17-d293-8e48-14fe2e4da212',
        orElse: () => throw Exception('OBD2 characteristic not found'),
      );

      _writeCharacteristic = characteristic;
      _readCharacteristic = characteristic;

      await _readCharacteristic!.setNotifyValue(true);

      final buffer = StringBuffer();
      _readCharacteristic!.value.listen((data) {
        final chunk = String.fromCharCodes(data);
        buffer.write(chunk);
        if (chunk.contains('>')) {
          _dataController.add(buffer.toString().trim());
          buffer.clear();
        }
      }, onError: (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'ObdCommunicationService.read');
        _dataController.addError(e, stackTrace);
      });
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ObdCommunicationService.initialize');
      rethrow;
    }
  }


  /// Send OBD2 command (e.g., PID request)
  Future<void> sendCommand(String command) async {
    if (_writeCharacteristic == null) {
      throw Exception('Service not initialized');
    }
    try {
      await _writeCharacteristic!.write(command.codeUnits, withoutResponse: false);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ObdCommunicationService.sendCommand');
      rethrow;
    }
  }

  /// Stream for OBD2 responses
  Stream<String> get obdDataStream => _dataController.stream;

  /// Clean up
  Future<void> dispose() async {
    await _dataController.close();
  }
}