import 'package:flutter/foundation.dart';
import '../objects/user_object.dart';
import '../repositories/user_repository.dart';
import '../utils/logger.dart';

/// Manages user data state and interactions with Firestore for the app's UI.
class UserProvider with ChangeNotifier {
  final UserRepository repository;
  final String? uid;

  /// Current user data, or null if not loaded or unavailable.
  UserObject? _user;

  /// Gets the current user data.
  UserObject? get user => _user;

  /// Indicates if user data is being loaded.
  bool _isLoading = false;

  /// Gets the loading state.
  bool get isLoading => _isLoading;

  /// Constructor for UserProvider.
  ///
  /// [repository] handles Firestore interactions.
  /// [uid] is the user ID, or null if no user is signed in.
  /// Initializes user data if [uid] is provided.
  UserProvider({required this.repository, required this.uid}) {
    if (uid != null) {
      _isLoading = true;
      _initializeUser();
    } else {
      notifyListeners();
    }
  }

  /// Initializes user data by creating or verifying user document.
  ///
  /// Creates a user document if it doesn't exist and loads the user profile.
  Future<void> _initializeUser() async {
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await repository.createUserDocIfNotExists(
        uid!,
        UserObject(uid: uid!, createdAt: DateTime.now(), demoMode: true),
      );
      AppLogger.logInfo('User document created or verified for UID: $uid');

      _user = await repository.getUser(uid!);
      AppLogger.logInfo('User profile loaded for UID: $uid');
    } catch (e) {
      AppLogger.logError(e);
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads or refreshes the user profile from Firestore.
  ///
  /// Skips if no [uid] is provided.
  /// Updates [_user] and notifies listeners.
  Future<void> loadUserProfile() async {
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _user = await repository.getUser(uid!);
      AppLogger.logInfo('User profile loaded for UID: $uid');
    } catch (e) {
      AppLogger.logError(e);
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the demo mode setting for the user.
  ///
  /// [value] is the new demo mode state.
  /// Optimistically updates local state before Firestore.
  /// Reverts on failure.
  Future<void> setDemoMode(bool value) async {
    if (uid == null || _user == null) return;

    try {
      _user = _user!.copyWith(demoMode: value);
      notifyListeners();

      await repository.updateField(uid!, 'demoMode', value);

      AppLogger.logInfo('Demo mode updated to $value for UID: $uid');
    } catch (e) {
      AppLogger.logError(e);
      _user = _user!.copyWith(demoMode: !value);
    } finally {
      notifyListeners();
    }
  }
}
