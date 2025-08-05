import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/providers/user_provider.dart';
import 'package:automotiq_app/screens/account_settings_screen.dart';
import 'package:automotiq_app/services/bluetooth_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../utils/logger.dart';
import '../widgets/vehicle_dropdown.dart';
import '../widgets/vehicle_info_card.dart';
import '../models/vehicle_model.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _errorMessage;
  Timer? _dtcCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vehicleProvider = context.read<VehicleProvider>();
      try {
        await vehicleProvider.loadVehicles();
        setState(() => _errorMessage = null);
      } catch (e) {
        AppLogger.logError(e);
        setState(() => _errorMessage = 'Failed to load vehicles: $e');
      }

      // Initialize model and chat in the background
      final modelProvider = Provider.of<ModelProvider>(context, listen: false);
      if (!modelProvider.isModelInitializing &&
          !modelProvider.isModelInitialized) {
        try {
          await modelProvider.initializeModel();
          if (modelProvider.isModelInitialized &&
              !modelProvider.isChatInitializing &&
              !modelProvider.isChatInitialized) {
            await modelProvider.initializeGlobalChat();
          }
        } catch (e) {
          AppLogger.logError(e);
          setState(() => _errorMessage = 'Failed to initialize model/chat: $e');
        }
      }

      // Start periodic DTC check
      _startDtcCheckTimer();
    });
  }

  Future<void> _loadVehicles() async {
    final vehicleProvider = context.read<VehicleProvider>();
    try {
      await vehicleProvider.loadVehicles();
      setState(() => _errorMessage = null);
    } catch (e) {
      AppLogger.logError(e);
      setState(() => _errorMessage = 'Failed to load vehicles: $e');
    }
  }

  Future<void> _attemptConnection(
    BluetoothManager bluetoothManager,
    VehicleModel vehicle,
  ) async {
    try {
      AppLogger.logInfo('Attempting to connect to device: ${vehicle.deviceId}');
      await bluetoothManager.connectToDevice(
        vehicle.deviceId,
        autoReconnect: true,
      );
    } catch (e) {
      AppLogger.logError(e);
    }
  }

  void _startDtcCheckTimer() {
    // Cancel any existing timer to avoid duplicates
    _dtcCheckTimer?.cancel();

    // Check for new errors every 1 minute, adjust if too frequent
    _dtcCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      final vehicleProvider = context.read<VehicleProvider>();
      final bluetoothManager = Provider.of<BluetoothManager?>(
        context,
        listen: false,
      );
      final selectedVehicle = vehicleProvider.selectedVehicle;

      if (selectedVehicle == null ||
          selectedVehicle.id == 'demo' ||
          bluetoothManager == null ||
          selectedVehicle.deviceId.isEmpty) {
        AppLogger.logInfo(
          'Skipping DTC check: No valid vehicle or Bluetooth connection',
        );
        return;
      }

      // Check connection state
      final connectionState = bluetoothManager.getDeviceState();
      if (connectionState != DeviceConnectionState.connected) {
        AppLogger.logInfo('Skipping DTC check: Device not connected');
        return;
      }

      try {
        // Fetch DTCs, VIN, and odometer
        final codes = await bluetoothManager.getVehicleDTCs();

        // TODO: To be added in future release
        // final odometer = await bluetoothManager.getOdometer();

        // Update VehicleModel
        final updatedVehicle = selectedVehicle.copyWith(
          diagnosticTroubleCodes: codes,
          // TODO: To be added in future release
          // vin: vin.isNotEmpty ? vin : selectedVehicle.vin,
          // odometer: odometer > 0 ? odometer : selectedVehicle.odometer,
        );

        // Update Firestore and local state
        await vehicleProvider.updateVehicle(updatedVehicle);
        AppLogger.logInfo(
          'Periodic DTC check completed for vehicle: ${selectedVehicle.id}, '
          'DTCs: ${updatedVehicle.diagnosticTroubleCodes}, ',
          // TODO: To be added in future release
          // 'VIN: ${updatedVehicle.vin}, '
          // 'Odometer: ${updatedVehicle.odometer} miles',
        );
      } catch (e) {
        AppLogger.logError('Periodic DTC check failed: $e');
        // Optionally show a SnackBar for user feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to refresh vehicle data: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _dtcCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AppAuthProvider>();
    final userProvider = context.watch<UserProvider>();
    final vehicleProvider = context.watch<VehicleProvider>();

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(context, authProvider, vehicleProvider),
        body: _buildBody(context, authProvider, userProvider, vehicleProvider),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppAuthProvider authProvider,
    VehicleProvider vehicleProvider,
  ) {
    if (authProvider.isLoading || vehicleProvider.isLoading) {
      return AppBar();
    }
    return AppBar(
      title: VehicleDropdown(),
      actions: [
        IconButton(
          icon: const Icon(Icons.account_circle_rounded),
          onPressed: () {
            AppLogger.logInfo('Account settings button clicked');
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppAuthProvider authProvider,
    UserProvider userProvider,
    VehicleProvider vehicleProvider,
  ) {
    final bluetoothManager = Provider.of<BluetoothManager?>(
      context,
      listen: false,
    );

    if (authProvider.isLoading || vehicleProvider.isLoading) {
      return const _LoadingView();
    }

    if (_errorMessage != null) {
      return _ErrorView(errorMessage: _errorMessage!, onRetry: _loadVehicles);
    }

    if (vehicleProvider.vehicles.isEmpty &&
        userProvider.user?.demoMode == false) {
      return const _EmptyView();
    }

    return Consumer<VehicleProvider>(
      builder: (context, vehicleProvider, child) {
        final selectedVehicle = vehicleProvider.selectedVehicle;
        if (selectedVehicle != null &&
            bluetoothManager != null &&
            selectedVehicle.deviceId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _attemptConnection(bluetoothManager, selectedVehicle);
            AppLogger.logInfo('Done!');
          });
        }
        return _ContentView(
          selectedVehicle: selectedVehicle,
          obdData: 'No Data',
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.deepPurple),
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
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: Theme.of(context).elevatedButtonTheme.style,
            child: const Text('Retry'),
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
    return Center(
      child: Text('No Vehicles', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ContentView extends StatelessWidget {
  final VehicleModel? selectedVehicle;
  final String obdData;

  const _ContentView({this.selectedVehicle, required this.obdData});

  @override
  Widget build(BuildContext context) {
    if (selectedVehicle == null) {
      return Center(
        child: Text(
          'Please select a vehicle',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return VehicleInfoCard(vehicle: selectedVehicle!);
  }
}
