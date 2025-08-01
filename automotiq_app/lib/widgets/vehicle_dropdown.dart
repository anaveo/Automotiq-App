import 'package:automotiq_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicle_provider.dart';
import '../utils/logger.dart';

class VehicleDropdown extends StatelessWidget {
  const VehicleDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = Provider.of<VehicleProvider>(context);
    final userProvider = Provider.of<UserProvider?>(context);

    final isDemo = userProvider?.user?.demoMode ?? false;
    final demoVehicle = isDemo ? [vehicleProvider.demoVehicle] : [];

    // Combine vehicles, ensuring no duplicates
    final allVehicles = [
      ...demoVehicle,
      ...vehicleProvider.vehicles,
    ].toSet().toList();
    VehicleModel? selected = vehicleProvider.selectedVehicle;

    // Validate selected vehicle
    if (selected != null && !allVehicles.contains(selected)) {
      // If selected is invalid, reset to a valid option
      selected = allVehicles.isNotEmpty ? allVehicles.first : null;
      if (selected != vehicleProvider.selectedVehicle) {
        // Update provider asynchronously to avoid build-time state changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (selected != null) {
            vehicleProvider.selectVehicle(selected);
          } else {
            vehicleProvider.updateDemoMode(isDemo);
          }
        });
      }
    }

    void navigateToAddVehicle(BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushNamed(context, '/obdSetup');
      });
    }

    if (allVehicles.isEmpty) {
      return InkWell(
        onTap: () => navigateToAddVehicle(context),
        child: const Row(
          children: [
            Icon(Icons.add, size: 18, color: Colors.white),
            SizedBox(width: 8),
            Text("Add Vehicle"),
          ],
        ),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<VehicleModel>(
        value: selected,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        dropdownColor: const Color.fromARGB(255, 20, 20, 20),
        style: Theme.of(context).textTheme.titleLarge,
        items: [
          ...allVehicles.map((vehicle) {
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
            child: const Row(
              children: [
                Icon(Icons.add, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text("Add Vehicle"),
              ],
            ),
          ),
        ],
        onChanged: (value) {
          AppLogger.logInfo('Vehicle selected: ${value?.name ?? "None"}');
          if (value != null) {
            vehicleProvider.selectVehicle(value);
          }
        },
      ),
    );
  }
}
