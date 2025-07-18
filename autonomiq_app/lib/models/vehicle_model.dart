class Vehicle {
  // Vehicle Firestore ID
  final String id;

  // Vehicle details
  final String name;
  final String vin;
  final int year;
  final int odometer;

  // Diagnostic trouble codes
  final List<Map<String, String>> diagnosticTroubleCodes;

  // BLE
  final String deviceId;
  final bool isConnected;

  Vehicle({
    required this.id,
    required this.name,
    required this.vin,
    required this.year,
    required this.odometer,
    required this.diagnosticTroubleCodes,
    required this.deviceId,
    required this.isConnected,
  });

  // Factory constructor to create Vehicle from Firestore document
  factory Vehicle.fromMap(String id, Map<String, dynamic> data) {
    return Vehicle(
      id: id,
      name: data['name'] ?? 'Unknown',
      vin: data['vin'] ?? 'Unknown',
      year: int.tryParse(data['year'].toString()) ?? 0,
      odometer: int.tryParse(data['odometer'].toString()) ?? 0,
      diagnosticTroubleCodes: List<Map<String, String>>.from(data['diagnosticTroubleCodes'] ?? []),
      deviceId: data['deviceId'] ?? 'Unknown',
      isConnected: data['isConnected'] ?? false,
    );
  }

  // Convert Vehicle to a map for Firestore
  Map<String, dynamic> toMap() => {
    'name': name,
    'vin': vin,
    'year': year,
    'odometer': odometer,
    'diagnosticTroubleCodes': diagnosticTroubleCodes,
    'deviceId': deviceId,
    'isConnected': isConnected,
  };
}
