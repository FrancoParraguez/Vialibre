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

  const UserModel({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.rol,
    this.institucionId,
    this.activo = true,
    required this.createdAt,
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
  };

  UserModel copyWith({
    String? uid,
    String? nombre,
    String? email,
    UserRole? rol,
    String? institucionId,
    bool? activo,
    DateTime? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      institucionId: institucionId ?? this.institucionId,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [uid, nombre, email, rol, institucionId, activo, createdAt];
}
