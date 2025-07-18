import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Interface to abstract BLE operations for testing and library independence
abstract class BluetoothAdapter {
  Stream<BleStatus> get statusStream;
  Stream<DiscoveredDevice> scanForDevices({List<Uuid> withServices});
  Future<void> connectToDevice(String deviceId);
  Stream<ConnectionStateUpdate> getConnectionStateStream(String deviceId);
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic);
  Future<void> writeCharacteristic(QualifiedCharacteristic characteristic, List<int> value, {bool withResponse});
  Future<void> requestMtu(String deviceId, int mtu);
  Future<void> clearGattCache(String deviceId);
  Future<void> disconnectDevice(String deviceId);
}

class ReactiveBleAdapter implements BluetoothAdapter {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  @override
  Stream<BleStatus> get statusStream => _ble.statusStream;

  @override
  Stream<DiscoveredDevice> scanForDevices({List<Uuid> withServices = const []}) {
    return _ble.scanForDevices(withServices: withServices);
  }

  @override
  Future<void> connectToDevice(String deviceId) async {
    try {
      await _ble
          .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
          .firstWhere(
            (state) => state.connectionState == DeviceConnectionState.connected,
            orElse: () => throw Exception('Connection timeout'),
          );
    } catch (e) {
      rethrow;
    }
  }

  @override
  Stream<ConnectionStateUpdate> getConnectionStateStream(String deviceId) {
    return _ble.connectToDevice(id: deviceId);
  }

  @override
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) async {
    try {
      return await _ble.readCharacteristic(characteristic);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> writeCharacteristic(QualifiedCharacteristic characteristic, List<int> value, {bool withResponse = true}) async {
    try {
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(characteristic, value: value);
      } else {
        await _ble.writeCharacteristicWithoutResponse(characteristic, value: value);
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> requestMtu(String deviceId, int mtu) async {
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> clearGattCache(String deviceId) async {
    try {
      await _ble.clearGattCache(deviceId);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> disconnectDevice(String deviceId) async {
    try {
      // flutter_reactive_ble uses connectToDevice stream to signal disconnection
      await _ble
          .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 5))
          .firstWhere(
            (state) => state.connectionState == DeviceConnectionState.disconnected,
            orElse: () => throw Exception('Disconnection timeout'),
          );
    } catch (e) {
      rethrow;
    }
  }
}