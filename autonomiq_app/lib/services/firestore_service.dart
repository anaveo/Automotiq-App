import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle_model.dart';

class FirestoreService {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Vehicle>> getUserVehicles(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .get();

    return snapshot.docs
        .map((doc) => Vehicle.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> addVehicle(String uid, Vehicle vehicle) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vehicle.id)
        .set(vehicle.toMap());
  }

  // Future functions: updateVehicle, deleteVehicle, listenToChanges...
}
