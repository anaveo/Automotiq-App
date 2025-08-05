import 'package:automotiq_app/models/vehicle_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:automotiq_app/repositories/vehicle_repository.dart';
import '../mocks.mocks.dart';

void main() {
  late VehicleRepository repository;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference<Map<String, dynamic>> mockCollection;
  late MockDocumentReference<Map<String, dynamic>> mockDocument;
  late MockQuerySnapshot<Map<String, dynamic>> mockSnapshot;
  late MockQueryDocumentSnapshot<Map<String, dynamic>> mockDocSnapshot;

  const testUserId = 'testUserId';
  const testVehicleId = 'vehicleId';

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference<Map<String, dynamic>>();
    mockDocument = MockDocumentReference<Map<String, dynamic>>();
    mockSnapshot = MockQuerySnapshot<Map<String, dynamic>>();
    mockDocSnapshot = MockQueryDocumentSnapshot<Map<String, dynamic>>();

    repository = VehicleRepository(firestoreInstance: mockFirestore);

    when(mockFirestore.collection('users')).thenReturn(mockCollection);
    when(mockCollection.doc(testUserId)).thenReturn(mockDocument);
    when(mockDocument.collection('vehicles')).thenReturn(mockCollection);
  });
  group('getVehicles', () {
    test('returns list of vehicles', () async {
      when(mockCollection.get()).thenAnswer((_) async => mockSnapshot);
      when(mockSnapshot.docs).thenReturn([mockDocSnapshot]);
      when(mockDocSnapshot.id).thenReturn('vehicle1');
      when(mockDocSnapshot.data()).thenReturn({
        'deviceId': 'OBD-II Device',
        'name': 'Car 1',
        'vin': '1HGCM82633A004352',
        'year': 2020,
        'odometer': 50000,
        'diagnosticTroubleCodes': [],
      });

      final vehicles = await repository.getVehicles(testUserId);

      expect(vehicles.length, 1);
      expect(vehicles[0].deviceId, 'OBD-II Device');
      expect(vehicles[0].id, 'vehicle1');
      expect(vehicles[0].name, 'Car 1');
      expect(vehicles[0].vin, '1HGCM82633A004352');
      expect(vehicles[0].year, 2020);
      expect(vehicles[0].odometer, 50000);
      expect(vehicles[0].diagnosticTroubleCodes, []);
    });

    test('throws on empty UID', () async {
      expect(() => repository.getVehicles(''), throwsArgumentError);
    });
  });

  group('addVehicle', () {
    test('adds vehicle successfully and returns new ID', () async {
      when(mockCollection.add(any)).thenAnswer((_) async => mockDocument);
      when(mockDocument.id).thenReturn('newVehicleId');

      final vehicleData = {
        'deviceId': 'Test Device',
        'name': 'Test Vehicle',
        'vin': 'VIN123',
        'year': 2020,
        'odometer': 10000,
      };

      final vehicle = VehicleObject.fromMap(testVehicleId, vehicleData);
      final result = await repository.addVehicle(testUserId, vehicle);
      expect(result, 'newVehicleId');

      // Use content match instead of instance match
      verify(mockCollection.add(argThat(equals(vehicle.toMap())))).called(1);
    });

    test('does not mutate original input map', () async {
      final originalMap = {'deviceId': 'test device'};
      final inputCopy = Map<String, dynamic>.from(originalMap);

      when(mockCollection.add(any)).thenAnswer((_) async => mockDocument);
      when(mockDocument.id).thenReturn('vehicleId');

      await repository.addVehicle(
        testUserId,
        VehicleObject.fromMap(testVehicleId, inputCopy),
      );
      expect(inputCopy, originalMap);
    });

    test('throws on empty userId', () async {
      expect(
        () => repository.addVehicle(
          '',
          VehicleObject.fromMap(testVehicleId, {'name': 'Test Vehicle'}),
        ),
        throwsArgumentError,
      );
    });

    test('throws on missing or empty deviceId', () async {
      expect(
        () => repository.addVehicle(
          testUserId,
          VehicleObject.fromMap(testVehicleId, {'vin': 'VIN123'}),
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.addVehicle(
          testUserId,
          VehicleObject.fromMap(testVehicleId, {
            'deviceId': '',
            'vin': 'VIN123',
          }),
        ),
        throwsArgumentError,
      );
    });

    test('throws on Firestore failure', () async {
      when(mockCollection.add(any)).thenThrow(Exception('Firestore error'));
      expect(
        () => repository.addVehicle(
          testUserId,
          VehicleObject.fromMap(testVehicleId, {'deviceId': 'test device'}),
        ),
        throwsException,
      );
      verify(mockCollection.add(any)).called(1);
    });
  });

  group('removeVehicle', () {
    test('removes vehicle successfully', () async {
      when(mockCollection.doc(testVehicleId)).thenReturn(mockDocument);
      when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
      when(mockDocSnapshot.exists).thenReturn(true);
      when(mockDocument.delete()).thenAnswer((_) async {});

      await repository.removeVehicle(testUserId, testVehicleId);

      verify(mockCollection.doc(testVehicleId)).called(1);
      verify(mockDocument.get()).called(1);
      verify(mockDocument.delete()).called(1);
    });

    test('throws on empty userId', () async {
      expect(
        () => repository.removeVehicle('', testVehicleId),
        throwsArgumentError,
      );
    });

    test('throws on empty vehicleId', () async {
      expect(
        () => repository.removeVehicle(testUserId, ''),
        throwsArgumentError,
      );
    });

    test('throws on non-existent vehicleId', () async {
      when(mockCollection.doc(testVehicleId)).thenReturn(mockDocument);
      when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
      when(mockDocSnapshot.exists).thenReturn(false);

      expect(
        () => repository.removeVehicle(testUserId, testVehicleId),
        throwsArgumentError,
      );

      verify(mockCollection.doc(testVehicleId)).called(1);
      verify(mockDocument.get()).called(1);
      verifyNever(mockDocument.delete());
    });

    test('throws on Firestore failure', () async {
      when(mockCollection.doc(testVehicleId)).thenReturn(mockDocument);
      when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
      when(mockDocSnapshot.exists).thenReturn(true);
      when(mockDocument.delete()).thenThrow(Exception('Firestore error'));

      expect(
        () => repository.removeVehicle(testUserId, testVehicleId),
        throwsException,
      );

      verify(mockCollection.doc(testVehicleId)).called(1);
      verify(mockDocument.get()).called(1);
    });
  });
}
