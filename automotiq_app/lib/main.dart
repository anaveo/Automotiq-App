import 'package:automotiq_app/providers/auth_provider.dart';
import 'package:automotiq_app/providers/user_provider.dart';
import 'package:automotiq_app/theme/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:automotiq_app/providers/providers.dart';
import 'package:automotiq_app/screens/home_screen.dart';
import 'package:automotiq_app/screens/splash_screen.dart';
import 'package:automotiq_app/screens/login_screen.dart';
import 'package:automotiq_app/screens/new_device_setup_screen.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/unified_background_service.dart'; // Add this import

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelProvider>(
      builder: (context, modelProvider, child) {
        // Show splash screen during model download
        if (modelProvider.isModelDownloading ||
            !modelProvider.isModelDownloaded) {
          return const SplashScreen();
        }

        // Show error screen if download fails
        if (modelProvider.downloadError != null) {
          return ErrorApp(errorMessage: modelProvider.downloadError!);
        }

        // Proceed to auth when model is downloaded
        return Consumer<AppAuthProvider>(
          builder: (context, authProvider, child) {
            // Show loader during auth or user loading
            if (authProvider.isLoading ||
                Provider.of<UserProvider>(context).isLoading) {
              return const LoaderScreen();
            }

            // Show error screen if auth fails
            if (authProvider.authError != null) {
              return ErrorApp(errorMessage: authProvider.authError!);
            }

            // Access UserProvider
            final userProvider = Provider.of<UserProvider>(context);

            // Show home screen if authenticated and user initialized
            if (authProvider.user != null && userProvider.user != null) {
              return const HomeScreen();
            }

            // Default to login screen
            return const LoginScreen();
          },
        );
      },
    );
  }
}

class LoaderScreen extends StatelessWidget {
  const LoaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Setting up your account...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                errorMessage,
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  AppLogger.logInfo('Retrying app initialization');
                  Provider.of<ModelProvider>(
                    context,
                    listen: false,
                  ).startModelDownload();
                },
                style: Theme.of(context).elevatedButtonTheme.style,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');
  AppLogger.logInfo('Starting app initialization');

  try {
    AppLogger.logInfo('Initializing Firebase...');
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    AppLogger.logInfo('Firebase initialized successfully');
  } catch (e) {
    AppLogger.logError(e);
    runApp(const ErrorApp(errorMessage: 'Failed to initialize Firebase'));
    return;
  }

  AppLogger.logInfo('Running MyApp');
  runApp(
    MultiProvider(
      providers: [
        // ModelProvider starts model download immediately (non-lazy)
        ChangeNotifierProvider(
          create: (_) => ModelProvider(
            variant: dotenv.env['GEMMA_MODEL_CONFIG'] ?? 'gemma3nGpu_2B',
          ),
          lazy: false,
        ),
        // Add the unified background service as a singleton
        ChangeNotifierProvider.value(value: UnifiedBackgroundService()),
        // AppAuthProvider waits for ModelProvider.isModelDownloaded
        appAuthProvider,
        // UserProvider waits for AppAuthProvider.user
        userProvider,
        // VehicleProvider waits for AppAuthProvider.user
        vehicleProvider,
        // BluetoothManager waits for AppAuthProvider.user
        bluetoothManagerProvider,
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.logInfo('Building MyApp');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Automotiq',
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const RootScreen(),
        '/home': (context) => const HomeScreen(),
        '/obdSetup': (context) => const ObdSetupScreen(),
      },
      onUnknownRoute: (settings) {
        AppLogger.logError('Unknown route: ${settings.name}');
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(child: Text('Route not found: ${settings.name}')),
          ),
        );
      },
    );
  }
}
