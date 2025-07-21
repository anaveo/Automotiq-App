import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicle_provider.dart';
import '../utils/navigation.dart';
import '../utils/logger.dart';

class VehicleDropdown extends StatelessWidget {
  const VehicleDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = Provider.of<VehicleProvider>(context);
    final vehicles = vehicleProvider.vehicles;
    final selected = vehicleProvider.selectedVehicle;

    void navigateToAddVehicle(BuildContext context) {
      AppLogger.logInfo('Navigating to OBD setup from VehicleDropdown', 'VehicleDropdown');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateToObdSetup(context);
      });
    }

    Widget buildMenuItem(String text, {VoidCallback? onTap}) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
              children: const [
                Icon(Icons.add, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text("Add Vehicle", 
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
        ),
      );
    }

    if (vehicles.isEmpty) {
      return buildMenuItem("Add Vehicle", onTap: () => navigateToAddVehicle(context));
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<VehicleModel>(
        value: selected,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        dropdownColor: const Color.fromARGB(255, 20, 20, 20),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: Colors.white,
        ),
        items: [
          ...vehicles.map((vehicle) {
            final name = vehicle.name.length > 16
                ? '${vehicle.name.substring(0, 16)}…'
                : vehicle.name;
            return DropdownMenuItem<VehicleModel>(
              value: vehicle,
              child: Text(name),
            );
          }),
          DropdownMenuItem<VehicleModel>(
            value: null,
            onTap: () => navigateToAddVehicle(context),
            child: Row(
              children: const [
                Icon(Icons.add, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text("Add Vehicle"),
              ],
            ),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            vehicleProvider.selectVehicle(value);
          }
        },
      ),
    );
  }
}
