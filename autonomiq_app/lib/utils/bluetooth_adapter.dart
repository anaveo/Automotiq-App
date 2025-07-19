import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Interface to abstract BLE operations for testing and library independence
abstract class BluetoothAdapter {
  /// BLE status stream (powered on/off, etc.)
  Stream<BleStatus> get statusStream;

  /// Scan for BLE devices advertising specific services
  Stream<DiscoveredDevice> scanForDevices({
    List<Uuid> withServices,
    ScanMode scanMode,
  });

  /// Connect to a BLE device
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  });

  /// Read a BLE characteristic
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic);

  /// Write to a BLE characteristic (with response)
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  });

  /// Write to a BLE characteristic (without response)
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  });

  /// Request a specific MTU size
  Future<int> requestMtu({
    required String deviceId,
    required int mtu,
  });

  /// Clear GATT cache (Android only)
  Future<void> clearGattCache(String deviceId);
}

class ReactiveBleAdapter implements BluetoothAdapter {
  final _ble = FlutterReactiveBle();

  ReactiveBleAdapter();

  @override
  Stream<BleStatus> get statusStream => _ble.statusStream;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    List<Uuid> withServices = const [],
    ScanMode scanMode = ScanMode.balanced,
  }) {
    return _ble.scanForDevices(
      withServices: withServices,
      scanMode: scanMode,
    );
  }

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    return _ble.connectToDevice(
      id: id,
      servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
      connectionTimeout: connectionTimeout,
    );
  }

  @override
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) {
    return _ble.readCharacteristic(characteristic);
  }

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) {
    return _ble.writeCharacteristicWithResponse(
      characteristic,
      value: value,
    );
  }

  @override
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) {
    return _ble.writeCharacteristicWithoutResponse(
      characteristic,
      value: value,
    );
  }

  @override
  Future<int> requestMtu({
    required String deviceId,
    required int mtu,
  }) {
    return _ble.requestMtu(deviceId: deviceId, mtu: mtu);
  }

  @override
  Future<void> clearGattCache(String deviceId) {
    return _ble.clearGattCache(deviceId);
  }

  void dispose() {
    // TODO: Add cleanup logic if needed
  }
}
