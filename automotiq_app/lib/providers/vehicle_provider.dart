import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/vehicle_model.dart';
import '../repositories/vehicle_repository.dart';
import '../utils/logger.dart';

class VehicleProvider extends ChangeNotifier {
  final VehicleRepository _vehicleRepository;
  late FirebaseAuth _firebaseAuth;
  List<VehicleModel> _vehicles = [];
  VehicleModel? _selected;
  final Uuid _uuid = const Uuid();
  
  // Demo vehicle for testing purposes
  final VehicleModel? demoVehicle = VehicleModel(
    id: 'demo',
    name: 'Demo Vehicle',
    deviceId: '',
    vin: '4S3OMBAO2A4050702',
    year: 2002,
    odometer: 20618,
    diagnosticTroubleCodes: ['P0420', 'P0325'], 
  );

  bool _isLoading = false;

  List<VehicleModel> get vehicles => _vehicles;
  VehicleModel? get selectedVehicle => _selected;
  bool get isLoading => _isLoading;

  VehicleProvider({required VehicleRepository vehicleRepository, required FirebaseAuth firebaseAuth})
      : _vehicleRepository = vehicleRepository,
        _firebaseAuth = firebaseAuth;

  void updateAuth(FirebaseAuth auth) {
    _firebaseAuth = auth;
  }

  Future<void> loadVehicles() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _vehicles = [];
      _selected = null;
      _isLoading = false;
      notifyListeners();
      throw StateError('No user is signed in');
    }

    try {
      _isLoading = true;
      notifyListeners();
      _vehicles = await _vehicleRepository.getVehicles(user.uid);
      _selected = _vehicles.isNotEmpty ? _vehicles.first : demoVehicle;
      AppLogger.logInfo('Loaded ${_vehicles.length} vehicle(s) for UID: ${_firebaseAuth.currentUser?.uid}');
    } catch (e) {
      AppLogger.logError(e);
      _vehicles = [];
      _selected = demoVehicle;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectVehicle(VehicleModel vehicle) {
    if (_vehicles.contains(vehicle) || vehicle == demoVehicle) {
      _selected = vehicle;
      notifyListeners();
    } else {
      AppLogger.logError(
        Exception('Invalid vehicle selected'));
    }
  }

  Future<void> addVehicle(VehicleModel newVehicle) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(
        StateError('No user is signed in'));
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      // Generate client-side ID and include it in the VehicleModel
      final vehicleId = _uuid.v4();
      final newVehicleWithId = newVehicle.copyWith(id: vehicleId);

      // Add vehicle to Firestore
      await _vehicleRepository.addVehicle(user.uid, newVehicleWithId);

      // Prioritize new vehicle
      _vehicles.insert(0, newVehicleWithId);
      _selected = newVehicleWithId;
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeVehicle(String vehicleId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(StateError('No user is signed in'));
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();
      await _vehicleRepository.removeVehicle(user.uid, vehicleId);
      _vehicles.removeWhere((v) => v.id == vehicleId);
      _selected = _vehicles.isNotEmpty ? _vehicles.first : null;
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}