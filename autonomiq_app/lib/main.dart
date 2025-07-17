import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'utils/firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/vehicle_provider.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
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
        ChangeNotifierProvider(
          create: (_) => AppAuthProvider(
            authService: AuthService(firebaseAuth: FirebaseAuth.instance),
            firebaseAuth: FirebaseAuth.instance,
          ),
        ),
        // Defer vehicle loading to HomeScreen to ensure auth is complete
        ChangeNotifierProvider(
          create: (_) => VehicleProvider(
            firestore: FirestoreService(firestore: FirebaseFirestore.instance),
            firebaseAuth: FirebaseAuth.instance,
          ),
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