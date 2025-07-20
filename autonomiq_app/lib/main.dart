import 'package:autonomiq_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:autonomiq_app/utils/firebase_options.dart';
import 'package:autonomiq_app/utils/logger.dart';
import 'package:autonomiq_app/providers/providers.dart';
import 'package:autonomiq_app/screens/home_screen.dart';
import 'package:autonomiq_app/screens/splash_screen.dart';
import 'package:autonomiq_app/screens/login_screen.dart';
import 'package:autonomiq_app/screens/new_device_setup_screen.dart';

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
      final authProvider = Provider.of<AppAuthProvider>(context, listen: false);
      if (authProvider.user == null && !authProvider.isLoading) {
        try {
          AppLogger.logInfo('Attempting anonymous login', 'RootScreen.initState');
          await authProvider.signInAnonymously();
          AppLogger.logInfo(
            'Anonymous login successful, user: ${authProvider.user?.uid} (anonymous: ${authProvider.user?.isAnonymous})',
            'RootScreen.initState',
          );
          // Trigger UserProvider initialization
          final userProvider = Provider.of<UserProvider?>(context, listen: false);
          if (userProvider != null && userProvider.isLoading) {
            AppLogger.logInfo('Waiting for UserProvider to load user profile', 'RootScreen.initState');
            await Future.delayed(const Duration(milliseconds: 100)); // Small delay to ensure provider initialization
          }
        } catch (e, stackTrace) {
          AppLogger.logError(e, stackTrace, 'RootScreen.initState');
          setState(() => _errorMessage = 'Authentication failed: $e');
        }
      } else if (authProvider.user != null) {
        AppLogger.logInfo(
          'User already authenticated: ${authProvider.user!.uid} (anonymous: ${authProvider.user!.isAnonymous})',
          'RootScreen.initState',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppAuthProvider>(context);
    final userProvider = Provider.of<UserProvider?>(context);
    if (authProvider.isLoading || (userProvider != null && userProvider.isLoading)) {
      return const SplashScreen();
    }
    if (_errorMessage != null || authProvider.authError != null) {
      return ErrorApp(errorMessage: _errorMessage ?? authProvider.authError!);
    }
    if (authProvider.user != null && userProvider != null && userProvider.user != null) {
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
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
      ),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  AppLogger.logInfo('Retrying app initialization', 'ErrorApp');
                  Navigator.pushReplacementNamed(context, '/');
                },
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
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.logInfo('Starting app initialization', 'main');
  try {
    AppLogger.logInfo('Initializing Firebase...', 'main');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
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
      title: 'Autonomiq',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
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