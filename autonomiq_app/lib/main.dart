import 'package:autonomiq_app/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'utils/firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/vehicle_provider.dart';
import 'repositories/vehicle_repository.dart';
import 'app.dart';
import 'utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize Firebase with error handling
    AppLogger.logInfo('Initializing Firebase...', 'main');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, stackTrace) {
    AppLogger.logError(e, stackTrace, 'main');
    // Fallback: Show error screen or retry logic
    runApp(const ErrorApp());
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<UserRepository>(
          create: (_) => UserRepository(firestoreInstance: FirebaseFirestore.instance),
        ),
        ChangeNotifierProvider<AppAuthProvider>(
          create: (_) => AppAuthProvider(firebaseAuth: FirebaseAuth.instance),
        ),
        ChangeNotifierProxyProvider<AppAuthProvider, VehicleProvider>(
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
        ),
      ],
      child: const MyApp(),
    ),
  );
}

// Fallback app for Firebase initialization failure
class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Failed to initialize app. Please try again later.',
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
        ),
      ),
    );
  }
}