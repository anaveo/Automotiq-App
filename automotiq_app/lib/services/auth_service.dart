import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth;

  AuthService({FirebaseAuth? firebaseAuth}) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  Future<UserCredential> signInAnonymously() async {
    try {
      return await _firebaseAuth.signInAnonymously();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'AuthService.signInAnonymously');
      rethrow;
    }
  }

  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'AuthService.signInWithEmailAndPassword');
      rethrow;
    }
  }

  User? getCurrentUser() => _firebaseAuth.currentUser;
}