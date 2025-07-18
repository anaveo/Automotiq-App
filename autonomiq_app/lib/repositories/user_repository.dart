import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autonomiq_app/utils/logger.dart';

class UserRepository {
  final FirebaseFirestore firestore;

  UserRepository({FirebaseFirestore? firestoreInstance})
      : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  Future<void> createUserIfNotExists(String uid) async {
    if (uid.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    final docRef = firestore.collection('users').doc(uid);

    try {
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        await docRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          // Add default fields here in the future if needed
        });
      }
    } catch (e, stackTrace) {
      // Optional: Use AppLogger if you're logging elsewhere
      AppLogger.logError(e, stackTrace, 'UserRepository.createUserIfNotExists');
      throw Exception('Failed to create user: $e');
    }
  }
}
