// lib/models/vehicle_model.dart

import 'package:equatable/equatable.dart';

enum VehicleType { ambulancia, bomberos, carabineros, otro }

class VehicleModel extends Equatable {
  final String id;
  final String patente;
  final VehicleType tipo;
  final String institucionId;
  final String institucionNombre;
  final String? conductorAsignadoUid;
  final bool activo;
  final DateTime createdAt;

  const VehicleModel({
    required this.id,
    required this.patente,
    required this.tipo,
    required this.institucionId,
    required this.institucionNombre,
    this.conductorAsignadoUid,
    this.activo = true,
    required this.createdAt,
  });

  factory VehicleModel.fromMap(Map<String, dynamic> map) {
    return VehicleModel(
      id: map['id'] as String,
      patente: map['patente'] as String,
      tipo: VehicleType.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => VehicleType.otro,
      ),
      institucionId: map['institucion_id'] as String,
      institucionNombre: map['institucion_nombre'] as String,
      conductorAsignadoUid: map['conductor_asignado_uid'] as String?,
      activo: map['activo'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'patente': patente,
    'tipo': tipo.name,
    'institucion_id': institucionId,
    'institucion_nombre': institucionNombre,
    'conductor_asignado_uid': conductorAsignadoUid,
    'activo': activo,
    'created_at': createdAt.toIso8601String(),
  };

  VehicleModel copyWith({
    String? id,
    String? patente,
    VehicleType? tipo,
    String? institucionId,
    String? institucionNombre,
    String? conductorAsignadoUid,
    bool? activo,
    DateTime? createdAt,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      patente: patente ?? this.patente,
      tipo: tipo ?? this.tipo,
      institucionId: institucionId ?? this.institucionId,
      institucionNombre: institucionNombre ?? this.institucionNombre,
      conductorAsignadoUid: conductorAsignadoUid ?? this.conductorAsignadoUid,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get tipoLabel {
    switch (tipo) {
      case VehicleType.ambulancia:  return 'Ambulancia';
      case VehicleType.bomberos:    return 'Bomberos';
      case VehicleType.carabineros: return 'Carabineros';
      case VehicleType.otro:        return 'Otro';
    }
  }

  @override
  List<Object?> get props => [id, patente, tipo, institucionId, activo];
}
