import 'package:flutter/material.dart';
import '../models/vehicle_model.dart';
import 'current_status_widget.dart';

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
        _fadeOpacity = offset > 0 ? (offset / appBarHeight) * 0.5 : 0.0; // Fade only when overlapping
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
        // Base layer: solid black to prevent bleed-through
        Container(color: Colors.black),
        // Background image area that fades out
        VehicleImagePlaceholder(
          height: imageHeight,
          fadeOpacity: 1.0 - _fadeOpacity, // invert fade
        ),

        // Scrollable content overlapping image
        NotificationListener<ScrollNotification>(
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
              // Transparent space for image placeholder
              SliverToBoxAdapter(
                child: SizedBox(height: imageHeight),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  VehicleDetailsCard(vehicle: widget.vehicle),
                ]),
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
          "Vehicle Image Placeholder",
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class VehicleDetailsCard extends StatelessWidget {
  final Vehicle vehicle;

  const VehicleDetailsCard({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final dummyCodes = [
      {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
      {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
      {"code": "P0171", "description": "System Too Lean (Bank 1)"},
            {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
      {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
      {"code": "P0171", "description": "System Too Lean (Bank 1)"},
            {"code": "P0301", "description": "Cylinder 1 Misfire Detected"},
      {"code": "P0420", "description": "Catalyst System Efficiency Below Threshold"},
      {"code": "P0171", "description": "System Too Lean (Bank 1)"},
    ];

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CurrentStatusWidget(dtcs: dummyCodes),
            const SizedBox(height: 24),
            Text("VIN: ${vehicle.vin ?? 'Unknown'}"),
            Text("Year: ${vehicle.year ?? 'Unknown'}"),
            Text("Odometer: ${vehicle.odometer != null ? '${vehicle.odometer} km' : 'Unknown'}"),
            Text("Connected: ${vehicle.isConnected ? 'Yes' : 'No'}"),
          ],
        ),
      ),
    );
  }
}