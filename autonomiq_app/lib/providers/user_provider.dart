import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../utils/logger.dart';

class UserProvider with ChangeNotifier {
  final UserRepository repository;
  final String uid;

  UserModel? _user;
  UserModel? get user => _user;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  UserProvider({required this.repository, required this.uid});

  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await repository.getUser(uid);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserProvider.loadUserProfile');
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
