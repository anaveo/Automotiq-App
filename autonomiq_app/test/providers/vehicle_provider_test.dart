import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autonomiq_app/models/vehicle_model.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import '../mocks.mocks.dart';

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late MockUser mockUser;
  late MockVehicleRepository mockVehicleRepository;
  late VehicleProvider vehicleProvider;
  late StreamController<User?> authStateController;
  late Vehicle mockVehicle;

  setUpAll(() {
    authStateController = StreamController<User?>.broadcast();
  });

  tearDownAll(() {
    authStateController.close();
  });

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockVehicleRepository = MockVehicleRepository();
    mockVehicle = MockVehicle();
    when(mockFirebaseAuth.authStateChanges()).thenAnswer((_) => authStateController.stream);
    when(mockFirebaseAuth.currentUser).thenReturn(null);
    when(mockUser.uid).thenReturn('test-uid');
    vehicleProvider = VehicleProvider(
      vehicleRepository: mockVehicleRepository,
      firebaseAuth: mockFirebaseAuth,
    );
  });

  group('loadVehicles', () {
    test('loads vehicles for signed-in user', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockVehicleRepository.getVehicles('test-uid')).thenAnswer((_) async => [mockVehicle]);
      authStateController.add(mockUser); // Simulate signed-in user
      await Future.microtask(() {}); // Wait for stream processing

      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      await vehicleProvider.loadVehicles();
      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, [mockVehicle]);
      expect(vehicleProvider.selectedVehicle, mockVehicle);
      verify(mockVehicleRepository.getVehicles('test-uid')).called(1);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles no user signed in', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(null);
      authStateController.add(null); // Simulate no user
      await Future.microtask(() {}); // Wait for stream processing

      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      await expectLater(
        vehicleProvider.loadVehicles(),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', 'Bad state: No user is signed in')),
      );
      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      verifyNever(mockVehicleRepository.getVehicles(any));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles Firestore error', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockVehicleRepository.getVehicles('test-uid')).thenThrow(Exception('Firestore error'));
      authStateController.add(mockUser); // Simulate signed-in user
      await Future.microtask(() {}); // Wait for stream processing

      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      await expectLater(
        vehicleProvider.loadVehicles(),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', 'Exception: Firestore error')),
      );
      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      verify(mockVehicleRepository.getVehicles('test-uid')).called(1);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles empty vehicle list', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockVehicleRepository.getVehicles('test-uid')).thenAnswer((_) async => []);
      authStateController.add(mockUser); // Simulate signed-in user
      await Future.microtask(() {}); // Wait for stream processing

      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      await vehicleProvider.loadVehicles();
      expect(vehicleProvider.isLoading, false);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      verify(mockVehicleRepository.getVehicles('test-uid')).called(1);
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('selectVehicle', () {
    test('selects valid vehicle', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockVehicleRepository.getVehicles('test-uid')).thenAnswer((_) async => [mockVehicle]);
      authStateController.add(mockUser); // Simulate signed-in user
      await Future.microtask(() {}); // Wait for stream processing

      await vehicleProvider.loadVehicles();
      expect(vehicleProvider.vehicles, [mockVehicle]);
      expect(vehicleProvider.selectedVehicle, mockVehicle);

      vehicleProvider.selectVehicle(mockVehicle);
      expect(vehicleProvider.selectedVehicle, mockVehicle);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles invalid vehicle selection', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockVehicleRepository.getVehicles('test-uid')).thenAnswer((_) async => [mockVehicle]);
      authStateController.add(mockUser); // Simulate signed-in user
      await Future.microtask(() {}); // Wait for stream processing

      await vehicleProvider.loadVehicles();
      expect(vehicleProvider.vehicles, [mockVehicle]);
      expect(vehicleProvider.selectedVehicle, mockVehicle);

      final invalidVehicle = MockVehicle();
      vehicleProvider.selectVehicle(invalidVehicle);
      expect(vehicleProvider.selectedVehicle, mockVehicle); // Should not change
    }, timeout: Timeout(Duration(seconds: 5)));
  });
  group('addVehicle', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockVehicleRepository mockVehicleRepository;
    late VehicleProvider vehicleProvider;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockVehicleRepository = MockVehicleRepository();
      vehicleProvider = VehicleProvider(vehicleRepository: mockVehicleRepository, firebaseAuth: mockAuth);

      when(mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('testUserId');

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('testUserId');
    });

    test('adds vehicle successfully', () async {
      final vehicleData = {
        'name': 'New Car',
        'vin': 'VIN123',
        'year': 2021,
        'odometer': 15000,
        'isConnected': true,
      };
      when(mockVehicleRepository.addVehicle('testUserId', vehicleData)).thenAnswer((_) async => 'newVehicleId');

      await vehicleProvider.addVehicle(vehicleData);

      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.vehicles[0].id, 'newVehicleId');
      expect(vehicleProvider.vehicles[0].name, 'New Car');
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verify(mockVehicleRepository.addVehicle('testUserId', vehicleData)).called(1);
      expect(vehicleProvider.isLoading, false);
    });

    test('handles default values for missing fields', () async {
      final vehicleData = {'name': 'Minimal Car'};
      when(mockVehicleRepository.addVehicle('testUserId', vehicleData)).thenAnswer((_) async => 'minimalId');

      await vehicleProvider.addVehicle(vehicleData);

      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.vehicles[0].id, 'minimalId');
      expect(vehicleProvider.vehicles[0].name, 'Minimal Car');
      expect(vehicleProvider.vehicles[0].vin, 'Unknown');
      expect(vehicleProvider.vehicles[0].year, 0);
      expect(vehicleProvider.vehicles[0].odometer, 0);
      expect(vehicleProvider.vehicles[0].isConnected, false);
      expect(vehicleProvider.vehicles[0].diagnosticTroubleCodes, []);
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verify(mockVehicleRepository.addVehicle('testUserId', vehicleData)).called(1);
    });

    test('logs error and returns when no user signed in', () async {
      when(mockAuth.currentUser).thenReturn(null);
      final vehicleData = {'name': 'NoUserCar'};

      await vehicleProvider.addVehicle(vehicleData);

      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.isLoading, false);
      verifyNever(mockVehicleRepository.addVehicle(any, any));
    });

    test('throws and logs error on Firestore failure', () async {
      final vehicleData = {'name': 'FailingCar'};
      when(mockVehicleRepository.addVehicle('testUserId', vehicleData)).thenThrow(Exception('Firestore error'));

      expect(() => vehicleProvider.addVehicle(vehicleData), throwsException);
      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.isLoading, false);
      verify(mockVehicleRepository.addVehicle('testUserId', vehicleData)).called(1);
    });
  });

  group('removeVehicle', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late VehicleProvider vehicleProvider;
    const testVehicleId = 'testVehicleId';

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockVehicleRepository = MockVehicleRepository();
      vehicleProvider = VehicleProvider(vehicleRepository: mockVehicleRepository, firebaseAuth: mockAuth);

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('testUserId');

      // Pre-populate vehicles using addVehicle mock
      final initialVehicle = {'name': 'Initial Car', 'vin': 'VIN000'};
      when(mockVehicleRepository.addVehicle('testUserId', initialVehicle)).thenAnswer((_) async => testVehicleId);
      vehicleProvider.addVehicle(initialVehicle); // Sets initial state
    });

    test('removes vehicle successfully', () async {
      when(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).thenAnswer((_) async {});

      await vehicleProvider.removeVehicle(testVehicleId);

      expect(vehicleProvider.vehicles, isEmpty);
      expect(vehicleProvider.selectedVehicle, isNull);
      verify(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).called(1);
      expect(vehicleProvider.isLoading, false);
    });

    test('updates selected to first vehicle if multiple exist', () async {
      // Add second vehicle to test selection update
      final secondVehicleData = {'name': 'Second Car', 'vin': 'VIN001'};
      when(mockVehicleRepository.addVehicle('testUserId', secondVehicleData)).thenAnswer((_) async => 'id2');
      await vehicleProvider.addVehicle(secondVehicleData);
      expect(vehicleProvider.vehicles.length, 2);
      // Set selected to second vehicle
      vehicleProvider.selectVehicle(vehicleProvider.vehicles[1]);

      when(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).thenAnswer((_) async {});

      await vehicleProvider.removeVehicle(testVehicleId);

      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.vehicles[0].id, 'id2');
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verify(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).called(1);
      expect(vehicleProvider.isLoading, false);
    });

    test('logs error and returns when no user signed in', () async {
      when(mockAuth.currentUser).thenReturn(null);

      await vehicleProvider.removeVehicle(testVehicleId);

      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verifyNever(mockVehicleRepository.removeVehicle(any, any));
      expect(vehicleProvider.isLoading, false);
    });

    test('throws and logs error on Firestore failure', () async {
      when(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).thenThrow(Exception('Firestore error'));

      expect(() => vehicleProvider.removeVehicle(testVehicleId), throwsException);
      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verify(mockVehicleRepository.removeVehicle('testUserId', testVehicleId)).called(1);
      expect(vehicleProvider.isLoading, false);
    });

    test('handles non-existent vehicleId', () async {
      when(mockVehicleRepository.removeVehicle('testUserId', 'nonExistentId')).thenThrow(ArgumentError('Vehicle not found'));

      expect(() => vehicleProvider.removeVehicle('nonExistentId'), throwsArgumentError);
      expect(vehicleProvider.vehicles.length, 1);
      expect(vehicleProvider.selectedVehicle, vehicleProvider.vehicles[0]);
      verify(mockVehicleRepository.removeVehicle('testUserId', 'nonExistentId')).called(1);
      expect(vehicleProvider.isLoading, false);
    });
  });
}