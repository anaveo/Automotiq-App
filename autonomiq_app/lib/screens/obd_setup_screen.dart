import 'package:autonomiq_app/services/permission_service.dart';
import 'package:autonomiq_app/utils/bluetooth_adapter.dart';
import 'package:autonomiq_app/services/ble_service.dart';
import 'package:autonomiq_app/services/permission_service.dart';
import 'package:flutter/material.dart';
import 'ble_scan_screen.dart';

class ObdSetupScreen extends StatelessWidget {
  const ObdSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('OBD2 Setup', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Plug in your new OBD2 device and turn on your car.',
              style: TextStyle(color: Colors.white70, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final bleService = BleService(adapter: FlutterBlueAdapter(), permissionService: SystemPermissionService());
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BleScanScreen(bleService: bleService)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Proceed', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}