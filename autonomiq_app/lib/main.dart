import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:autonomiq_app/utils/firebase_options.dart';
import 'package:autonomiq_app/utils/logger.dart';
import 'package:autonomiq_app/providers/providers.dart';

// Screens
import 'package:autonomiq_app/screens/home_screen.dart';
import 'package:autonomiq_app/screens/splash_screen.dart';
import 'package:autonomiq_app/screens/login_screen.dart';
import 'package:autonomiq_app/screens/obd_setup_screen.dart';


class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppAuthProvider>(context);
    if (authProvider.isLoading) {
      return const SplashScreen();
    }
    final user = authProvider.user;
    return user != null ? const HomeScreen() : const LoginScreen();
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

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
      home: const Scaffold(
        body: Center(
          child: Text('Failed to initialize app. Please try again.'),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppLogger.logInfo('Initializing Firebase...', 'main');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.logInfo('Firebase initialized successfully', 'main');
  } catch (e, stackTrace) {
    AppLogger.logError(e, stackTrace, 'main');
    runApp(const ErrorApp());
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        userRepositoryProvider,
        appAuthProvider,
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
    return MaterialApp(
      title: 'Autonomiq',
      // TODO: move to a separate theme file
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
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => Scaffold(
          body: Center(
            child: Text('Route not found: ${settings.name}'),
          ),
        ),
      ),
    );
  }
}