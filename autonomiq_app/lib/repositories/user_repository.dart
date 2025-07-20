import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autonomiq_app/models/user_model.dart';
import 'package:autonomiq_app/utils/logger.dart';

class UserRepository {
  final FirebaseFirestore firestore;

  UserRepository({FirebaseFirestore? firestoreInstance})
      : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  CollectionReference get _usersRef => firestore.collection('users');

  Future<void> createUserIfNotExists(String uid, UserModel newUser) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    final docRef = _usersRef.doc(uid);

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        final userMap = newUser.toMap();
        userMap['createdAt'] = FieldValue.serverTimestamp();

        await docRef.set(userMap);
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserRepository.createUserIfNotExists');
      throw Exception('Failed to create user: $e');
    }
  }

  Future<UserModel> getUser(String uid) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');

    try {
      final doc = await _usersRef.doc(uid).get();

      if (!doc.exists || doc.data() == null) {
        throw Exception('User document not found or empty for UID: $uid');
      }

      return UserModel.fromMap(doc.id, doc.data()! as Map<String, dynamic>);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserRepository.getUser');
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  Future<void> updateField(String uid, String field, dynamic value) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');
    if (field.isEmpty) throw ArgumentError('Field name cannot be empty');

    try {
      final docRef = _usersRef.doc(uid);

      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        throw Exception('Cannot update field. User $uid does not exist.');
      }

      await docRef.update({field: value});
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UserRepository.updateField');
      throw Exception('Failed to update user field: $e');
    }
  }
}
