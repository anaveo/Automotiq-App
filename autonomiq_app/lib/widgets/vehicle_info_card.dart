import 'package:autonomiq_app/services/bluetooth_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import '../models/vehicle_model.dart';
import '../providers/providers.dart';
import '../utils/logger.dart';
import '../widgets/current_status_widget.dart';

class VehicleInfoCard extends StatefulWidget {
  final Vehicle vehicle;

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
        _fadeOpacity = offset > 0 ? (offset / appBarHeight) * 0.5 : 0.0;
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
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollNotification) {
              final offset = _scrollController.offset.clamp(0.0, imageHeight);
              setState(() {
                _fadeOpacity = (offset / imageHeight).clamp(0.0, 1.0);
              });
              return false;
            },
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
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          Colors.transparent,
          Colors.black.withOpacity(fadeOpacity),
        ],
        stops: const [0.0, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: Container(
        height: height,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'Vehicle Image Placeholder',
          style: TextStyle(fontSize: 18, color: Colors.white70),
        ),
      ),
    );
  }
}

class VehicleDetailsCard extends StatelessWidget {
  final Vehicle vehicle;
  const VehicleDetailsCard({
    super.key,
    required this.vehicle,
  });

  @override
  Widget build(BuildContext context) {
    final bluetoothManager = Provider.of<BluetoothManager?>(context, listen: false);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<DeviceConnectionState>(
            stream: bluetoothManager != null && vehicle.deviceId.isNotEmpty
                ? bluetoothManager.connectionStateStream
                : Stream.value(DeviceConnectionState.disconnected),
            initialData: DeviceConnectionState.disconnected,
            builder: (context, snapshot) {
              final state = snapshot.data ?? DeviceConnectionState.disconnected;
              return Text(
                'Vehicle Status: ${state.toString().split('.').last}',
                style: TextStyle(
                  color: state == DeviceConnectionState.connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 16,
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 16),
//           CurrentStatusWidget(dtcs: [
//   {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
//   {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
//   {"code": "P0171", "description": "System Too Lean (Bank 1)"},
//         {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
//   {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
//   {"code": "P0171", "description": "System Too Lean (Bank 1)"},
//         {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
//   {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
//   {"code": "P0171", "description": "System Too Lean (Bank 1)"},
// ]), // Placeholder for DTCs
          Text(
            'VIN: ${vehicle.vin.isEmpty ? "N/A" : vehicle.vin}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          Text(
            'Odometer: ${vehicle.odometer == 0 ? "N/A" : "${vehicle.odometer} km"}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }
}