import 'package:automotiq_app/objects/user_object.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:automotiq_app/repositories/user_repository.dart';
import '../mocks.mocks.dart';

void main() {
  late UserRepository repository;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference<Map<String, dynamic>> mockUsers;
  late MockDocumentReference<Map<String, dynamic>> mockUserDoc;
  late MockDocumentSnapshot<Map<String, dynamic>> mockUserSnapshot;

  const testUserId = 'testUserId';

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockUsers = MockCollectionReference<Map<String, dynamic>>();
    mockUserDoc = MockDocumentReference<Map<String, dynamic>>();
    mockUserSnapshot = MockDocumentSnapshot<Map<String, dynamic>>();

    repository = UserRepository(firestoreInstance: mockFirestore);

    when(mockFirestore.collection('users')).thenReturn(mockUsers);
    when(mockUsers.doc(testUserId)).thenReturn(mockUserDoc);
  });

  group('createUserIfNotExists', () {
    test('creates new user if user document does not exist', () async {
      when(mockUserDoc.get()).thenAnswer((_) async => mockUserSnapshot);
      when(mockUserSnapshot.exists).thenReturn(false);
      when(mockUserDoc.set(any)).thenAnswer((_) async => {});

      await repository.createUserDocIfNotExists(
        testUserId,
        UserObject(uid: testUserId),
      );

      verify(mockUserDoc.get()).called(1);
      verify(mockUserDoc.set(argThat(contains('createdAt')))).called(1);
    });

    test('does not overwrite existing user document', () async {
      when(mockUserDoc.get()).thenAnswer((_) async => mockUserSnapshot);
      when(mockUserSnapshot.exists).thenReturn(true);

      await repository.createUserDocIfNotExists(
        testUserId,
        UserObject(uid: testUserId),
      );

      verify(mockUserDoc.get()).called(1);
      verifyNever(mockUserDoc.set(any));
    });

    test('throws if userId is empty', () async {
      expect(
        () => repository.createUserDocIfNotExists('', UserObject(uid: '')),
        throwsArgumentError,
      );
      verifyNever(mockUserDoc.get());
    });

    test('throws on Firestore error', () async {
      when(mockUserDoc.get()).thenThrow(Exception('Firestore read error'));

      expect(
        () => repository.createUserDocIfNotExists(
          testUserId,
          UserObject(uid: testUserId),
        ),
        throwsException,
      );

      verify(mockUserDoc.get()).called(1);
    });
  });
}
