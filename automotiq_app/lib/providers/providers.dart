import 'package:automotiq_app/utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/services/bluetooth_manager.dart';
import 'package:automotiq_app/repositories/user_repository.dart';
import 'package:automotiq_app/providers/user_provider.dart';
import 'package:automotiq_app/providers/vehicle_provider.dart';
import 'package:automotiq_app/providers/auth_provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/repositories/vehicle_repository.dart';
export 'package:automotiq_app/providers/auth_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final modelProvider = ChangeNotifierProvider<GemmaProvider>(
  create: (_) {
    AppLogger.logInfo('Initializing ModelProvider', 'providers.dart');
    return GemmaProvider(
      variant: dotenv.env['GEMMA_MODEL_VARIANT'] ?? ''
    );
  },
  lazy: true,
);

final appAuthProvider = ChangeNotifierProxyProvider<GemmaProvider, AppAuthProvider>(
  create: (_) {
    AppLogger.logInfo('Creating AppAuthProvider (initial)', 'providers.dart');
    return AppAuthProvider(firebaseAuth: FirebaseAuth.instance);
  },
  update: (_, modelProvider, previous) {
    final provider = previous ?? AppAuthProvider(firebaseAuth: FirebaseAuth.instance);
    if (modelProvider.isModelDownloaded && provider.user == null && !provider.isLoading) {
      AppLogger.logInfo('Triggering anonymous sign-in after model download', 'providers.dart');
      provider.signInAnonymously();
    }
    return provider;
  },
  lazy: true,
);

final userProvider = ChangeNotifierProxyProvider<AppAuthProvider, UserProvider?>(
  create: (_) {
    AppLogger.logInfo('Creating UserProvider (initial)', 'providers.dart');
    return null;
  },
  update: (_, authProvider, previous) {
    if (authProvider.user == null) {
      if (previous != null) {
        AppLogger.logInfo('Disposing UserProvider due to no authenticated user', 'providers.dart');
      }
      return null;
    }
    if (previous == null) {
      AppLogger.logInfo(
        'Initializing UserProvider for user: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
        'providers.dart',
      );
      return UserProvider(
        repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
        uid: authProvider.user!.uid,
      );
    }
    return previous;
  },
  lazy: true,
);

final vehicleProvider = ChangeNotifierProxyProvider<AppAuthProvider, VehicleProvider>(
  create: (_) {
    AppLogger.logInfo('Creating VehicleProvider (initial)', 'providers.dart');
    return VehicleProvider(
      vehicleRepository: VehicleRepository(firestoreInstance: FirebaseFirestore.instance),
      firebaseAuth: FirebaseAuth.instance,
    );
  },
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
      AppLogger.logInfo(
        'Loading vehicles for user: ${user.uid} (anonymous: ${user.isAnonymous})',
        'providers.dart',
      );
      provider.loadVehicles();
    }

    return provider;
  },
  lazy: true,
);

final bluetoothManagerProvider = ProxyProvider<AppAuthProvider, BluetoothManager?>(
  update: (_, authProvider, previous) {
    if (authProvider.user == null) {
      if (previous != null) {
        AppLogger.logInfo('Disposing BluetoothManager due to no authenticated user', 'providers.dart');
        previous.dispose();
      }
      return null;
    }
    if (previous == null) {
      AppLogger.logInfo(
        'Initializing BluetoothManager for user: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
        'providers.dart',
      );
      return BluetoothManager();
    }
    return previous;
  },
  dispose: (_, manager) {
    if (manager != null) {
      AppLogger.logInfo('Disposing BluetoothManager', 'providers.dart');
      manager.dispose();
    }
  },
  lazy: true,
);