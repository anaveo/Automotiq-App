import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/add_vehicle_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return MaterialApp(
      title: 'Torque Clone',
      theme: ThemeData.dark(),

      // Use named routes
      initialRoute: '/',
      routes: {
        '/': (context) => authProvider.isLoading
            ? const SplashScreen()
            : authProvider.user == null
                ? const SplashScreen() // can be LoginScreen later
                : const HomeScreen(),

        '/addVehicle': (context) => AddVehiclePage(),
      },
    );
  }
}
