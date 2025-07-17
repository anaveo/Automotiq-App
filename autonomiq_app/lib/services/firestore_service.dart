import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle_model.dart';
import '../utils/logger.dart';

class FirestoreService {
  final FirebaseFirestore _firestore;

  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    // Enable offline persistence
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  // Assumes Firestore security rules:
  // match /users/{uid}/vehicles/{vehicleId} {
  //   allow read, write: if request.auth.uid == uid;
  // }
  Future<List<Vehicle>> getUserVehicles(String uid) async {
    if (uid.isEmpty) {
      throw ArgumentError('UID cannot be empty');
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .get();
      return snapshot.docs
          .map((doc) => Vehicle.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'FirestoreService.getUserVehicles');
      rethrow;
    }
  }

  Future<String> addVehicle(String uid, Map<String, dynamic> vehicleData) async {
    if (uid.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }

    final name = vehicleData['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      throw ArgumentError('Vehicle name is required');
    }

    try {
      final cleanData = Map<String, dynamic>.from(vehicleData)
        ..['name'] = name; // ensure it's trimmed

      final docRef = await _firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .add(cleanData);

      return docRef.id;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'FirestoreService.addVehicle');
      throw Exception('Failed to add vehicle: $e');
    }
  }

  Future<void> removeVehicle(String uid, String vehicleId) async {
    if (uid.isEmpty) {
      throw ArgumentError('User ID cannot be empty');
    }
    if (vehicleId.isEmpty) {
      throw ArgumentError('Vehicle ID cannot be empty');
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .doc(vehicleId);

      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        throw ArgumentError('Vehicle ID $vehicleId does not exist for user $uid');
      }

      await docRef.delete();
    } on ArgumentError {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'FirestoreService.removeVehicle');
      throw Exception('Failed to remove vehicle: $e');
    }
  }
}