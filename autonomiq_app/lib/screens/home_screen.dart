import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/bluetooth_manager.dart';
import '../services/obd_communication_service.dart';
import '../utils/logger.dart';
import '../utils/navigation.dart';
import '../widgets/vehicle_dropdown.dart';
import '../widgets/vehicle_info_card.dart';
import '../models/vehicle_model.dart';

class HomeScreenController {
  final BluetoothManager bluetoothManager;
  String connectionStatus = 'Disconnected';
  String obdData = 'No Data';
  StreamSubscription<DeviceConnectionState>? _connectionStateSubscription;
  ObdCommunicationService? _obdService;

  HomeScreenController({required this.bluetoothManager});

  Future<void> startBluetoothReconnection(Vehicle? selectedVehicle, VoidCallback onStateChange) async {
    if (selectedVehicle == null || selectedVehicle.deviceId.isEmpty) {
      connectionStatus = 'No device selected';
      onStateChange();
      return;
    }

    try {
      connectionStatus = 'Connecting';
      onStateChange();
      // await bluetoothManager.initializeDeviceWithDevice(device);
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = bluetoothManager.getConnectionStateStream().listen(
        (state) {
          connectionStatus = state == DeviceConnectionState.connected ? 'Connected' : 'Disconnected';
          if (state == DeviceConnectionState.connected) {
            AppLogger.logInfo('Connected to device: ${selectedVehicle.deviceId}');
            // _initializeObdCommunication(onStateChange);
          } else {
            obdData = 'No Data';
            _obdService?.dispose();
            _obdService = null;
            onStateChange();
          }
        },
        onError: (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'HomeScreenController.connectionState');
          connectionStatus = 'Error: $e';
          onStateChange();
        },
      );
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreenController.startBluetoothReconnection');
      connectionStatus = 'Error: $e';
      onStateChange();
    }
  }

  Future<void> _initializeObdCommunication(VoidCallback onStateChange) async {
    try {
      final deviceId = bluetoothManager.getCurrentDevice()?.id;
      if (deviceId == null) throw Exception('No device connected');
      _obdService?.dispose();
      _obdService = ObdCommunicationService(bleService: bluetoothManager.bleService, deviceId: deviceId);
      await _obdService!.initialize();
      await Future.delayed(const Duration(seconds: 2)); // Allow time for initialization
      await _obdService!.sendCommand('ATZ\r'); // Reset OBD2
      _obdService!.obdDataStream.listen(
        (data) {
          AppLogger.logInfo('OBD Data: $data');
          obdData = 'RPM: $data';
          onStateChange();
        },
        onError: (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'HomeScreenController.obdData');
          obdData = 'Error: $e';
          onStateChange();
        },
      );
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreenController.initializeObdCommunication');
      connectionStatus = 'Error: $e';
      onStateChange();
    }
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
    _obdService?.dispose();
    bluetoothManager.disconnectDevice();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _errorMessage;
  late HomeScreenController _controller;

  @override
  void initState() {
    super.initState();
    final bluetoothManager = context.read<BluetoothManager>();
    _controller = HomeScreenController(bluetoothManager: bluetoothManager);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vehicleProvider = context.read<VehicleProvider>();
      try {
        await vehicleProvider.loadVehicles();
        setState(() => _errorMessage = null);
        _controller.startBluetoothReconnection(vehicleProvider.selectedVehicle, () => setState(() {}));
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
      _controller.startBluetoothReconnection(vehicleProvider.selectedVehicle, () => setState(() {}));
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreen.loadVehicles');
      setState(() => _errorMessage = 'Failed to load vehicles: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
    return AppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.black,
      foregroundColor: Colors.white,
      shadowColor: Colors.transparent,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: VehicleDropdown(
              onChanged: (vehicle) {
                vehicleProvider.selectVehicle(vehicle);
                _controller.startBluetoothReconnection(vehicle, () => setState(() {}));
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _controller.connectionStatus,
            style: TextStyle(
              color: _controller.connectionStatus == 'Connected'
                  ? Colors.green
                  : _controller.connectionStatus.startsWith('Error')
                      ? Colors.redAccent
                      : Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
      actions: [
        if (authProvider.user?.isAnonymous == false)
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () async {
              try {
                // await authProvider.signOut();
                // navigateTo(context, '/login');
              } catch (e, stackTrace) {
                AppLogger.logError(e, stackTrace, 'HomeScreen.signOut');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to sign out: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
        if (authProvider.user?.isAnonymous == true)
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white70),
            onPressed: () => navigateToObdSetup(context),
            tooltip: 'Create Account',
          ),
        IconButton(
          icon: const Icon(Icons.bluetooth, color: Colors.white70),
          onPressed: () => navigateToObdSetup(context),
          tooltip: 'OBD2 Setup',
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppAuthProvider authProvider,
    VehicleProvider vehicleProvider,
  ) {
    if (authProvider.isLoading) {
      return const _LoadingView();
    }

    if (vehicleProvider.isLoading) {
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
      obdData: _controller.obdData,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'No Vehicles',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => navigateToObdSetup(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              'Add Vehicle',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (selectedVehicle != null) VehicleInfoCard(vehicle: selectedVehicle!),
          if (selectedVehicle == null)
            const Text(
              'Please select a vehicle',
              style: TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 16),
          Text(
            obdData,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }
}