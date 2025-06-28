import 'package:flutter/material.dart';
import '../models/vehicle_model.dart';
import 'current_status_widget.dart';

class VehicleInfoCard extends StatelessWidget {
  final Vehicle vehicle;

  const VehicleInfoCard({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final dummyCodes = [
      {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
      {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
      {"code": "P0171", "description": "System Too Lean (Bank 1)"},
    ];

    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        /// Placeholder for car image — 30% of screen height
        Container(
          height: screenHeight * 0.3,
          width: double.infinity,
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text(
            "Vehicle Image Placeholder",
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
        ),

        /// Card with vehicle details and status — fills remaining space
        Expanded(
          child: Card(
            elevation: 3,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CurrentStatusWidget(dtcs: dummyCodes),
                  const SizedBox(height: 24),
                  Text("VIN: ${vehicle.vin}"),
                  Text("Year: ${vehicle.year}"),
                  Text("Odometer: ${vehicle.odometer} km"),
                  Text("Connected: ${vehicle.isConnected ? 'Yes' : 'No'}"),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
