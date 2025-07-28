import 'package:automotiq_app/providers/auth_provider.dart';
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
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelProvider>(
      builder: (context, modelProvider, child) {
        // Show splash screen during model download
        if (modelProvider.isModelDownloading || !modelProvider.isModelDownloaded) {
          return const SplashScreen();
        }

        // Show error screen if download fails
        if (modelProvider.downloadError != null) {
          return ErrorApp(errorMessage: modelProvider.downloadError!);
        }

        // Proceed to auth when model is downloaded
        return MultiProvider(
          providers: [
            appAuthProvider,
            userProvider,
            vehicleProvider,
            bluetoothManagerProvider,
          ],
          child: Consumer<AppAuthProvider>(
            builder: (context, authProvider, child) {
              // Diagnostic logging
              AppLogger.logInfo(
                'RootScreen state: authProvider.user=${authProvider.user?.uid}, '
                'isModelInitialized=${modelProvider.isModelInitialized}, '
                'isChatInitialized=${modelProvider.isChatInitialized}, '
                'userProvider=${Provider.of<UserProvider>(context) != null}, '
                'userProvider.user=${Provider.of<UserProvider>(context).user != null}',
                'RootScreen',
              );
              // Show loader during auth, model init, chat init, or user loading
              if (authProvider.isLoading ||
                  modelProvider.isModelInitializing ||
                  modelProvider.isChatInitializing ||
                  Provider.of<UserProvider>(context).isLoading) {
                return const LoaderScreen();
              }
              // Show error screen if auth or init fails
              if (authProvider.authError != null) {
                return ErrorApp(errorMessage: authProvider.authError!);
              }
              if (modelProvider.initializeError != null) {
                return ErrorApp(errorMessage: modelProvider.initializeError!);
              }
              // Access UserProvider
              final userProvider = Provider.of<UserProvider>(context);
              // Show home screen if fully initialized
              if (authProvider.user != null &&
                  modelProvider.isModelInitialized &&
                  modelProvider.isChatInitialized &&
                  userProvider.user != null) {
                return const HomeScreen();
              }
              // Default to login screen
              return const LoginScreen();
            },
          ),
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
                  Provider.of<ModelProvider>(context, listen: false).startModelDownload();
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
  AppLogger.logInfo('Starting app initialization', 'main');

  try {
    AppLogger.logInfo('Initializing Firebase...', 'main');
    await Firebase.initializeApp();
    AppLogger.logInfo('Firebase initialized successfully', 'main');
  } catch (e, stackTrace) {
    AppLogger.logError(e, stackTrace, 'main');
    runApp(const ErrorApp(errorMessage: 'Failed to initialize Firebase'));
    return;
  }

  AppLogger.logInfo('Running MyApp', 'main');
  runApp(
    ChangeNotifierProvider(
      create: (_) => ModelProvider(
        variant: dotenv.env['GEMMA_MODEL_CONFIG'] ?? 'gemma3nGpu_2B',
      ),
      lazy: false,
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