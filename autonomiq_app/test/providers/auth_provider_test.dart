import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import '../mocks.mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockFirebaseAuth mockFirebaseAuth;
  late MockUser mockUser;
  late MockUserCredential mockUserCredential;
  late AppAuthProvider authProvider;
  late StreamController<User?> authStateController;

  setUpAll(() {
    authStateController = StreamController<User?>.broadcast();
  });

  tearDownAll(() {
    authStateController.close();
  });

  setUp(() {
    mockAuthService = MockAuthService();
    mockFirebaseAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockUserCredential = MockUserCredential();
    when(mockFirebaseAuth.authStateChanges()).thenAnswer((_) => authStateController.stream);
    authStateController.add(null); // Initial state: no user
    authProvider = AppAuthProvider(
      authService: mockAuthService,
      firebaseAuth: mockFirebaseAuth,
    );
    when(mockFirebaseAuth.currentUser).thenReturn(null); // Initial state: no user
  });

  group('signInAnonymously', () {
    test('updates user and loading state on success', () async {
      when(mockAuthService.signInAnonymously())
          .thenAnswer((_) async => mockUserCredential);
      when(mockUserCredential.user).thenReturn(mockUser);
      when(mockUser.isAnonymous).thenReturn(true);

      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
      await authProvider.signInAnonymously();
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      expect(authProvider.user?.isAnonymous, true);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles network error', () async {
      when(mockAuthService.signInAnonymously())
          .thenThrow(FirebaseAuthException(code: 'network-error'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInAnonymously(),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'network-error')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles already signed-in user', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockUser.isAnonymous).thenReturn(true);
      authStateController.add(mockUser); // Simulate existing user
      await Future.microtask(() {}); // Wait for stream processing

      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser); // Verify user is set
      await authProvider.signInAnonymously();
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      verifyNever(mockAuthService.signInAnonymously()); // No call if already signed in
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('signInWithEmail', () {
    test('updates user and loading state on success', () async {
      when(mockAuthService.signInWithEmailAndPassword('test@example.com', 'password123'))
          .thenAnswer((_) async => mockUserCredential);
      when(mockUserCredential.user).thenReturn(mockUser);
      when(mockUser.isAnonymous).thenReturn(false);

      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
      await authProvider.signInWithEmail('test@example.com', 'password123');
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      expect(authProvider.user?.isAnonymous, false);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles invalid-email error', () async {
      when(mockAuthService.signInWithEmailAndPassword('invalid-email', 'password123'))
          .thenThrow(FirebaseAuthException(code: 'invalid-email'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('invalid-email', 'password123'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'invalid-email')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles wrong-password error', () async {
      when(mockAuthService.signInWithEmailAndPassword('test@example.com', 'wrong'))
          .thenThrow(FirebaseAuthException(code: 'wrong-password'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('test@example.com', 'wrong'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'wrong-password')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles user-not-found error', () async {
      when(mockAuthService.signInWithEmailAndPassword('unknown@example.com', 'password123'))
          .thenThrow(FirebaseAuthException(code: 'user-not-found'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('unknown@example.com', 'password123'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'user-not-found')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles network error', () async {
      when(mockAuthService.signInWithEmailAndPassword('test@example.com', 'password123'))
          .thenThrow(FirebaseAuthException(code: 'network-error'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('test@example.com', 'password123'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'network-error')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('throws ArgumentError on empty email', () async {
      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('', 'password123'),
        throwsA(isA<ArgumentError>()),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
      verifyNever(mockAuthService.signInWithEmailAndPassword(any, any));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('throws ArgumentError on empty password', () async {
      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.signInWithEmail('test@example.com', ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
      verifyNever(mockAuthService.signInWithEmailAndPassword(any, any));
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('linkAnonymousToEmail', () {
    setUp(() async {
      // Ensure mockUser is set before instantiating authProvider
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockUser.isAnonymous).thenReturn(true);
      authStateController.add(mockUser); // Simulate anonymous user
      // Wait for authStateChanges stream to process
      await Future.microtask(() {});
    });

    test('successfully links anonymous user to email', () async {
      when(mockUser.linkWithCredential(any)).thenAnswer((_) async => mockUserCredential);
      when(mockUserCredential.user).thenReturn(mockUser);

      expect(authProvider.isLoading, false);
      await authProvider.linkAnonymousToEmail('test@example.com', 'password123');
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      verify(mockUser.linkWithCredential(any)).called(1);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('fails if user is not anonymous', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(mockUser);
      when(mockUser.isAnonymous).thenReturn(false);
      authStateController.add(mockUser); // Simulate non-anonymous user
      await Future.microtask(() {}); // Wait for stream processing

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('test@example.com', 'password123'),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', 'Bad state: Current user is not anonymous')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      verifyNever(mockUser.linkWithCredential(any));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles invalid-email error', () async {
      when(mockUser.linkWithCredential(any))
          .thenThrow(FirebaseAuthException(code: 'invalid-email'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('invalid-email', 'password123'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'invalid-email')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles weak-password error', () async {
      when(mockUser.linkWithCredential(any))
          .thenThrow(FirebaseAuthException(code: 'weak-password'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('test@example.com', 'weak'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'weak-password')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles email-already-in-use error', () async {
      when(mockUser.linkWithCredential(any))
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('test@example.com', 'password123'),
        throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'email-already-in-use')),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('handles null user', () async {
      when(mockFirebaseAuth.currentUser).thenReturn(null);
      authStateController.add(null); // Simulate no user
      await Future.microtask(() {}); // Wait for stream processing

      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('test@example.com', 'password123'),
        throwsA(isA<StateError>()),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, null);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('throws ArgumentError on empty email', () async {
      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('', 'password123'),
        throwsA(isA<ArgumentError>()),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      verifyNever(mockUser.linkWithCredential(any));
    }, timeout: Timeout(Duration(seconds: 5)));

    test('throws ArgumentError on empty password', () async {
      expect(authProvider.isLoading, false);
      await expectLater(
        authProvider.linkAnonymousToEmail('test@example.com', ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(authProvider.isLoading, false);
      expect(authProvider.user, mockUser);
      verifyNever(mockUser.linkWithCredential(any));
    }, timeout: Timeout(Duration(seconds: 5)));
  });
}