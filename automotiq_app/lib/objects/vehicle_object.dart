/// Represents a vehicle with its details and diagnostic information stored in Firestore.
class VehicleObject {
  /// Firestore document ID for the vehicle.
  String id;

  /// Name or model of the vehicle.
  String name;

  /// Vehicle Identification Number (VIN).
  String vin;

  /// Manufacturing year of the vehicle.
  int year;

  /// Current odometer reading of the vehicle.
  int odometer;

  /// List of diagnostic trouble codes (DTCs) associated with the vehicle.
  List<String> diagnosticTroubleCodes;

  /// Bluetooth Low Energy (BLE) device ID for vehicle connectivity.
  String deviceId;

  /// Constructor for VehicleModel.
  ///
  /// [deviceId] is required for BLE connectivity.
  /// Optional parameters default to empty or zero values.
  /// [diagnosticTroubleCodes] defaults to an empty list if not provided.
  VehicleObject({
    required this.deviceId,
    this.id = '',
    this.name = 'Unknown',
    this.vin = 'Unknown',
    this.year = 0,
    this.odometer = 0,
    List<String>? diagnosticTroubleCodes,
  }) : diagnosticTroubleCodes = diagnosticTroubleCodes ?? [];

  /// Creates a VehicleModel instance from a Firestore document.
  ///
  /// [id] is the Firestore document ID.
  /// [data] is the Firestore document data as a map.
  /// Handles null or invalid values with defaults.
  factory VehicleObject.fromMap(String id, Map<String, dynamic> data) {
    return VehicleObject(
      deviceId: data['deviceId'] ?? '',
      id: id,
      name: data['name'] ?? 'Unknown',
      vin: data['vin'] ?? 'Unknown',
      year: int.tryParse(data['year'].toString()) ?? 0,
      odometer: int.tryParse(data['odometer'].toString()) ?? 0,
      diagnosticTroubleCodes: List<String>.from(
        data['diagnosticTroubleCodes'] ?? [],
      ),
    );
  }

  /// Converts the VehicleModel instance to a map for Firestore storage.
  ///
  /// Excludes the document ID as it is managed by Firestore.
  /// Returns a map of vehicle attributes.
  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'name': name,
    'vin': vin,
    'year': year,
    'odometer': odometer,
    'diagnosticTroubleCodes': diagnosticTroubleCodes,
  };

  /// Updates the vehicle's name.
  ///
  /// [newName] is the new name to set for the vehicle.
  void updateName(String newName) => name = newName;

  /// Updates the vehicle's VIN.
  ///
  /// [newVin] is the new VIN to set for the vehicle.
  void updateVin(String newVin) => vin = newVin;

  /// Updates the vehicle's manufacturing year.
  ///
  /// [newYear] is the new year to set for the vehicle.
  void updateYear(int newYear) => year = newYear;

  /// Updates the vehicle's odometer reading.
  ///
  /// [newOdometer] is the new odometer value to set.
  void updateOdometer(int newOdometer) => odometer = newOdometer;

  /// Adds a diagnostic trouble code to the vehicle.
  ///
  /// [code] is the DTC to add. Only adds if not already present.
  void addDiagnosticTroubleCode(String code) {
    if (!diagnosticTroubleCodes.contains(code)) {
      diagnosticTroubleCodes.add(code);
    }
  }

  /// Removes a diagnostic trouble code from the vehicle.
  ///
  /// [code] is the DTC to remove.
  void removeDiagnosticTroubleCode(String code) {
    diagnosticTroubleCodes.remove(code);
  }

  /// Clears all diagnostic trouble codes from the vehicle.
  void clearDiagnosticTroubleCodes() {
    diagnosticTroubleCodes.clear();
  }

  /// Creates a copy of the VehicleModel with optional updated fields.
  ///
  /// Allows partial updates to vehicle attributes while preserving unchanged values.
  /// Returns a new VehicleModel instance.
  VehicleObject copyWith({
    String? deviceId,
    String? id,
    String? name,
    String? vin,
    int? year,
    int? odometer,
    List<String>? diagnosticTroubleCodes,
  }) {
    return VehicleObject(
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      vin: vin ?? this.vin,
      year: year ?? this.year,
      odometer: odometer ?? this.odometer,
      diagnosticTroubleCodes:
          diagnosticTroubleCodes ?? List.from(this.diagnosticTroubleCodes),
    );
  }
}
