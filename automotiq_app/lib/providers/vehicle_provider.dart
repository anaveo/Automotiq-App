import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../objects/vehicle_object.dart';
import '../repositories/vehicle_repository.dart';
import '../utils/logger.dart';

/// Manages vehicle data state and interactions with Firestore for the app's UI.
class VehicleProvider extends ChangeNotifier {
  final VehicleRepository _vehicleRepository;
  late FirebaseAuth _firebaseAuth;
  List<VehicleObject> _vehicles = [];
  VehicleObject? _selected;
  final Uuid _uuid = const Uuid();

  /// Demo vehicle for testing purposes in demo mode.
  final VehicleObject demoVehicle = VehicleObject(
    id: 'demo',
    name: 'Demo Vehicle',
    deviceId: '',
    vin: '4S3OMBAO2A4050702',
    year: 2002,
    odometer: 20618,
    diagnosticTroubleCodes: ['P0420', 'P0118'],
  );

  /// Indicates if vehicle data is being loaded.
  bool _isLoading = false;

  /// List of vehicles for the current user.
  List<VehicleObject> get vehicles => _vehicles;

  /// Currently selected vehicle, or null if none selected.
  VehicleObject? get selectedVehicle => _selected;

  /// Indicates if data loading is in progress.
  bool get isLoading => _isLoading;

  /// Tracks demo mode state.
  bool _demoMode = true;

  /// Constructor for VehicleProvider.
  ///
  /// [vehicleRepository] handles Firestore interactions.
  /// [firebaseAuth] provides user authentication state.
  VehicleProvider({
    required VehicleRepository vehicleRepository,
    required FirebaseAuth firebaseAuth,
  }) : _vehicleRepository = vehicleRepository,
       _firebaseAuth = firebaseAuth;

  /// Updates the FirebaseAuth instance.
  ///
  /// [auth] is the new FirebaseAuth instance to use.
  void updateAuth(FirebaseAuth auth) {
    _firebaseAuth = auth;
  }

  /// Loads vehicles for the current user from Firestore.
  ///
  /// Throws [StateError] if no user is signed in.
  /// Updates [_vehicles] and [_selected], notifying listeners.
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
      _setValidSelectedVehicle();
      AppLogger.logInfo(
        'Loaded ${_vehicles.length} vehicle(s) for UID: ${_firebaseAuth.currentUser?.uid}',
      );
    } catch (e) {
      AppLogger.logError(e);
      _vehicles = [];
      _selected = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Selects a vehicle for detailed viewing or interaction.
  ///
  /// [vehicle] must be in [_vehicles] or be the [demoVehicle].
  /// Notifies listeners if selection is valid.
  void selectVehicle(VehicleObject vehicle) {
    if (_vehicles.contains(vehicle) || vehicle == demoVehicle) {
      _selected = vehicle;
      notifyListeners();
    } else {
      AppLogger.logError(Exception('Invalid vehicle selected'));
    }
  }

  /// Updates demo mode and adjusts selected vehicle accordingly.
  ///
  /// [isDemoMode] determines if demo mode is active.
  /// Notifies listeners after updating.
  void updateDemoMode(bool isDemoMode) {
    _demoMode = isDemoMode;
    _setValidSelectedVehicle();
    notifyListeners();
  }

  /// Sets [_selected] to a valid vehicle or null based on state.
  ///
  /// Selects first vehicle if available, demo vehicle in demo mode, or null.
  void _setValidSelectedVehicle() {
    if (_vehicles.isNotEmpty) {
      _selected = _vehicles.first;
    } else if (_demoMode) {
      _selected = demoVehicle;
    } else {
      _selected = null;
    }
  }

  /// Adds a new vehicle to Firestore and local state.
  ///
  /// [newVehicle] is the vehicle to add.
  /// Generates a client-side UUID for the vehicle ID.
  /// Throws [StateError] if no user is signed in.
  Future<void> addVehicle(VehicleObject newVehicle) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(StateError('No user is signed in'));
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final vehicleId = _uuid.v4();
      final newVehicleWithId = newVehicle.copyWith(id: vehicleId);

      await _vehicleRepository.addVehicle(user.uid, newVehicleWithId);

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

  /// Updates an existing vehicle in Firestore and local state.
  ///
  /// [updatedVehicle] contains the updated vehicle data.
  /// Throws [StateError] if no user is signed in.
  /// Prevents updates to demo vehicle.
  Future<void> updateVehicle(VehicleObject updatedVehicle) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      AppLogger.logError(StateError('No user is signed in'));
      return;
    }

    if (updatedVehicle.id == 'demo') {
      AppLogger.logWarning('Cannot update demo vehicle');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      await _vehicleRepository.updateVehicle(user.uid, updatedVehicle);

      final index = _vehicles.indexWhere((v) => v.id == updatedVehicle.id);
      if (index != -1) {
        _vehicles[index] = updatedVehicle;
      } else {
        AppLogger.logWarning(
          'Vehicle ${updatedVehicle.id} not found in local list',
        );
        _vehicles.add(updatedVehicle);
      }

      if (_selected?.id == updatedVehicle.id) {
        _selected = updatedVehicle;
      }
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Removes a vehicle from Firestore and local state.
  ///
  /// [vehicleId] is the ID of the vehicle to remove.
  /// Throws [StateError] if no user is signed in.
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
      _setValidSelectedVehicle();
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
