import 'package:automotiq_app/services/bluetooth_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:automotiq_app/providers/auth_provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/providers/user_provider.dart';
import 'package:automotiq_app/providers/vehicle_provider.dart';
import 'package:automotiq_app/repositories/user_repository.dart';
import 'package:automotiq_app/repositories/vehicle_repository.dart';

final appAuthProvider = ChangeNotifierProxyProvider<ModelProvider, AppAuthProvider>(
  create: (_) {
    AppLogger.logInfo('Creating AppAuthProvider (initial)', 'providers.dart');
    return AppAuthProvider(firebaseAuth: FirebaseAuth.instance);
  },
  update: (_, modelProvider, previous) {
    if (!modelProvider.isModelDownloaded) {
      AppLogger.logInfo('Returning default AppAuthProvider until model is downloaded', 'providers.dart');
      return previous ?? AppAuthProvider(firebaseAuth: FirebaseAuth.instance);
    }
    if (previous!.user == null && !previous.isLoading) {
      AppLogger.logInfo('Triggering anonymous sign-in', 'providers.dart');
      previous.signInAnonymously();
    }
    return previous;
  },
  lazy: true,
);

final userProvider = ChangeNotifierProxyProvider<AppAuthProvider, UserProvider>(
  create: (_) {
    AppLogger.logInfo('Creating UserProvider (initial, no UID)', 'providers.dart');
    return UserProvider(
      repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
      uid: null,
    );
  },
  update: (_, authProvider, previous) {
    if (authProvider.user == null) {
      AppLogger.logInfo('Returning default UserProvider until auth is ready', 'providers.dart');
      return previous ?? UserProvider(
        repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
        uid: null,
      );
    }
    AppLogger.logInfo(
      'Initializing UserProvider for user: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
      'providers.dart',
    );
    return UserProvider(
      repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
      uid: authProvider.user!.uid,
    );
  },
  lazy: true,
);

final vehicleProvider = ChangeNotifierProxyProvider<AppAuthProvider, VehicleProvider>(
  create: (_) {
    AppLogger.logInfo('Creating VehicleProvider (initial, no auth)', 'providers.dart');
    return VehicleProvider(
      vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
      firebaseAuth: FirebaseAuth.instance,
    );
  },
  update: (_, authProvider, previous) {
    if (authProvider.user == null) {
      AppLogger.logInfo('Returning default VehicleProvider until auth is ready', 'providers.dart');
      return previous ?? VehicleProvider(
        vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
        firebaseAuth: FirebaseAuth.instance,
      );
    }
    AppLogger.logInfo(
      'Initializing VehicleProvider for user: ${authProvider.user!.uid}',
      'providers.dart',
    );
    final provider = VehicleProvider(
      vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
      firebaseAuth: FirebaseAuth.instance,
    );
    provider.updateAuth(authProvider.firebaseAuth);
    return provider;
  },
  lazy: true,
);

final bluetoothManagerProvider = ProxyProvider<AppAuthProvider, BluetoothManager>(
  create: (_) {
    AppLogger.logInfo('Creating BluetoothManager (initial, no auth)', 'providers.dart');
    return BluetoothManager();
  },
  update: (_, authProvider, previous) {
    if (authProvider.user == null) {
      AppLogger.logInfo('Returning default BluetoothManager until auth is ready', 'providers.dart');
      return previous ?? BluetoothManager();
    }
    AppLogger.logInfo(
      'Initializing BluetoothManager for user: ${authProvider.user!.uid}',
      'providers.dart',
    );
    return BluetoothManager();
  },
  dispose: (_, manager) {
    AppLogger.logInfo('Disposing BluetoothManager', 'providers.dart');
    manager.dispose();
  },
  lazy: true,
);