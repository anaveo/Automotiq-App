// providers/vehicle_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vehicle_model.dart';
import '../services/firestore_service.dart';

class VehicleProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<Vehicle> _vehicles = [];
  Vehicle? _selected;
  bool _isLoading = true;

  List<Vehicle> get vehicles => _vehicles;
  Vehicle? get selectedVehicle => _selected;
  bool get isLoading => _isLoading;

  Future<void> loadVehicles() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    _vehicles = await _firestore.getUserVehicles(uid);
    _selected = _vehicles.isNotEmpty ? _vehicles.first : null;

    _isLoading = false;
    notifyListeners();
  }

  void selectVehicle(Vehicle vehicle) {
    _selected = vehicle;
    notifyListeners();
  }
}
