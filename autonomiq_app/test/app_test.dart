import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:autonomiq_app/app.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import 'package:autonomiq_app/screens/home_screen.dart';
import 'package:autonomiq_app/screens/login_screen.dart';
import 'package:autonomiq_app/screens/splash_screen.dart';
import 'mocks.mocks.dart';

void main() {
  late MockAppAuthProvider mockAuthProvider;
  late MockVehicleProvider mockVehicleProvider;
  late MockUser mockUser;

  setUp(() {
    mockAuthProvider = MockAppAuthProvider();
    mockVehicleProvider = MockVehicleProvider();
    mockUser = MockUser();
    // Stub VehicleProvider methods to avoid null issues
    when(mockVehicleProvider.isLoading).thenReturn(false);
    when(mockVehicleProvider.vehicles).thenReturn([]);
    when(mockVehicleProvider.selectedVehicle).thenReturn(null);
  });

  testWidgets('routes to HomeScreen for authenticated user', (WidgetTester tester) async {
    when(mockAuthProvider.isLoading).thenReturn(false);
    when(mockAuthProvider.user).thenReturn(mockUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppAuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VehicleProvider>.value(value: mockVehicleProvider),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('routes to LoginScreen for no user', (WidgetTester tester) async {
    when(mockAuthProvider.isLoading).thenReturn(false);
    when(mockAuthProvider.user).thenReturn(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppAuthProvider>.value(value: mockAuthProvider),
          ChangeNotifierProvider<VehicleProvider>.value(value: mockVehicleProvider),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}