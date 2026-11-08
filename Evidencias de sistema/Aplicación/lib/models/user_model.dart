// lib/models/user_model.dart

import 'package:equatable/equatable.dart';

enum UserRole { particular, emergencia, admin }

class UserModel extends Equatable {
  final String uid;
  final String nombre;
  final String email;
  final UserRole rol;
  final String? institucionId;
  final bool activo;
  final DateTime createdAt;
  final int? privacyNoticeVersion;
  final DateTime? privacyNoticeAckAt;

  const UserModel({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.rol,
    this.institucionId,
    this.activo = true,
    required this.createdAt,
    this.privacyNoticeVersion,
    this.privacyNoticeAckAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String,
      nombre: map['nombre'] as String,
      email: map['email'] as String,
      rol: UserRole.values.firstWhere(
        (r) => r.name == map['rol'],
        orElse: () => UserRole.particular,
      ),
      institucionId: map['institucion_id'] as String?,
      activo: map['activo'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      privacyNoticeVersion: map['privacy_notice_version'] as int?,
      privacyNoticeAckAt: map['privacy_notice_ack_at'] != null
          ? DateTime.parse(map['privacy_notice_ack_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'nombre': nombre,
    'email': email,
    'rol': rol.name,
    'institucion_id': institucionId,
    'activo': activo,
    'created_at': createdAt.toIso8601String(),
    if (privacyNoticeVersion != null)
      'privacy_notice_version': privacyNoticeVersion,
    if (privacyNoticeAckAt != null)
      'privacy_notice_ack_at': privacyNoticeAckAt!.toIso8601String(),
  };

  UserModel copyWith({
    String? uid,
    String? nombre,
    String? email,
    UserRole? rol,
    String? institucionId,
    bool? activo,
    DateTime? createdAt,
    int? privacyNoticeVersion,
    DateTime? privacyNoticeAckAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      institucionId: institucionId ?? this.institucionId,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      privacyNoticeVersion: privacyNoticeVersion ?? this.privacyNoticeVersion,
      privacyNoticeAckAt: privacyNoticeAckAt ?? this.privacyNoticeAckAt,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        nombre,
        email,
        rol,
        institucionId,
        activo,
        createdAt,
        privacyNoticeVersion,
        privacyNoticeAckAt,
      ];
}
