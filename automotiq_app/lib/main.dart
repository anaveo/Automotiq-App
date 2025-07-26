import 'package:automotiq_app/providers/user_provider.dart';
import 'package:automotiq_app/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:automotiq_app/providers/providers.dart';
import 'package:automotiq_app/screens/home_screen.dart';
import 'package:automotiq_app/screens/splash_screen.dart';
import 'package:automotiq_app/screens/login_screen.dart';
import 'package:automotiq_app/screens/new_device_setup_screen.dart';
import 'package:automotiq_app/providers/model_download_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final modelDownloadProvider = Provider.of<ModelDownloadProvider>(context, listen: false);
      final authProvider = Provider.of<AppAuthProvider>(context, listen: false);

      // Provider initialization flow:
      // [Model] -> [Auth] -> [User & Vehicle & Bluetooth]
      //
      // Downstream providers are set to initialize lazily to ensure no 
      // services are set up if their upstream components have failed
            
      // Check if model is downloaded or downloading
      if (!modelDownloadProvider.isModelDownloaded && !modelDownloadProvider.isDownloading) {
        try {
          AppLogger.logInfo('Starting model download', 'RootScreen.initState');
          await modelDownloadProvider.initializeModel();
          AppLogger.logInfo('Model initialization completed', 'RootScreen.initState');
        } catch (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'RootScreen.initState');
          setState(() => _errorMessage = 'Model initialization failed: $e');
          return;
        }
      }

      // Log authentication status
      if (authProvider.user != null) {
        AppLogger.logInfo(
          'User already authenticated: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
          'RootScreen.initState',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelProvider = Provider.of<ModelDownloadProvider>(context);
    final authProvider = Provider.of<AppAuthProvider>(context);
    final userProvider = Provider.of<UserProvider?>(context);

    if (modelProvider.isDownloading ||
        authProvider.isLoading ||
        (userProvider != null && userProvider.isLoading)) {
      return const SplashScreen();
    }
    if (_errorMessage != null || modelProvider.downloadError != null || authProvider.authError != null) {
      return ErrorApp(
        errorMessage: _errorMessage ?? modelProvider.downloadError ?? authProvider.authError!,
      );
    }
    if (modelProvider.isModelDownloaded &&
        authProvider.user != null &&
        userProvider != null &&
        userProvider.user != null) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
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
                  AppLogger.logInfo('Retrying app initialization', 'ErrorApp');
                  Navigator.pushReplacementNamed(context, '/');
                },
                style: Theme.of(context).elevatedButtonTheme.style,
                child: const Text(
                  'Retry',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() async {
  await dotenv.load(fileName: 'assets/.env');
  
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.logInfo('Starting app initialization', 'main');
  try {
    AppLogger.logInfo('Initializing Firebase...', 'main');
    await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: dotenv.get('FIRESTORE_API_KEY'),
          authDomain: dotenv.get('FIREBASE_AUTH_DOMAIN'),
          projectId: dotenv.get('FIREBASE_PROJECT_ID'),
          storageBucket: dotenv.get('FIREBASE_STORAGE_BUCKET'),
          messagingSenderId: dotenv.get('FIREBASE_MESSAGING_SENDER_ID'),
          appId: dotenv.get('FIREBASE_APP_ID'),
        ),
      );
    AppLogger.logInfo('Firebase initialized successfully', 'main');
  } catch (e, stackTrace) {
    AppLogger.logError(e, stackTrace, 'main');
    AppLogger.logInfo('Running ErrorApp due to Firebase initialization failure', 'main');
    runApp(const ErrorApp(errorMessage: 'Failed to initialize Firebase'));
    return;
  }

  AppLogger.logInfo('Initializing providers and running MyApp', 'main');
  runApp(
    MultiProvider(
      providers: [
        modelDownloadProvider,
        appAuthProvider,
        userProvider,
        vehicleProvider,
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
    AppLogger.logInfo('Building MyApp', 'main');
    return MaterialApp(
      title: 'Automotiq',
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const RootScreen(),
        '/home': (context) => const HomeScreen(),
        '/obdSetup': (context) => const ObdSetupScreen(),
      },
      onUnknownRoute: (settings) {
        AppLogger.logError('Unknown route: ${settings.name}', null, 'MyApp');
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(
              child: Text('Route not found: ${settings.name}'),
            ),
          ),
        );
      },
    );
  }
}