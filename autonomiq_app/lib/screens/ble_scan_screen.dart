import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/vehicle_provider.dart';
import '../utils/navigation.dart';
import '../utils/logger.dart';

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

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
    if (await Permission.bluetoothScan.isDenied ||
        await Permission.bluetoothConnect.isDenied) {
      final status = await Permission.bluetooth.request();
      if (status.isDenied) {
        setState(() {
          _errorMessage = 'Bluetooth permission denied';
        });
        return;
      }
    }
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          _devices = results.map((r) => r.device).toList();
        });
      });
      await Future.delayed(const Duration(seconds: 10));
      setState(() {
        _isScanning = false;
      });
      FlutterBluePlus.stopScan();
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
      await device.connect();
      if (!await _isElm327(device)) {
        await device.disconnect();
        setState(() {
          _errorMessage = 'Device is not an ELM327';
        });
        return;
      }
      final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
      final newVehicle = {
        'name': 'Vehicle_${DateTime.now().millisecondsSinceEpoch}',
        'vin': 'VIN_${DateTime.now().millisecondsSinceEpoch}',
        'year': 2020 + (DateTime.now().year % 10),
        'odometer': 10000 + (DateTime.now().millisecondsSinceEpoch % 50000),
        'isConnected': true,
        'deviceId': device.id.id,
      };
      // await _firestore
      //     .collection('users')
      //     .doc(Provider.of<VehicleProvider>(context, listen: false).userId)
      //     .collection('vehicles')
      //     .add(newVehicle);
      vehicleProvider.addVehicle(newVehicle);
      // vehicleProvider.selectVehicle(newVehicle);
      navigateToHome(context);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.pairAndSave');
      setState(() {
        _errorMessage = 'Failed to pair or save: $e';
      });
      if (device.isConnected) await device.disconnect();
    }
  }

  Future<bool> _isElm327(BluetoothDevice device) async {
    try {
      await device.connect();
      final services = await device.discoverServices();
      await device.disconnect();
      return services.any((s) => s.uuid.toString().contains('elm327')); // Placeholder check
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'BleScanScreen.isElm327');
      return false;
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
                            title: Text(device.name ?? 'Unknown Device', style: const TextStyle(color: Colors.white)),
                            subtitle: Text(device.id.id, style: const TextStyle(color: Colors.white70)),
                            onTap: () => _pairAndSaveDevice(device),
                          );
                        },
                      ),
      ),
    );
  }
}