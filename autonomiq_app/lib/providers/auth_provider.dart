import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? user;
  bool isLoading = true;

  AuthProvider() {
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      user = _authService.getCurrentUser();
      if (user == null) {
        await _authService.signInAnonymously();
        user = _authService.getCurrentUser();
      }
    } catch (e) {
      print("Auth error: $e");
    }
    isLoading = false;
    notifyListeners();
  }
}
