import 'package:automotiq_app/screens/ble_pairing_screen.dart';
import 'package:automotiq_app/services/bluetooth_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../utils/logger.dart';

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    final bluetoothManager = Provider.of<BluetoothManager?>(
      context,
      listen: false,
    );
    if (bluetoothManager == null) {
      setState(() {
        _errorMessage = 'Bluetooth service unavailable';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _devices = [];
    });

    try {
      AppLogger.logInfo('Starting BLE scan');
      final devices = await bluetoothManager.scanForNewDevices(
        timeout: const Duration(seconds: 10),
      );
      setState(() {
        final uniqueDevices = <String, DiscoveredDevice>{};
        for (final device in devices) {
          if (device.name.isNotEmpty) {
            uniqueDevices[device.id] = device;
          }
        }
        _devices = uniqueDevices.values.toList();
        _isScanning = false;
        AppLogger.logInfo(
          'BLE scan completed, found ${_devices.length} devices',
        );
      });
    } catch (e) {
      AppLogger.logError(e);
      setState(() {
        _errorMessage = 'Scan failed: $e';
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shadowColor: Colors.transparent,
        elevation: 0,
        title: const Text('Available Devices'),
      ),
      body: Center(
        child: _errorMessage != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.labelMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startScan,
                    style: Theme.of(context).elevatedButtonTheme.style,
                    child: const Text('Retry'),
                  ),
                ],
              )
            : _isScanning
            ? Image(
                image: const AssetImage(
                  'assets/images/Automotiq_Loading_Gif.gif',
                ),
                width: MediaQuery.of(context).size.width,
              )
            : _devices.isEmpty
            ? Text(
                'No devices found',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    title: Text(
                      device.name.isNotEmpty ? device.name : 'Unknown Device',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      device.id,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlePairingScreen(device: device),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
