import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user with their details stored in Firestore.
class UserObject {
  /// Unique identifier for the user.
  final String uid;

  /// Timestamp when the user account was created.
  final DateTime? createdAt;

  /// User's email address.
  String? email;

  /// Indicates if the user is in demo mode.
  bool? demoMode;

  /// Constructor for UserModel.
  ///
  /// [uid] is required to identify the user.
  /// Other fields are optional and can be null.
  UserObject({required this.uid, this.email, this.createdAt, this.demoMode});

  /// Creates a UserModel instance from a Firestore document.
  ///
  /// [uid] is the Firestore document ID.
  /// [map] is the Firestore document data as a map.
  /// Converts Firestore Timestamp to DateTime for [createdAt].
  factory UserObject.fromMap(String uid, Map<String, dynamic> map) {
    return UserObject(
      uid: uid,
      email: map['email'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      demoMode: map['demoMode'] as bool?,
    );
  }

  /// Converts the UserModel instance to a map for Firestore storage.
  ///
  /// Returns a map of user attributes, excluding the UID.
  Map<String, dynamic> toMap() {
    return {'email': email, 'demoMode': demoMode, 'createdAt': createdAt};
  }

  /// Creates a copy of the UserModel with optional updated fields.
  ///
  /// Allows partial updates to user attributes while preserving unchanged values.
  /// Returns a new UserModel instance.
  UserObject copyWith({String? email, DateTime? createdAt, bool? demoMode}) {
    return UserObject(
      uid: uid,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      demoMode: demoMode ?? this.demoMode,
    );
  }
}
