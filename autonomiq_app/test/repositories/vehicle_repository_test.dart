import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:autonomiq_app/repositories/vehicle_repository.dart';
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
        'name': 'Car 1',
        'vin': '1HGCM82633A004352',
        'year': 2020,
        'odometer': 50000,
        'isConnected': false,
      });

      final vehicles = await repository.getVehicles(testUserId);

      expect(vehicles.length, 1);
      expect(vehicles[0].id, 'vehicle1');
      expect(vehicles[0].name, 'Car 1');
      expect(vehicles[0].vin, '1HGCM82633A004352');
      expect(vehicles[0].year, 2020);
      expect(vehicles[0].odometer, 50000);
      expect(vehicles[0].isConnected, false);
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
        'name': 'Test Vehicle',
        'vin': 'VIN123',
        'year': 2020,
        'odometer': 10000,
        'isConnected': true,
      };

      final result = await repository.addVehicle(testUserId, vehicleData);
      expect(result, 'newVehicleId');
      verify(mockCollection.add(vehicleData)).called(1);
    });

    test('trims name before saving', () async {
      when(mockCollection.add(any)).thenAnswer((invocation) async {
        final addedData = invocation.positionalArguments[0] as Map<String, dynamic>;
        expect(addedData['name'], 'TrimmedName');
        return mockDocument;
      });
      when(mockDocument.id).thenReturn('vehicleId');

      final result = await repository.addVehicle(testUserId, {
        'name': '  TrimmedName  ',
        'vin': 'VIN456',
      });
      expect(result, 'vehicleId');
    });

    test('does not mutate original input map', () async {
      final originalMap = {'name': 'UnchangedName', 'vin': 'VIN789'};
      final inputCopy = Map<String, dynamic>.from(originalMap);

      when(mockCollection.add(any)).thenAnswer((_) async => mockDocument);
      when(mockDocument.id).thenReturn('vehicleId');

      await repository.addVehicle(testUserId, inputCopy);
      expect(inputCopy, originalMap);
    });

    test('throws on empty userId', () async {
      expect(() => repository.addVehicle('', {'name': 'Test Vehicle'}), throwsArgumentError);
    });

    test('throws on missing or empty name', () async {
      expect(() => repository.addVehicle(testUserId, {'vin': 'VIN123'}), throwsArgumentError);
      expect(() => repository.addVehicle(testUserId, {'name': '', 'vin': 'VIN123'}), throwsArgumentError);
    });

    test('throws on Firestore failure', () async {
      when(mockCollection.add(any)).thenThrow(Exception('Firestore error'));
      expect(() => repository.addVehicle(testUserId, {'name': 'Failing Vehicle', 'vin': 'VIN000'}), throwsException);
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
      expect(() => repository.removeVehicle('', testVehicleId), throwsArgumentError);
    });

    test('throws on empty vehicleId', () async {
      expect(() => repository.removeVehicle(testUserId, ''), throwsArgumentError);
    });

    test('throws on non-existent vehicleId', () async {
      when(mockCollection.doc(testVehicleId)).thenReturn(mockDocument);
      when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
      when(mockDocSnapshot.exists).thenReturn(false);

      expect(() => repository.removeVehicle(testUserId, testVehicleId), throwsArgumentError);

      verify(mockCollection.doc(testVehicleId)).called(1);
      verify(mockDocument.get()).called(1);
      verifyNever(mockDocument.delete());
    });

    test('throws on Firestore failure', () async {
      when(mockCollection.doc(testVehicleId)).thenReturn(mockDocument);
      when(mockDocument.get()).thenAnswer((_) async => mockDocSnapshot);
      when(mockDocSnapshot.exists).thenReturn(true);
      when(mockDocument.delete()).thenThrow(Exception('Firestore error'));

      expect(() => repository.removeVehicle(testUserId, testVehicleId), throwsException);

      verify(mockCollection.doc(testVehicleId)).called(1);
      verify(mockDocument.get()).called(1);
    });
  });
}