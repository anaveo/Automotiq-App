import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automotiq_app/models/user_model.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'dart:async';

class UserRepository {
  final FirebaseFirestore firestore;

  /// Constructor for UserRepository.
  ///
  /// [firestoreInstance] is an optional parameter to allow dependency injection
  /// for testing. Defaults to [FirebaseFirestore.instance] if not provided.
  UserRepository({FirebaseFirestore? firestoreInstance})
    : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  /// Reference to the 'users' collection in Firestore.
  CollectionReference get _usersRef => firestore.collection('users');

  /// Creates a user document in Firestore if it doesn't already exist.
  ///
  /// Throws [ArgumentError] if [uid] is empty.
  /// Throws an [Exception] if creation fails and no operation is queued.
  Future<void> createUserDocIfNotExists(String uid, UserModel newUser) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    final docRef = _usersRef.doc(uid);

    try {
      final snapshot = await docRef.get(const GetOptions(source: Source.cache));
      if (!snapshot.exists) {
        final userMap = newUser.toMap();
        userMap['createdAt'] = FieldValue.serverTimestamp();

        // Perform the set operation
        unawaited(
          docRef
              .set(userMap)
              .then((_) {
                AppLogger.logInfo(
                  'User creation for $uid was successfully queued or completed.',
                );
              })
              .catchError((error) {
                AppLogger.logError(
                  'Error during background user set operation: $error',
                );
              }),
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        AppLogger.logWarning(
          'Offline mode detected during user creation check. Operation will be queued.',
        );
        final userMap = newUser.toMap();
        userMap['createdAt'] = FieldValue.serverTimestamp();
        unawaited(docRef.set(userMap));
      } else {
        throw Exception('Failed to create user: ${e.message}');
      }
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  /// Fetches a user from the Firestore database.
  ///
  /// Throws [ArgumentError] if [uid] is empty.
  /// Throws an [Exception] if fetching fails and no data is available in the offline cache.
  Future<UserModel> getUser(String uid) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    try {
      final snapshot = await _usersRef.doc(uid).get();

      if (snapshot.metadata.isFromCache) {
        AppLogger.logWarning(
          'getUser: Using cached user data due to being offline or for performance.',
        );
      }

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('User document not found or empty for UID: $uid');
      }

      return UserModel.fromMap(
        snapshot.id,
        snapshot.data()! as Map<String, dynamic>,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        AppLogger.logWarning('Offline mode detected, using cached data');
        final doc = await _usersRef
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        if (!doc.exists || doc.data() == null) {
          throw Exception('User document not found or empty for UID: $uid');
        }
        return UserModel.fromMap(doc.id, doc.data()! as Map<String, dynamic>);
      }
      throw Exception('Failed to fetch user profile: ${e.message}');
    } catch (e) {
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  /// Updates a specific field in the user document in Firestore.
  ///
  /// Throws [ArgumentError] if [uid] or [field] are empty.
  /// Throws an [Exception] if the user does not exist or if the update fails.
  Future<void> updateField(String uid, String field, dynamic value) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');
    if (field.isEmpty) throw ArgumentError('Field name cannot be empty');

    final docRef = _usersRef.doc(uid);

    try {
      final snapshot = await docRef.get(const GetOptions(source: Source.cache));
      if (!snapshot.exists) {
        throw Exception('Cannot update field. User $uid does not exist.');
      }

      // Perform the update operation
      unawaited(
        docRef
            .update({field: value})
            .then((_) {
              AppLogger.logInfo(
                'User field update for $uid was successfully queued or completed.',
              );
            })
            .catchError((error) {
              AppLogger.logError(
                'Error during background user update operation: $error',
              );
            }),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        AppLogger.logWarning(
          'Offline mode detected during user update check. Update will be queued.',
        );
        unawaited(docRef.update({field: value}));
      } else {
        throw Exception('Failed to update user field: ${e.message}');
      }
    } catch (e) {
      throw Exception('Failed to update user field: $e');
    }
  }
}
