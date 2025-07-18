import 'package:autonomiq_app/utils/navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vehicle_provider.dart';
import '../utils/logger.dart';
import '../widgets/vehicle_dropdown.dart';
import '../widgets/vehicle_info_card.dart';
import '../models/vehicle_model.dart';
import 'login_screen.dart';

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
      try {
        await vehicleProvider.loadVehicles();
        setState(() {
          _errorMessage = null;
        });
      } catch (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'HomeScreen._loadVehicles');
        setState(() {
          _errorMessage = 'Failed to load vehicles: $e';
        });
      }
    });
  }

  Future<void> _loadVehicles() async {
    final vehicleProvider = Provider.of<VehicleProvider>(context, listen: false);
    try {
      await vehicleProvider.loadVehicles();
      setState(() {
        _errorMessage = null;
      });
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'HomeScreen.loadVehicles');
      setState(() {
        _errorMessage = 'Failed to load vehicles: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppAuthProvider>(context);
    final vehicleProvider = Provider.of<VehicleProvider>(context);

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
            width: 200,
            child: VehicleDropdown()
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
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            tooltip: 'Create Account',
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppAuthProvider authProvider,
    VehicleProvider vehicleProvider,
  ) {
    if (authProvider.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      });
      return const _UnauthenticatedView();
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
    );
  }
}

class _UnauthenticatedView extends StatelessWidget {
  const _UnauthenticatedView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      ),
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

  const _ContentView({this.selectedVehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: selectedVehicle != null
        ? VehicleInfoCard(vehicle: selectedVehicle!)
        : const Text(
            'Please select a vehicle',
            style: TextStyle(color: Colors.white70),
          ),
    );
  }
}