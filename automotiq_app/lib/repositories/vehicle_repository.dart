import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automotiq_app/models/vehicle_model.dart';
import 'package:automotiq_app/utils/logger.dart';

class VehicleRepository {
  final FirebaseFirestore firestore;
  
  VehicleRepository({FirebaseFirestore? firestoreInstance})
      : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  Future<List<VehicleModel>> getVehicles(String uid) async {
    if (uid.isEmpty) throw ArgumentError('UID cannot be empty');
    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .get();

      if (snapshot.metadata.isFromCache) {
        AppLogger.logWarning('getVehicles: Using cached data due to offline mode');
      }

      return snapshot.docs
          .map((doc) => VehicleModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('getVehicles: Offline mode, using cached data', 'VehicleRepository.getVehicles');
        // Firestore automatically uses cache, so no need to rethrow if data is available
        final snapshot = await firestore
            .collection('users')
            .doc(uid)
            .collection('vehicles')
            .get(const GetOptions(source: Source.cache));
        return snapshot.docs
            .map((doc) => VehicleModel.fromMap(doc.id, doc.data()))
            .toList();
      }
      rethrow;
    }
  }

  Future<String> addVehicle(String uid, VehicleModel newVehicle) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');
    if (newVehicle.deviceId.isEmpty) throw ArgumentError('Device ID is required');
    if (newVehicle.id.isEmpty) throw ArgumentError('Vehicle ID cannot be empty');

    try {
      final docRef = firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .doc(newVehicle.id);

      // Check for ID collision
      final existingDoc = await docRef.get();
      if (existingDoc.exists) {
        throw Exception('Vehicle ID ${newVehicle.id} already exists');
      }

      await docRef.set(newVehicle.toMap());

      // Check if operation was queued offline
      final docSnapshot = await docRef.get();
      if (docSnapshot.metadata.isFromCache) {
        AppLogger.logWarning('addVehicle: Operation queued for sync due to offline mode');
      }

      return newVehicle.id;
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('addVehicle: Operation queued for sync due to offline mode', 'VehicleRepository.addVehicle');
        // Firestore automatically queues the operation, so no retry needed
        return newVehicle.id;
      }
      throw Exception('Failed to add vehicle: $e');
    }
  }

  Future<void> removeVehicle(String uid, String vehicleId) async {
    if (uid.isEmpty || vehicleId.isEmpty) {
      throw ArgumentError('User ID and Vehicle ID cannot be empty');
    }

    try {
      final docRef = firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .doc(vehicleId);

      final docSnap = await docRef.get(const GetOptions(source: Source.cache));
      if (!docSnap.exists) {
        throw ArgumentError('Vehicle $vehicleId does not exist for user $uid');
      }

      await docRef.delete();
      // Check if deletion was queued offline
      final postDeleteSnap = await docRef.get();
      if (postDeleteSnap.metadata.isFromCache) {
        AppLogger.logWarning('removeVehicle: Deletion queued for sync due to offline mode');
      }
    } on ArgumentError {
      rethrow;
    } catch (e) {
      if (e is FirebaseException && e.code == 'unavailable') {
        AppLogger.logWarning('removeVehicle: Deletion queued for sync due to offline mode', 'VehicleRepository.removeVehicle');
        // Deletion is queued by Firestore, so allow it to proceed
        final docRef = firestore
            .collection('users')
            .doc(uid)
            .collection('vehicles')
            .doc(vehicleId);
        await docRef.delete();
        return;
      }
      throw Exception('Failed to remove vehicle: $e');
    }
  }
}