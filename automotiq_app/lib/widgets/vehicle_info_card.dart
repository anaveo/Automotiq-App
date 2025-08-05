import 'package:automotiq_app/screens/chat_screen.dart';
import 'package:automotiq_app/screens/diagnosis_screen.dart';
import 'package:automotiq_app/widgets/current_status_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../objects/vehicle_object.dart';
import '../services/bluetooth_manager.dart';
import '../utils/logger.dart';
import '../services/dtc_database_service.dart';
import '../providers/vehicle_provider.dart';

class VehicleInfoCard extends StatefulWidget {
  final VehicleObject vehicle;

  const VehicleInfoCard({super.key, required this.vehicle});

  @override
  State<VehicleInfoCard> createState() => _VehicleInfoCardState();
}

class _VehicleInfoCardState extends State<VehicleInfoCard> {
  final ScrollController _scrollController = ScrollController();
  double _fadeOpacity = 0.0;
  late VehicleObject _currentVehicle; // Track current vehicle state

  @override
  void initState() {
    super.initState();
    _currentVehicle = widget.vehicle; // Initialize with widget.vehicle
    _scrollController.addListener(() {
      final appBarHeight = MediaQuery.of(context).size.height * 0.3;
      final offset = _scrollController.offset.clamp(0.0, appBarHeight);
      setState(() {
        _fadeOpacity = (offset / appBarHeight).clamp(0.0, 1.0);
      });
    });
  }

  @override
  void didUpdateWidget(covariant VehicleInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle != widget.vehicle) {
      _currentVehicle = widget.vehicle;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = screenHeight * 0.3;

    return Stack(
      children: [
        Container(color: Colors.black),
        VehicleImagePlaceholder(
          height: imageHeight,
          fadeOpacity: 1.0 - _fadeOpacity,
        ),
        SizedBox(
          height: screenHeight,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: imageHeight)),
              SliverToBoxAdapter(
                child: VehicleDetailsCard(
                  vehicle: _currentVehicle, // Pass current vehicle
                  onRefresh: _refreshDtcCodes, // Pass refresh callback
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _refreshDtcCodes() async {
    final bluetoothManager = Provider.of<BluetoothManager?>(
      context,
      listen: false,
    );
    final vehicleProvider = Provider.of<VehicleProvider>(
      context,
      listen: false,
    );

    try {
      List<String> newDtcs;
      if (widget.vehicle.id == 'demo') {
        newDtcs = await loadRandomDtcCodes();
      } else if (bluetoothManager != null &&
          widget.vehicle.deviceId.isNotEmpty) {
        newDtcs = (await bluetoothManager.getVehicleDTCs())
            .map((code) => code.toUpperCase())
            .toList();
      } else {
        AppLogger.logWarning('No valid device or demo mode not active');
        return;
      }

      // Create a new VehicleObject with updated DTCs
      final updatedVehicle = widget.vehicle.copyWith(
        diagnosticTroubleCodes: newDtcs,
      );

      // Update Firestore via VehicleProvider
      await vehicleProvider.updateVehicle(updatedVehicle);

      // Update local state to trigger rebuild
      setState(() {
        _currentVehicle = updatedVehicle;
      });

      AppLogger.logInfo(
        'DTC codes updated: ${updatedVehicle.diagnosticTroubleCodes}',
      );
    } catch (e) {
      AppLogger.logError('Failed to refresh DTC codes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh DTC codes: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<List<String>> loadRandomDtcCodes() async {
    Set<String> codesSet = {};
    while (codesSet.length < 1) {
      String? codeNullable = await DtcDatabaseService().getRandomDtcCode();
      if (codeNullable != null) {
        codesSet.add(codeNullable.toUpperCase());
      }
    }
    return codesSet.toList();
  }
}

class VehicleImagePlaceholder extends StatelessWidget {
  final double height;
  final double fadeOpacity;

  const VehicleImagePlaceholder({
    super.key,
    required this.height,
    required this.fadeOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: fadeOpacity.clamp(0.0, 1.0),
      child: Container(
        height: height,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Image(
          image: AssetImage('assets/images/Sedan_Wireframe.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class VehicleDetailsCard extends StatefulWidget {
  final VehicleObject vehicle;
  final VoidCallback onRefresh; // Callback for refresh button

  const VehicleDetailsCard({
    super.key,
    required this.vehicle,
    required this.onRefresh,
  });

  @override
  State<VehicleDetailsCard> createState() => _VehicleDetailsCardState();
}

class _VehicleDetailsCardState extends State<VehicleDetailsCard> {
  String _mapConnectionStateToString(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.connecting:
        return 'Connecting...';
      case DeviceConnectionState.disconnecting:
        return 'Disconnecting...';
      case DeviceConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothManager = Provider.of<BluetoothManager?>(
      context,
      listen: false,
    );

    return Container(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 30,
            children: [
              IconButton(
                onPressed: widget.onRefresh, // Use callback
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  AppLogger.logInfo("Diagnose button pressed");
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => DiagnosisScreen(
                        dtcs: widget.vehicle.diagnosticTroubleCodes,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.build_circle_outlined),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (context) => ChatScreen()),
                  );
                },
                icon: const Icon(Icons.chat_outlined),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          Card(
            elevation: 3,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: const Color.fromARGB(255, 20, 20, 20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConnectionStatusWidget(
                    bluetoothManager: bluetoothManager,
                    vehicle: widget.vehicle,
                    stateMapper: _mapConnectionStateToString,
                  ),
                  CurrentStatusWidget(
                    dtcs: widget.vehicle.diagnosticTroubleCodes,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Odometer: ${widget.vehicle.odometer == 0 ? "N/A" : "${widget.vehicle.odometer} miles"}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionStatusWidget extends StatelessWidget {
  final BluetoothManager? bluetoothManager;
  final VehicleObject vehicle;
  final String Function(DeviceConnectionState) stateMapper;

  const ConnectionStatusWidget({
    super.key,
    required this.bluetoothManager,
    required this.vehicle,
    required this.stateMapper,
  });

  @override
  Widget build(BuildContext context) {
    if (bluetoothManager == null || vehicle.deviceId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 18.0),
          child: Text(
            'Not linked to OBD2 device',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }

    return StreamBuilder<DeviceConnectionState>(
      stream: bluetoothManager!.connectionStateStream,
      initialData: bluetoothManager!.getDeviceState(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLogger.logError('Connection status error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Text(
                'Vehicle Status: Error',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        }

        final state = snapshot.data ?? DeviceConnectionState.disconnected;
        final isLoading =
            state == DeviceConnectionState.connecting ||
            state == DeviceConnectionState.disconnecting;

        return Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 18.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                if (isLoading) const SizedBox(width: 8),
                Text(
                  stateMapper(state),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: state == DeviceConnectionState.connected
                        ? Colors.greenAccent
                        : isLoading
                        ? Colors.white70
                        : Colors.redAccent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
