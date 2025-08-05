import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:automotiq_app/objects/user_object.dart';
import 'package:automotiq_app/providers/user_provider.dart';

import '../mocks.mocks.dart'; // Make sure mock classes are generated properly

void main() {
  late MockUserRepository mockUserRepository;
  late UserProvider userProvider;
  late UserObject testUser;

  setUp(() {
    mockUserRepository = MockUserRepository();

    testUser = UserObject(
      uid: 'test-uid',
      email: 'test@example.com',
      createdAt: DateTime.now(),
    );

    userProvider = UserProvider(
      repository: mockUserRepository,
      uid: 'test-uid',
    );
  });

  group('UserProvider.loadUserProfile', () {
    test('loads user profile successfully', () async {
      when(
        mockUserRepository.getUser('test-uid'),
      ).thenAnswer((_) async => testUser);

      await userProvider.loadUserProfile();

      expect(userProvider.isLoading, false);
      expect(userProvider.user, equals(testUser));
    });

    test('handles error and sets user to null', () async {
      when(
        mockUserRepository.getUser('test-uid'),
      ).thenThrow(Exception('Firestore error'));

      await userProvider.loadUserProfile();

      expect(userProvider.user, isNull);
      expect(userProvider.isLoading, false);
    });
  });
}
