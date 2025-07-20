import 'package:autonomiq_app/services/bluetooth_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../utils/logger.dart';
import '../widgets/vehicle_dropdown.dart';
import '../widgets/vehicle_info_card.dart';
import '../models/vehicle_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vehicleProvider = context.read<VehicleProvider>();
      final bluetoothManager = Provider.of<BluetoothManager?>(context, listen: false);
      final selectedVehicle = vehicleProvider.vehicles[0];

      try {
        await vehicleProvider.loadVehicles();
        AppLogger.logInfo('Vehicles loaded successfully', 'HomeScreen.initState');
        if (selectedVehicle != null && bluetoothManager != null && selectedVehicle.deviceId.isNotEmpty) {
          AppLogger.logInfo('Attempting to connect to selected vehicle: ${selectedVehicle.deviceId}', 'HomeScreen.initState');
          _attemptConnection(bluetoothManager, selectedVehicle);
        }
        setState(() => _errorMessage = null);
      } catch (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'HomeScreen.initState');
        setState(() => _errorMessage = 'Failed to load vehicles: $e');
      }
    });
  }

  Future<void> _loadVehicles() async {
    final vehicleProvider = context.read<VehicleProvider>();
    try {
      await vehicleProvider.loadVehicles();
      setState(() => _errorMessage = null);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreen.loadVehicles');
      setState(() => _errorMessage = 'Failed to load vehicles: $e');
    }
  }

  Future<void> _attemptConnection(BluetoothManager bluetoothManager, Vehicle vehicle) async {
    try {
      final state = await bluetoothManager.connectionStateStream.first;
      if (state != DeviceConnectionState.connected) {
        AppLogger.logInfo('Attempting to connect to device: ${vehicle.deviceId}', 'HomeScreen');
        await bluetoothManager.connectToDevice(vehicle.deviceId);
      } else {
        AppLogger.logInfo('Device ${vehicle.deviceId} already connected', 'HomeScreen');
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreen.connectToDevice');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AppAuthProvider>();
    final vehicleProvider = context.watch<VehicleProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(context, authProvider, vehicleProvider),
      body: _buildBody(context, authProvider, vehicleProvider),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppAuthProvider authProvider,
    VehicleProvider vehicleProvider,
  ) {
    if (authProvider.isLoading || vehicleProvider.isLoading) {
      return emptyAppBar();
    }
    return authAppBar(authProvider);
  }

  PreferredSizeWidget emptyAppBar() {
    return AppBar(
      backgroundColor: Colors.purple,
      surfaceTintColor: Colors.black,
      foregroundColor: Colors.white,
      shadowColor: Colors.transparent,
      elevation: 0,
    );
  }

  PreferredSizeWidget authAppBar(AppAuthProvider authProvider) {
    return AppBar(
      backgroundColor: Colors.purple,
      surfaceTintColor: Colors.black,
      foregroundColor: Colors.white,
      shadowColor: Colors.transparent,
      elevation: 0,
      title: VehicleDropdown(),
      actions: [
        // VehicleDropdown(),
        IconButton(
          icon: const Icon(Icons.account_circle_rounded),
          onPressed: () {
            AppLogger.logInfo('Account settings button clicked', 'HomeScreen');
            // TODO: Implement settings/logout functionality
          },
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppAuthProvider authProvider,
    VehicleProvider vehicleProvider,
  ) {
    if (authProvider.isLoading || vehicleProvider.isLoading) {
      return const _LoadingView();
    }

    if (_errorMessage != null) {
      return _ErrorView(
        errorMessage: _errorMessage!,
        onRetry: _loadVehicles,
      );
    }

    if (vehicleProvider.vehicles.isEmpty) {
      return const _EmptyView();
    }

    return _ContentView(
      selectedVehicle: vehicleProvider.selectedVehicle,
      obdData: 'No Data',
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.redAccent),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _ErrorView({required this.errorMessage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            errorMessage,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No Vehicles',
        style: TextStyle(color: Colors.white70, fontSize: 18),
      ),
    );
  }
}

class _ContentView extends StatelessWidget {
  final Vehicle? selectedVehicle;
  final String obdData;

  const _ContentView({this.selectedVehicle, required this.obdData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: [
          if (selectedVehicle != null)
            VehicleInfoCard(vehicle: selectedVehicle!),
          if (selectedVehicle == null)
            const Text(
              'Please select a vehicle',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
        ],
      ),
    );
  }
}