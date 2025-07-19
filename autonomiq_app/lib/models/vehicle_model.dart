import 'dart:convert';
import 'dart:typed_data';

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
  final String deviceName; // Device name (usually VEEPEAK)
  final Uint8List manufacturerData; // Unique fingerprint

  Vehicle({
    required this.id,
    required this.name,
    required this.vin,
    required this.year,
    required this.odometer,
    required this.diagnosticTroubleCodes,
    required this.deviceName,
    required this.manufacturerData,
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
      deviceName: data['deviceName'] ?? '',
      manufacturerData: data['manufacturerData'] != null
          ? base64.decode(data['manufacturerData'])
          : Uint8List(0),
    );
  }

  // Convert Vehicle to a map for Firestore
  Map<String, dynamic> toMap() => {
    'name': name,
    'vin': vin,
    'year': year,
    'odometer': odometer,
    'diagnosticTroubleCodes': diagnosticTroubleCodes,
    'deviceName': deviceName,
    'manufacturerData': manufacturerData.isNotEmpty
        ? base64.encode(manufacturerData)
        : null,
  };

  Vehicle copyWith({
    String? id,
    String? name,
    String? vin,
    int? year,
    int? odometer,
    List<Map<String, String>>? diagnosticTroubleCodes,
    String? deviceName,
    Uint8List? manufacturerData,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      vin: vin ?? this.vin,
      year: year ?? this.year,
      odometer: odometer ?? this.odometer,
      diagnosticTroubleCodes: diagnosticTroubleCodes ?? this.diagnosticTroubleCodes,
      deviceName: deviceName ?? this.deviceName,
      manufacturerData: manufacturerData ?? this.manufacturerData,
    );
  }
}
