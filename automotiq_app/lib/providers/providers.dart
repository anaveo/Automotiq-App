import 'package:automotiq_app/repositories/vehicle_repository.dart';
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
      previous.signInAnonymously().then((_) {
        if (previous.user != null && !modelProvider.isModelInitialized) {
          Future.microtask(() async {
            try {
              await modelProvider.initializeModel();
              if (modelProvider.isModelInitialized && !modelProvider.isChatInitialized) {
                await modelProvider.initializeGlobalChat();
              }
            } catch (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'appAuthProvider.initializeModelAndChat');
            }
          });
        }
      });
    }
    return previous!;
  },
  lazy: true,
);

final userProvider = ChangeNotifierProxyProvider2<ModelProvider, AppAuthProvider, UserProvider>(
  create: (_) {
    AppLogger.logInfo('Creating UserProvider (initial, no UID)', 'providers.dart');
    return UserProvider(
      repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
      uid: null,
    );
  },
  update: (_, modelProvider, authProvider, previous) {
    if (!modelProvider.isModelDownloaded ||
        !modelProvider.isModelInitialized ||
        !modelProvider.isChatInitialized ||
        authProvider.user == null) {
      AppLogger.logInfo('Returning default UserProvider until all dependencies are ready', 'providers.dart');
      return previous ?? UserProvider(
        repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
        uid: null,
      );
    }
    if (previous!.uid != authProvider.user!.uid) {
      AppLogger.logInfo(
        'Initializing UserProvider for user: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
        'providers.dart',
      );
      return UserProvider(
        repository: UserRepository(firestoreInstance: FirebaseFirestore.instance),
        uid: authProvider.user!.uid,
      ); // _initializeUser called in constructor
    }
    return previous;
  },
  lazy: true,
);

final vehicleProvider = ProxyProvider2<ModelProvider, AppAuthProvider?, VehicleProvider?>(
  create: (_) {
    AppLogger.logInfo('Creating VehicleProvider (initial, null)', 'providers.dart');
    return null;
  },
  update: (_, modelProvider, authProvider, previous) {
    if (!modelProvider.isModelDownloaded ||
        !modelProvider.isModelInitialized ||
        !modelProvider.isChatInitialized ||
        authProvider == null) {
      if (previous != null) {
        AppLogger.logInfo('Disposing VehicleProvider until all dependencies are ready', 'providers.dart');
      }
      return null;
    }
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

final bluetoothManagerProvider = ProxyProvider2<ModelProvider, AppAuthProvider?, BluetoothManager?>(
  create: (_) {
    AppLogger.logInfo('Creating BluetoothManager (initial, null)', 'providers.dart');
    return null;
  },
  update: (_, modelProvider, authProvider, previous) {
    if (!modelProvider.isModelDownloaded ||
        !modelProvider.isModelInitialized ||
        !modelProvider.isChatInitialized ||
        authProvider == null ||
        authProvider.user == null) {
      if (previous != null) {
        AppLogger.logInfo('Disposing BluetoothManager until all dependencies are ready', 'providers.dart');
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