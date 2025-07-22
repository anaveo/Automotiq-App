import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final DateTime? createdAt;

  String? email;
  bool? demoMode;
  
  UserModel({
    required this.uid,
    this.email,
    this.createdAt,
    this.demoMode,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      email: map['email'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      demoMode: map['demoMode'] as bool?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'demoMode': demoMode,
      'createdAt': createdAt,
    };
  }

  UserModel copyWith({
    String? email,
    DateTime? createdAt,
    bool? demoMode,
  }) {
    return UserModel(
      uid: uid,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      demoMode: demoMode ?? this.demoMode,
    );
  }
}
