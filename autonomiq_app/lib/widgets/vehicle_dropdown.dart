import 'package:autonomiq_app/services/bluetooth_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicle_provider.dart';
import '../providers/providers.dart';
import '../utils/navigation.dart';
import '../utils/logger.dart';

class VehicleDropdown extends StatelessWidget {
  const VehicleDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = Provider.of<VehicleProvider>(context);
    final bluetoothManager = Provider.of<BluetoothManager?>(context, listen: false);
    final vehicles = vehicleProvider.vehicles;
    final selected = vehicleProvider.selectedVehicle;

    if (vehicles.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: TextButton(
          onPressed: () {
            AppLogger.logInfo('Navigating to OBD setup from VehicleDropdown (empty)', 'VehicleDropdown');
            navigateToObdSetup(context);
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.white54),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: const [
              Icon(Icons.add, size: 18, color: Colors.white70),
              SizedBox(width: 6),
              Text(
                'Add Vehicle',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    const addVehicleValue = null;

    final items = [
      ...vehicles.map((vehicle) => DropdownMenuItem<Vehicle?>(
            value: vehicle,
            child: Text(
              vehicle.name,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          )),
      DropdownMenuItem<Vehicle?>(
        value: addVehicleValue,
        child: Row(
          children: const [
            Icon(Icons.add, size: 18, color: Colors.white70),
            SizedBox(width: 6),
            Text(
              'Add Vehicle',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: DropdownButton<Vehicle?>(
        value: selected,
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
        dropdownColor: Colors.black,
        underline: Container(
          height: 1,
          color: Colors.white54,
        ),
        onChanged: (value) async {
          if (value == addVehicleValue) {
            // TODO: Remove
            AppLogger.logInfo('Navigating to OBD setup from VehicleDropdown', 'VehicleDropdown');
            if (bluetoothManager != null) {
              AppLogger.logInfo('Attempting to connect to device: ${vehicleProvider.vehicles[0].deviceId}', 'VehicleDropdown');
              bluetoothManager.connectToDevice(vehicleProvider.vehicles[0].deviceId);
            }
            else  {
              AppLogger.logWarning('BluetoothManager is null, cannot connect to device', 'VehicleDropdown');
            }
            // navigateToObdSetup(context);
          } else if (value is Vehicle && value != selected) {
            AppLogger.logInfo('Selected vehicle: ${value.name} (ID: ${value.id})', 'VehicleDropdown');
            vehicleProvider.selectVehicle(value);
            if (bluetoothManager != null && value.deviceId.isNotEmpty) {
              try {
                // Check current connection state
                final state = await bluetoothManager.connectionStateStream.first;
                if (state != DeviceConnectionState.connected) {
                  AppLogger.logInfo('Attempting to connect to device: ${value.deviceId}', 'VehicleDropdown');
                  await bluetoothManager.connectToDevice(value.deviceId);
                } else {
                  AppLogger.logInfo('Device ${value.deviceId} already connected', 'VehicleDropdown');
                }
              } catch (e, stackTrace) {
                AppLogger.logError(e, stackTrace, 'VehicleDropdown.connectToDevice');
              }
            } else {
              AppLogger.logWarning('No BluetoothManager or invalid deviceId for vehicle: ${value.name}', 'VehicleDropdown');
            }
          }
        },
        items: items,
        style: const TextStyle(color: Colors.white70, fontSize: 16),
        selectedItemBuilder: (context) => items.map((item) {
          return Align(
            alignment: Alignment.centerLeft,
            child: item.child,
          );
        }).toList(),
        menuMaxHeight: 300,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}