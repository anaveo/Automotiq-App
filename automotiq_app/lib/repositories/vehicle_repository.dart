import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automotiq_app/objects/vehicle_object.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'dart:async';

class VehicleRepository {
  final FirebaseFirestore firestore;

  /// Constructor for VehicleRepository.
  ///
  /// [firestoreInstance] is an optional parameter to allow dependency injection
  /// for testing. Defaults to [FirebaseFirestore.instance] if not provided.
  VehicleRepository({FirebaseFirestore? firestoreInstance})
    : firestore = firestoreInstance ?? FirebaseFirestore.instance;

  /// Fetches vehicles from the Firestore database.
  ///
  /// Throws [ArgumentError] if [uid] is empty.
  /// Throws an [Exception] if fetching fails and no data is available in the offline cache.
  Future<List<VehicleObject>> getVehicles(String uid) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty.');

    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('vehicles')
          .get();

      if (snapshot.metadata.isFromCache) {
        AppLogger.logWarning(
          'getVehicles: Using cached vehicle data due to being offline or for performance.',
        );
      }

      // Retrieve data and return
      return snapshot.docs
          .map((doc) => VehicleObject.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Adds a vehicle to the Firestore database.
  ///
  /// Throws [ArgumentError] if required IDs are empty.
  /// Returns the ID of the vehicle being added.
  Future<String> addVehicle(String uid, VehicleObject newVehicle) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty.');
    if (newVehicle.id.isEmpty)
      throw ArgumentError('Vehicle ID cannot be empty.');
    if (newVehicle.deviceId.isEmpty)
      throw ArgumentError('Device ID is required.');

    final docRef = firestore
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(newVehicle.id);

    try {
      // Perform the add operation
      unawaited(
        docRef
            .set(newVehicle.toMap())
            .then((_) {
              AppLogger.logInfo(
                'Vehicle add/update for ${newVehicle.id} was successfully queued or completed.',
              );
            })
            .catchError((error) {
              // If the set Future fails, it's due to a non-network issue
              // like permissions, not because the device is offline.
              AppLogger.logError(
                'Error during background vehicle set operation: $error',
              );
            }),
      );

      // Return vehicle id (actual addition will be done in the background based on offline state)
      return newVehicle.id;
    } catch (e) {
      rethrow;
    }
  }

  /// Updates a vehicle's diagnostic trouble codes, odometer, and name in the Firestore database.
  ///
  /// Throws [ArgumentError] if [uid] or [vehicle.id] are empty.
  /// Throws an [Exception] if the vehicle does not exist in the cache.
  Future<void> updateVehicle(String uid, VehicleObject vehicle) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty.');
    if (vehicle.id.isEmpty) throw ArgumentError('Vehicle ID cannot be empty.');

    final docRef = firestore
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vehicle.id);

    try {
      // Ensure vehicle exists in cache
      final docSnap = await docRef.get(const GetOptions(source: Source.cache));
      if (!docSnap.exists) {
        throw ArgumentError(
          'Vehicle ${vehicle.id} does not exist for user $uid',
        );
      }

      // Perform the update operation for diagnosticTroubleCodes, odometer, and name
      unawaited(
        docRef
            .update({
              'diagnosticTroubleCodes': vehicle.diagnosticTroubleCodes,
              'odometer': vehicle.odometer,
              'name': vehicle.name,
            })
            .then((_) {
              AppLogger.logInfo(
                'Vehicle update for ${vehicle.id} (diagnosticTroubleCodes, odometer, name) was successfully queued or completed.',
              );
            })
            .catchError((error) {
              // If the update Future fails, it's due to a non-network issue
              // like permissions, not because the device is offline.
              AppLogger.logError(
                'Error during background vehicle update operation: $error',
              );
            }),
      );
    } on FirebaseException catch (e) {
      // Handle errors from the initial docRef.get() call
      if (e.code == 'unavailable') {
        AppLogger.logWarning(
          'Offline mode detected during vehicle existence check. Update will be queued.',
        );
        unawaited(
          docRef.update({
            'diagnosticTroubleCodes': vehicle.diagnosticTroubleCodes,
            'odometer': vehicle.odometer,
            'name': vehicle.name,
          }),
        );
      } else {
        throw Exception(
          'Failed to update vehicle due to a Firebase error: ${e.message}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Removes a vehicle from the Firestore database.
  ///
  /// Throws [ArgumentError] if [uid] or [vehicleId] are empty, or if the
  /// vehicle does not exist in the cache.
  /// Throws an [Exception] for other failures.
  Future<void> removeVehicle(String uid, String vehicleId) async {
    if (uid.isEmpty) throw ArgumentError('User ID cannot be empty.');
    if (vehicleId.isEmpty) throw ArgumentError('Vehicle ID cannot be empty.');

    final docRef = firestore
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vehicleId);

    try {
      // Ensure vehicle exists
      final docSnap = await docRef.get(const GetOptions(source: Source.cache));
      if (!docSnap.exists) {
        throw ArgumentError('Vehicle $vehicleId does not exist for user $uid');
      }

      // Perform the delete operation
      unawaited(
        docRef
            .delete()
            .then((_) {
              AppLogger.logInfo(
                'Vehicle deletion for $vehicleId successfully queued or completed.',
              );
            })
            .catchError((e) {
              // If the delete Future fails, it's due to a non-network issue
              // like permissions, not because the device is offline.
              AppLogger.logError(e);
            }),
      );
    } on FirebaseException catch (e) {
      // This catches errors from the initial docRef.get() call
      if (e.code == 'unavailable') {
        AppLogger.logWarning(
          'Offline mode detected during vehicle existence check. Deletion will be queued.',
        );
        unawaited(docRef.delete());
      } else {
        throw Exception(
          'Failed to remove vehicle due to a Firebase error: ${e.message}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}
