import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';

class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final FirebaseAuth _firebaseAuth;
  User? _user;
  bool _isLoading = false;
  String? _authError;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get authError => _authError;
  FirebaseAuth get firebaseAuth => _firebaseAuth;

  AppAuthProvider({AuthService? authService, required FirebaseAuth firebaseAuth})
      : _authService = authService ?? AuthService(firebaseAuth: firebaseAuth),
        _firebaseAuth = firebaseAuth {
    _firebaseAuth.authStateChanges().listen((User? user) {
      _user = user;
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> signInAnonymously() async {
    if (_user != null) {
      return; // User already signed in
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
      final userCredential = await _authService.signInWithEmailAndPassword(email, password);
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
        final credential = EmailAuthProvider.credential(email: email, password: password);
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