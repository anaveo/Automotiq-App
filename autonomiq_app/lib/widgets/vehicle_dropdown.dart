import 'package:autonomiq_app/utils/navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicle_provider.dart';

class VehicleDropdown extends StatelessWidget {
  final Function(Vehicle)? onChanged; // Changed to Vehicle to exclude Add Vehicle

  const VehicleDropdown({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = Provider.of<VehicleProvider>(context);
    final vehicles = vehicleProvider.vehicles;
    final selected = vehicleProvider.selectedVehicle;

    void handleSelection(dynamic value) {
      if (value == '__add_vehicle__') {
        navigateToObdSetup(context);
      } else if (value is Vehicle && value != selected) {
        vehicleProvider.selectVehicle(value);
        onChanged?.call(value); // Trigger onChanged for vehicle selection
      }
    }

    if (vehicles.isEmpty) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
        onPressed: () => navigateToObdSetup(context), // No onChanged
      );
    }

    return DropdownButton<dynamic>(
      value: selected,
      isExpanded: true,
      icon: const Icon(Icons.arrow_drop_down),
      onChanged: handleSelection,
      items: [
        ...vehicles.map((vehicle) {
          return DropdownMenuItem(
            value: vehicle,
            child: Text(vehicle.name),
          );
        }).toList(),
        const DropdownMenuItem(
          value: '__add_vehicle__',
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 6),
              Text('Add Vehicle'),
            ],
          ),
        ),
      ],
    );
  }
}