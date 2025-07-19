import 'dart:async';
import 'package:autonomiq_app/models/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/bluetooth_manager.dart';
import '../utils/navigation.dart';
import '../utils/logger.dart';

class BleScanScreen extends StatefulWidget {
  final BluetoothManager bluetoothManager;

  const BleScanScreen({super.key, required this.bluetoothManager});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      await widget.bluetoothManager.bleService.requestPermissions();
      _startScan();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.checkPermissions');
      setState(() {
        _errorMessage = 'Permission request failed: $e';
      });
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _devices = [];
    });
    try {
      final devices = await widget.bluetoothManager.scanForElmDevices(timeout: const Duration(seconds: 10));
      setState(() {
        final uniqueDevices = <String, DiscoveredDevice>{};
        for (final d in devices) {
          if (d.name.isNotEmpty) {
            uniqueDevices[d.id] = d;
          }
        }
        _devices = uniqueDevices.values.toList();
        _isScanning = false;
      });
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.startScan');
      setState(() {
        _errorMessage = 'Scan failed: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _pairAndSaveDevice(DiscoveredDevice device) async {
    try {
      final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
      await widget.bluetoothManager.bleService.connectToDevice(device.id);

      // Ensure device has valid name and manufacturer data
      if (device.id.isEmpty) {
        throw ArgumentError("Invalid device: missing ID");
      }

      // Create dummy vehicle (TODO: use actual device data)
      Vehicle newVehicle = Vehicle(
        deviceId: device.id,
        id: 'Unknown', // Placeholder, will be updated by Firestore
        name: 'Test_${DateTime.now().millisecond}',
        vin: '1234567890ABCDEF',
        year: 2020 + (DateTime.now().year % 10),
        odometer: 10000 + (DateTime.now().millisecondsSinceEpoch % 50000),
        diagnosticTroubleCodes: [], // TODO: Replace with List<Map>
      );


      // Add vehicle to Firestore
      vehicleProvider.addVehicle(newVehicle);

      navigateToHome(context);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.pairAndSave');
      setState(() {
        _errorMessage = 'Failed to pair or save vehicle: $e';
      });
      if (await widget.bluetoothManager.bleService.getDeviceState(device.id) == DeviceConnectionState.connected) {
        await widget.bluetoothManager.bleService.disconnectDevice(device.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan for OBD2', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _errorMessage != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkPermissions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            : _isScanning
                ? const CircularProgressIndicator(color: Colors.redAccent)
                : _devices.isEmpty
                    ? const Text('No devices found', style: TextStyle(color: Colors.white70))
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return ListTile(
                            title: Text(device.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(device.id, style: const TextStyle(color: Colors.white70)),
                            onTap: () => _pairAndSaveDevice(device),
                          );
                        },
                      ),
      ),
    );
  }
}
