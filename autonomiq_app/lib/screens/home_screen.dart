// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vehicle_provider.dart';
import '../widgets/vehicle_dropdown.dart';
import '../widgets/vehicle_info_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VehicleProvider>(context);

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.vehicles.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('No Vehicles')),
        body: const Center(child: Text('Add a new vehicle to get started.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            VehicleDropdown(),
          ],
        ),
      ),
      body: VehicleInfoCard(vehicle: provider.selectedVehicle!),
    );
  }
}
