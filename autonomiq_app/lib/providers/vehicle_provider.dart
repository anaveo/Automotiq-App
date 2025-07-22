import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vehicle_model.dart';
import '../repositories/vehicle_repository.dart';
import '../utils/logger.dart';

class VehicleProvider extends ChangeNotifier {
  final VehicleRepository _vehicleRepository;
  late FirebaseAuth _firebaseAuth;
  List<VehicleModel> _vehicles = [];
  VehicleModel? _selected;

  // Demo vehicle for testing purposes
  final VehicleModel? demoVehicle = VehicleModel(
    id: 'demo',
    name: 'Demo Vehicle',
    deviceId: '',
    vin: '4S3OMBAO2A4050702',
    year: 2002,
    odometer: 9282,
    diagnosticTroubleCodes: ['P0420', 'P0301'], 
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

  void selectVehicle(VehicleModel vehicle) {
    if (_vehicles.contains(vehicle) || vehicle == demoVehicle) {
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

  Future<void> addVehicle(VehicleModel newVehicle) async {
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

      // Add vehicle to Firestore, get document ID
      final vehicleId = await _vehicleRepository.addVehicle(user.uid, newVehicle);
      final newVehicleWithId = newVehicle.copyWith(id: vehicleId);

      // Prioritize new vehicle
      _vehicles.insert(0, newVehicleWithId);
      _selected = newVehicleWithId;
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