import 'package:automotiq_app/providers/user_provider.dart';
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
    final userProvider = Provider.of<UserProvider?>(context);

    final isDemo = userProvider?.user?.demoMode ?? false;
    final demoVehicle = isDemo ? [vehicleProvider.demoVehicle] : [];

    final allVehicles = [...demoVehicle, ...vehicleProvider.vehicles];
    final selected = vehicleProvider.selectedVehicle;

    void navigateToAddVehicle(BuildContext context) {
      AppLogger.logInfo('Navigating to OBD setup from VehicleDropdown', 'VehicleDropdown');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateToObdSetup(context);
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
            final name = vehicle.name.length > 16 ? '${vehicle.name.substring(0, 16)}…' : vehicle.name;
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
          AppLogger.logInfo(
            'Vehicle selected: ${value?.name ?? "None"}',
            'VehicleDropdown.onChanged',
          );
          if (value != null) {
            vehicleProvider.selectVehicle(value);
          }
        },
      ),
    );
  }
}
