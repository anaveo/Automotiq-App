import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../utils/logger.dart';

class UserProvider with ChangeNotifier {
  final UserRepository repository;
  final String? uid;

  UserModel? _user;
  UserModel? get user => _user;

  bool _isLoading = false; // Default to false for null UID
  bool get isLoading => _isLoading;

  UserProvider({required this.repository, required this.uid}) {
    if (uid != null) {
      _isLoading = true; // Set loading only if UID exists
      _initializeUser();
    } else {
      notifyListeners();
    }
  }

  Future<void> _initializeUser() async {
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Create user document if it doesn't exist
      await repository.createUserDocIfNotExists(
        uid!,
        UserModel(uid: uid!, createdAt: DateTime.now(), demoMode: true),
      );
      AppLogger.logInfo('User document created or verified for UID: $uid', 'UserProvider.initializeUser');

      // Load user profile
      _user = await repository.getUser(uid!);
      AppLogger.logInfo('User profile loaded for UID: $uid', 'UserProvider.initializeUser');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserProvider.initializeUser');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUserProfile() async {
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _user = await repository.getUser(uid!);
      AppLogger.logInfo('User profile loaded for UID: $uid', 'UserProvider.loadUserProfile');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserProvider.loadUserProfile');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setDemoMode(bool value) async {
    if (uid == null || _user == null) return;

    try {
      // Optimistically update local model
      _user = _user!.copyWith(demoMode: value);
      notifyListeners();

      // Update Firestore
      await repository.updateField(uid!, 'demoMode', value);

      AppLogger.logInfo('Demo mode updated to $value for UID: $uid', 'UserProvider.setDemoMode');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserProvider.setDemoMode');
      // Revert optimistic update here if needed
      _user = _user!.copyWith(demoMode: !value);
    } finally {
      notifyListeners();
    }
  }
}