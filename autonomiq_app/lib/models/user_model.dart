import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String? name;
  final String? email;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    this.name,
    this.email,
    this.createdAt,
  });

  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    return UserModel(
      id: id,
      name: map['name'] as String?,
      email: map['email'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'createdAt': createdAt,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
