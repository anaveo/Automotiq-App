import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autonomiq_app/services/auth_service.dart';
import '../mocks.mocks.dart';

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late MockUser mockUser;
  late MockUserCredential mockUserCredential;
  late AuthService authService;

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockUserCredential = MockUserCredential();
    authService = AuthService(firebaseAuth: mockFirebaseAuth);
  });

  test('signInAnonymously returns UserCredential', () async {
    when(mockFirebaseAuth.signInAnonymously())
        .thenAnswer((_) async => mockUserCredential);
    when(mockUserCredential.user).thenReturn(mockUser);
    when(mockUser.isAnonymous).thenReturn(true);

    final result = await authService.signInAnonymously();
    expect(result.user, mockUser);
    expect(result.user?.isAnonymous, true);
  });

  test('signInAnonymously handles error', () async {
    when(mockFirebaseAuth.signInAnonymously())
        .thenThrow(FirebaseAuthException(code: 'network-error'));

    expect(() => authService.signInAnonymously(), throwsA(isA<FirebaseAuthException>()));
  });

  test('getCurrentUser returns user', () {
    when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
    expect(authService.getCurrentUser(), mockUser);
  });
}
