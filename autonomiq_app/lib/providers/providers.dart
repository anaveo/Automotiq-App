import 'package:autonomiq_app/utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:autonomiq_app/services/bluetooth_manager.dart';
import 'package:autonomiq_app/repositories/user_repository.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import 'package:autonomiq_app/repositories/vehicle_repository.dart';

export 'package:autonomiq_app/providers/auth_provider.dart';

final userRepositoryProvider = Provider<UserRepository>(
  create: (_) => UserRepository(firestoreInstance: FirebaseFirestore.instance),
);

final appAuthProvider = ChangeNotifierProvider<AppAuthProvider>(
  create: (_) => AppAuthProvider(firebaseAuth: FirebaseAuth.instance),
);

final vehicleProvider = ChangeNotifierProxyProvider<AppAuthProvider, VehicleProvider>(
  create: (_) => VehicleProvider(
    vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
    firebaseAuth: FirebaseAuth.instance,
  ),
  update: (_, authProvider, previous) {
    final provider = previous ??
        VehicleProvider(
          vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
          firebaseAuth: authProvider.firebaseAuth,
        );

    provider.updateAuth(authProvider.firebaseAuth);

    final user = authProvider.user;
    final notAlreadyLoading = provider.isLoading == false;
    final isEmpty = provider.vehicles.isEmpty;

    if (user != null && notAlreadyLoading && isEmpty) {
      provider.loadVehicles();
    }

    return provider;
  },
);

// TODO: have this provider initialize lazily when auth provider is ready
final bluetoothManagerProvider = Provider<BluetoothManager>(
  create: (context) {
    final manager = BluetoothManager();
    AppLogger.logInfo('BluetoothManager initialized', 'providers.dart');
    return manager;
  },
  dispose: (context, manager) => manager.dispose(),
);