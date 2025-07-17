// widgets/vehicle_dropdown.dart
import 'package:autonomiq_app/utils/navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicle_provider.dart';

class VehicleDropdown extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VehicleProvider>(context);

    return DropdownButtonHideUnderline(
      child: DropdownButton<Vehicle?>(
        value: provider.selectedVehicle,
        icon: const Icon(Icons.arrow_drop_down),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        dropdownColor: Colors.grey[900],
        items: [
          ...provider.vehicles.map((v) => DropdownMenuItem<Vehicle?>(
                value: v,
                child: Text(v.name),
              )),
          const DropdownMenuItem<Vehicle?>(
            value: null,
            child: Text('+ Add new vehicle', style: TextStyle(color: Colors.blueAccent)),
          )
        ],
        onChanged: (selected) {
          if (selected == null) {
            navigateToObdSetup(context);
          } else {
            provider.selectVehicle(selected);
          }
        },
      ),
    );
  }
}
