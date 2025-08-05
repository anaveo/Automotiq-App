import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';

/// Manages authentication state and interactions with Firebase Authentication.
class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final FirebaseAuth _firebaseAuth;
  User? _user;

  /// Indicates if an authentication operation is in progress.
  bool _isLoading = false;

  /// Stores any authentication error message.
  String? _authError;

  /// Gets the current authenticated user, or null if not signed in.
  User? get user => _user;

  /// Gets the loading state.
  bool get isLoading => _isLoading;

  /// Gets the authentication error, if any.
  String? get authError => _authError;

  /// Gets the FirebaseAuth instance.
  FirebaseAuth get firebaseAuth => _firebaseAuth;

  /// Constructor for AppAuthProvider.
  ///
  /// [authService] handles authentication operations (optional for dependency injection).
  /// [firebaseAuth] is required for Firebase Authentication.
  /// Listens to auth state changes to update [_user].
  AppAuthProvider({
    AuthService? authService,
    required FirebaseAuth firebaseAuth,
  }) : _authService = authService ?? AuthService(firebaseAuth: firebaseAuth),
       _firebaseAuth = firebaseAuth {
    _firebaseAuth.authStateChanges().listen((User? user) {
      _user = user;
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Signs in the user anonymously.
  ///
  /// Skips if a user is already signed in.
  /// Updates [_user] and notifies listeners.
  Future<void> signInAnonymously() async {
    if (_user != null) {
      return;
    }
    try {
      _isLoading = true;
      _authError = null;
      notifyListeners();
      final userCredential = await _authService.signInAnonymously();
      _user = userCredential.user;
      AppLogger.logInfo('User signed in anonymously: ${_user?.uid}');
    } catch (e) {
      AppLogger.logError(e);
      _authError = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs in the user with email and password.
  ///
  /// [email] and [password] are required.
  /// Throws [ArgumentError] if either is empty.
  /// Updates [_user] and notifies listeners.
  Future<void> signInWithEmail(String email, String password) async {
    if (email.isEmpty) {
      throw ArgumentError('Email cannot be empty');
    }
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }
    try {
      _isLoading = true;
      _authError = null;
      notifyListeners();
      final userCredential = await _authService.signInWithEmailAndPassword(
        email,
        password,
      );
      _user = userCredential.user;
      AppLogger.logInfo('User signed in with email: ${_user?.uid}');
    } catch (e) {
      AppLogger.logError(e);
      _authError = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Links an anonymous account to an email and password.
  ///
  /// [email] and [password] are required.
  /// Throws [ArgumentError] if either is empty or if no user is signed in.
  /// Throws [StateError] if the current user is not anonymous.
  Future<void> linkAnonymousToEmail(String email, String password) async {
    if (email.isEmpty) {
      throw ArgumentError('Email cannot be empty');
    }
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }
    if (_user == null) {
      throw StateError('No user is currently signed in');
    }
    try {
      _isLoading = true;
      _authError = null;
      notifyListeners();
      if (_user!.isAnonymous) {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        final userCredential = await _user!.linkWithCredential(credential);
        _user = userCredential.user;
        AppLogger.logInfo('User linked to email: ${_user?.uid}');
      } else {
        throw StateError('Current user is not anonymous');
      }
    } catch (e) {
      AppLogger.logError(e);
      _authError = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
