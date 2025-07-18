import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle_model.dart';
import '../utils/logger.dart';

class VehicleRepository {
  final FirebaseFirestore firestore;

  VehicleRepository({FirebaseFirestore? firestoreInstance})
      : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  Future<List<Vehicle>> getVehicles(String uid) async {
    if (uid.isEmpty) throw ArgumentError('UID cannot be empty');
    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .get();

      return snapshot.docs
          .map((doc) => Vehicle.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleRepository.getVehicles');
      rethrow;
    }
  }

  Future<String> addVehicle(String uid, Map<String, dynamic> vehicleData) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty');
    final name = vehicleData['name']?.toString().trim();
    if (name == null || name.isEmpty) throw ArgumentError('Vehicle name is required');

    try {
      final cleanData = {...vehicleData, 'name': name};
      final docRef = await firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .add(cleanData);
      return docRef.id;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleRepository.addVehicle');
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

      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        throw ArgumentError('Vehicle $vehicleId does not exist for user $uid');
      }

      await docRef.delete();
    } on ArgumentError {
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleRepository.removeVehicle');
      throw Exception('Failed to remove vehicle: $e');
    }
  }
}
