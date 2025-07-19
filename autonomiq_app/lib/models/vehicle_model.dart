class Vehicle {
  // Firestore document ID
  String id;

  // Vehicle details
  String name;
  String vin;
  int year;
  int odometer;

  // Diagnostic trouble codes
  List<String> diagnosticTroubleCodes;

  // BLE
  String deviceId;

  Vehicle({
    required this.deviceId,
    this.id = '',
    this.name = 'Unknown',
    this.vin = 'Unknown',
    this.year = 0,
    this.odometer = 0,
    List<String>? diagnosticTroubleCodes,
  }) : diagnosticTroubleCodes = diagnosticTroubleCodes ?? [];

  // Factory constructor to create Vehicle from Firestore document
  factory Vehicle.fromMap(String id, Map<String, dynamic> data) {
    return Vehicle(
      deviceId: data['deviceId'] ?? '',
      id: id,
      name: data['name'] ?? 'Unknown',
      vin: data['vin'] ?? 'Unknown',
      year: int.tryParse(data['year'].toString()) ?? 0,
      odometer: int.tryParse(data['odometer'].toString()) ?? 0,
      diagnosticTroubleCodes: List<String>.from(data['diagnosticTroubleCodes'] ?? []),
    );
  }

  // Convert Vehicle to a map for Firestore
  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        // Doc ID is not stored within the document, it's managed by Firestore
        'name': name,
        'vin': vin,
        'year': year,
        'odometer': odometer,
        'diagnosticTroubleCodes': diagnosticTroubleCodes,
      };

  // Update methods
  void updateName(String newName) => name = newName;
  void updateVin(String newVin) => vin = newVin;
  void updateYear(int newYear) => year = newYear;
  void updateOdometer(int newOdometer) => odometer = newOdometer;
  void addDiagnosticTroubleCode(String code) {
    if (!diagnosticTroubleCodes.contains(code)) {
      diagnosticTroubleCodes.add(code);
    }
  }
  void removeDiagnosticTroubleCode(String code) {
    diagnosticTroubleCodes.remove(code);
  }
  void clearDiagnosticTroubleCodes() {
    diagnosticTroubleCodes.clear();
  }

  // Copy method
  Vehicle copyWith({
    String? deviceId,
    String? id,
    String? name,
    String? vin,
    int? year,
    int? odometer,
    List<String>? diagnosticTroubleCodes,
  }) {
    return Vehicle(
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      vin: vin ?? this.vin,
      year: year ?? this.year,
      odometer: odometer ?? this.odometer,
      diagnosticTroubleCodes: diagnosticTroubleCodes ?? List.from(this.diagnosticTroubleCodes),
    );
  }
}
