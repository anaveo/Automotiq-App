import 'package:autonomiq_app/providers/providers.dart';
import 'package:autonomiq_app/widgets/current_status_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../services/bluetooth_manager.dart';
import '../utils/logger.dart';

class VehicleInfoCard extends StatefulWidget {
  final VehicleModel vehicle;

  const VehicleInfoCard({super.key, required this.vehicle});

  @override
  State<VehicleInfoCard> createState() => _VehicleInfoCardState();
}

class _VehicleInfoCardState extends State<VehicleInfoCard> {
  final ScrollController _scrollController = ScrollController();
  double _fadeOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final appBarHeight = MediaQuery.of(context).size.height * 0.3;
      final offset = _scrollController.offset.clamp(0.0, appBarHeight);
      setState(() {
        _fadeOpacity = (offset / appBarHeight).clamp(0.0, 1.0);
      });
    });
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
              SliverToBoxAdapter(
                child: SizedBox(height: imageHeight),
              ),
              SliverToBoxAdapter(
                child: VehicleDetailsCard(vehicle: widget.vehicle),
              ),
            ],
          ),
        ),
      ],
    );
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
      opacity: fadeOpacity.clamp(0.0, 1.0), // Ensures opacity stays within bounds
      child: Container(
        height: height,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Image(
          image: AssetImage('assets/images/Pickup_Wireframe.png'), // TODO: Add vehicle selection logic
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class VehicleDetailsCard extends StatelessWidget {
  final VehicleModel vehicle;
  const VehicleDetailsCard({
    super.key,
    required this.vehicle,
  });

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
    final bluetoothManager = Provider.of<BluetoothManager?>(context, listen: false);

    return Container(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 30,
            children: [
              IconButton(onPressed: () {AppLogger.logInfo("Refresh button pressed");/* TODO: Implement ai camera functionality*/}, icon: Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              ),
              IconButton(onPressed: () {AppLogger.logInfo("Diagnose button pressed");/* TODO: Implement ai camera functionality*/}, icon: Icon(Icons.build_circle_outlined),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              ),
              IconButton(onPressed: () {AppLogger.logInfo("C button pressed");/* TODO: Implement ai camera functionality*/}, icon: Icon(Icons.chat_outlined),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconSize: 30,
                  shape: CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
              )  
            ],
          ),
          Card(
            elevation: 3,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: const Color.fromARGB(255, 20, 20, 20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConnectionStatusWidget(
                    bluetoothManager: bluetoothManager,
                    vehicle: vehicle,
                    stateMapper: _mapConnectionStateToString,
                  ),
                  CurrentStatusWidget(dtcs: vehicle.diagnosticTroubleCodes ?? []),
                  const SizedBox(height: 16),
                  Text(
                    'VIN: ${vehicle.vin.isEmpty ? "N/A" : vehicle.vin}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Odometer: ${vehicle.odometer == 0 ? "N/A" : "${vehicle.odometer} miles"}',
                  ),
                ],
              ),
            ),
          )
        ]
      ),
    );
  }
}

class ConnectionStatusWidget extends StatelessWidget {
  final BluetoothManager? bluetoothManager;
  final VehicleModel vehicle;
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
          AppLogger.logError(snapshot.error, null, 'ConnectionStatusWidget');
          return Center(
            child: Padding(
              padding: EdgeInsets.all(18.0),
              child: Text(
                'Vehicle Status: Error',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        }

        final state = snapshot.data ?? DeviceConnectionState.disconnected;
        final isLoading = state == DeviceConnectionState.connecting ||
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