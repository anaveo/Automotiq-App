// screens/add_vehicle_screen.dart
import 'package:flutter/material.dart';
import 'package:autonomiq_app/services/ble_service.dart'; // Adjust path as needed
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AddVehiclePage extends StatefulWidget {
  const AddVehiclePage({Key? key}) : super(key: key);

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  final BleService _bleService = BleService(); // instance of your service
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    final scannedDevices = await _bleService.scanForElmDevices(
      timeout: const Duration(seconds: 5),
    );

    setState(() {
      _devices = scannedDevices;
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Vehicle')),
      body: _isScanning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return ListTile(
                  title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unnamed device'),
                  subtitle: Text(device.remoteId.toString()),
                  onTap: () {
                    // Later: connect and register vehicle
                  },
                );
              },
            ),
    );
  }
}
