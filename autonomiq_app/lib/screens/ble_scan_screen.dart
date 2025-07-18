import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/vehicle_provider.dart';
import '../services/ble_service.dart';
import '../utils/navigation.dart';
import '../utils/logger.dart';

class BleScanScreen extends StatefulWidget {
  final BleService bleService;

  const BleScanScreen({super.key, required this.bleService});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  String? _errorMessage;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      await widget.bleService.requestPermissions();
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
      final devices = await widget.bleService.scanForElmDevices(timeout: const Duration(seconds: 10));
      setState(() {
        _devices = devices;
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

  Future<void> _pairAndSaveDevice(BluetoothDevice device) async {
    try {
      final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
      // final userId = Provider.of<VehicleProvider>(context, listen: false).userId;
      // if (userId == null || userId.isEmpty) {
      //   throw Exception('User ID is null or empty');
      // }

      await widget.bleService.connect(device);

      final newVehicle = {
        'name': 'Vehicle_${DateTime.now().millisecondsSinceEpoch}',
        'vin': 'VIN_${DateTime.now().millisecondsSinceEpoch}',
        'year': 2020 + (DateTime.now().year % 10),
        'odometer': 10000 + (DateTime.now().millisecondsSinceEpoch % 50000),
        'isConnected': true,
        'deviceId': device.id.id,
      };

      // Add vehicle to Firestore
      // final firestoreService = FirestoreService();
      // final vehicleId = await firestoreService.addVehicle(userId, newVehicle);

      // Add to VehicleProvider with Firestore document ID
      // newVehicle['id'] = vehicleId;
      vehicleProvider.addVehicle(newVehicle);

      navigateToHome(context);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.pairAndSave');
      setState(() {
        _errorMessage = 'Failed to pair or save vehicle: $e';
      });
      if (await widget.bleService.getDeviceState(device) == BluetoothConnectionState.connected) {
        await widget.bleService.disconnect(device);
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
                            title: Text(device.platformName, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(device.remoteId.str, style: const TextStyle(color: Colors.white70)),
                            onTap: () => _pairAndSaveDevice(device),
                          );
                        },
                      ),
      ),
    );
  }
}