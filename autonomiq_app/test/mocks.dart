import 'package:autonomiq_app/services/ble_service.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import 'package:autonomiq_app/repositories/user_repository.dart';
import 'package:autonomiq_app/repositories/vehicle_repository.dart';
import 'package:autonomiq_app/services/auth_service.dart';
import 'package:autonomiq_app/services/permission_service.dart';
import 'package:autonomiq_app/models/vehicle_model.dart';
import 'package:autonomiq_app/utils/bluetooth_adapter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

@GenerateMocks([
  // Firebase
  FirebaseAuth,
  User,
  UserCredential,
  FirebaseFirestore,
  CollectionReference<Map<String, dynamic>>,
  DocumentReference<Map<String, dynamic>>,
  DocumentSnapshot<Map<String, dynamic>>,
  QuerySnapshot<Map<String, dynamic>>,
  QueryDocumentSnapshot<Map<String, dynamic>>,

  // Repositories
  UserRepository,
  VehicleRepository,

  // Providers & services
  AppAuthProvider,
  AuthService,
  VehicleProvider,
  Vehicle,

  // BLE
  BleService,
  BluetoothAdapter,
  BluetoothDevice,
  ScanResult,
  StreamSubscription,

  // Permission abstraction
  PermissionService,
])
void main() {}
