import 'dart:async';

import 'package:autonomiq_app/models/vehicle_model.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import 'package:autonomiq_app/repositories/user_repository.dart';
import 'package:autonomiq_app/repositories/vehicle_repository.dart';
import 'package:autonomiq_app/services/auth_service.dart';
import 'package:autonomiq_app/services/ble_service.dart';
import 'package:autonomiq_app/services/permission_service.dart';
import 'package:autonomiq_app/utils/bluetooth_adapter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:mockito/annotations.dart';

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
  VehicleModel,

  // BLE
  BleService,
  BluetoothAdapter,
  DiscoveredDevice,
  ConnectionStateUpdate,
  QualifiedCharacteristic,
  StreamSubscription,

  // Permission abstraction
  PermissionService,
])
void main() {}