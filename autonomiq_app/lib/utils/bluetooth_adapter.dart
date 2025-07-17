import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Interface to abstract FlutterBluePlus for testing
abstract class BluetoothAdapter {
  Stream<List<ScanResult>> get scanResults;
  Future<void> startScan({Duration timeout});
  Future<void> stopScan();
  Future<List<BluetoothDevice>> get connectedDevices;
}

class FlutterBlueAdapter implements BluetoothAdapter {
  @override
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 5)}) {
    return FlutterBluePlus.startScan(timeout: timeout);
  }

  @override
  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }

  @override
  Future<List<BluetoothDevice>> get connectedDevices async {
    return FlutterBluePlus.connectedDevices;
  }
}
