class Vehicle {
  final String id;
  final String name;
  final String vin;
  final int year;
  final int odometer;
  final bool isConnected;
  final List<Map<String, String>> diagnosticTroubleCodes;

  Vehicle({
    required this.id,
    required this.name,
    required this.vin,
    required this.year,
    required this.odometer,
    required this.isConnected,
    required this.diagnosticTroubleCodes
  });

  factory Vehicle.fromMap(String id, Map<String, dynamic> data) {
    return Vehicle(
      id: id,
      name: data['name'],
      vin: data['vin'],
      year: int.tryParse(data['year'].toString()) ?? 0,
      odometer: int.tryParse(data['odometer'].toString()) ?? 0,
      isConnected: data['isConnected'] ?? false,
      diagnosticTroubleCodes: [] // Not stored on Firestore
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'vin': vin,
    'year': year,
    'odometer': odometer,
    'isConnected': isConnected,
  };
}
