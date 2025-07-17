import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autonomiq_app/providers/auth_provider.dart';
import 'package:autonomiq_app/providers/vehicle_provider.dart';
import 'package:autonomiq_app/services/auth_service.dart';
import 'package:autonomiq_app/services/firestore_service.dart';
import 'package:autonomiq_app/models/vehicle_model.dart';

@GenerateMocks([
  FirebaseAuth,
  User,
  UserCredential,
  AppAuthProvider,
  AuthService,
  FirebaseFirestore,
  CollectionReference<Map<String, dynamic>>,
  DocumentReference<Map<String, dynamic>>,
  QuerySnapshot<Map<String, dynamic>>,
  QueryDocumentSnapshot<Map<String, dynamic>>,
  DocumentSnapshot<Map<String, dynamic>>,
  FirestoreService,
  VehicleProvider,
  Vehicle,
])
void main() {}