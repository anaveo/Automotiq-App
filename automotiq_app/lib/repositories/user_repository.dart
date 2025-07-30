import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automotiq_app/models/user_model.dart';
import 'package:automotiq_app/utils/logger.dart';

class UserRepository {
  final FirebaseFirestore firestore;

  UserRepository({FirebaseFirestore? firestoreInstance})
      : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  CollectionReference get _usersRef => firestore.collection('users');

  Future<void> createUserDocIfNotExists(String uid, UserModel newUser) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    final docRef = _usersRef.doc(uid);

    try {
      final snapshot = await docRef.get(const GetOptions(source: Source.cache));
      if (!snapshot.exists) {
        final userMap = newUser.toMap();
        userMap['createdAt'] = FieldValue.serverTimestamp();

        await docRef.set(userMap);

        // Check if operation was queued offline
        final docSnapshot = await docRef.get();
        if (docSnapshot.metadata.isFromCache) {
          AppLogger.logWarning('Operation queued for sync due to offline mode');
        }
      }
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('Operation queued for sync due to offline mode');
        // Firestore queues the set operation, so no retry needed
        final snapshot = await docRef.get(const GetOptions(source: Source.cache));
        if (!snapshot.exists) {
          final userMap = newUser.toMap();
          userMap['createdAt'] = FieldValue.serverTimestamp();
          await docRef.set(userMap);
        }
        return;
      }
      throw Exception('Failed to create user: $e');
    }
  }

  Future<UserModel> getUser(String uid) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    try {
      final doc = await _usersRef.doc(uid).get(const GetOptions(source: Source.cache));

      if (doc.metadata.isFromCache) {
        AppLogger.logWarning('Using cached data due to offline mode');
      }

      if (!doc.exists || doc.data() == null) {
        throw Exception('User document not found or empty for UID: $uid');
      }

      return UserModel.fromMap(doc.id, doc.data()! as Map<String, dynamic>);
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('Offline mode, using cached data');
        // Retry with cache explicitly
        final doc = await _usersRef.doc(uid).get(const GetOptions(source: Source.cache));
        if (!doc.exists || doc.data() == null) {
          throw Exception('User document not found or empty for UID: $uid');
        }
        return UserModel.fromMap(doc.id, doc.data()! as Map<String, dynamic>);
      }
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  Future<void> updateField(String uid, String field, dynamic value) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');
    if (field.isEmpty) throw ArgumentError('Field name cannot be empty');

    try {
      final docRef = _usersRef.doc(uid);

      final snapshot = await docRef.get(const GetOptions(source: Source.cache));
      if (!snapshot.exists) {
        throw Exception('Cannot update field. User $uid does not exist.');
      }

      await docRef.update({field: value});

      // Check if operation was queued offline
      final docSnapshot = await docRef.get();
      if (docSnapshot.metadata.isFromCache) {
        AppLogger.logWarning('Operation queued for sync due to offline mode');
      }
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('Operation queued for sync due to offline mode');
        // Firestore queues the update, so no retry needed
        return;
      }
      throw Exception('Failed to update user field: $e');
    }
  }
}