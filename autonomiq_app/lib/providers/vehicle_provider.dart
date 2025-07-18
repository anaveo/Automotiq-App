import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vehicle_model.dart';
import '../repositories/vehicle_repository.dart';
import '../utils/logger.dart';

class VehicleProvider extends ChangeNotifier {
  final VehicleRepository _vehicleRepository;
  late FirebaseAuth _firebaseAuth;
  List<Vehicle> _vehicles = [];
  Vehicle? _selected;
  bool _isLoading = false;

  List<Vehicle> get vehicles => _vehicles;
  Vehicle? get selectedVehicle => _selected;
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
      _selected = _vehicles.isNotEmpty ? _vehicles.first : null;
      AppLogger.logInfo('Loaded ${_vehicles.length} vehicle(s) for UID: ${_firebaseAuth.currentUser?.uid}', 'VehicleProvider.loadVehicles');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleProvider.loadVehicles');
      _vehicles = [];
      _selected = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectVehicle(Vehicle vehicle) {
    if (_vehicles.contains(vehicle)) {
      _selected = vehicle;
      notifyListeners();
    } else {
      AppLogger.logError(
        Exception('Invalid vehicle selected'),
        StackTrace.current,
        'VehicleProvider.selectVehicle',
      );
    }
  }

  Future<void> addVehicle(Map<String, dynamic> vehicleData) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(
        StateError('No user is signed in'),
        StackTrace.current,
        'VehicleProvider.addVehicle',
      );
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();
      final vehicleId = await _vehicleRepository.addVehicle(user.uid, vehicleData);
      final newVehicle = Vehicle(
        id: vehicleId,
        name: vehicleData['name'] ?? 'Unknown',
        vin: vehicleData['vin'] ?? 'Unknown',
        year: vehicleData['year'] ?? 0,
        odometer: vehicleData['odometer'] ?? 0,
        isConnected: vehicleData['isConnected'] ?? false,
        diagnosticTroubleCodes: vehicleData['diagnosticTroubleCodes'] ?? [],
      );
      _vehicles.insert(0, newVehicle); // Prioritize new vehicle
      _selected = newVehicle;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleProvider.addVehicle');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeVehicle(String vehicleId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(
        StateError('No user is signed in'),
        StackTrace.current,
        'VehicleProvider.removeVehicle',
      );
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();
      await _vehicleRepository.removeVehicle(user.uid, vehicleId);
      _vehicles.removeWhere((v) => v.id == vehicleId);
      _selected = _vehicles.isNotEmpty ? _vehicles.first : null;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'VehicleProvider.removeVehicle');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}