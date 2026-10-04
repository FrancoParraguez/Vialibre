// lib/models/emergency_model.dart

import 'package:equatable/equatable.dart';
import 'location_model.dart';

enum EmergencyStatus { activa, inactiva }

class RoutePoint {
  final double lat;
  final double lng;
  const RoutePoint({required this.lat, required this.lng});

  factory RoutePoint.fromMap(Map<String, dynamic> map) =>
      RoutePoint(lat: (map['lat'] as num).toDouble(), lng: (map['lng'] as num).toDouble());

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};
}

class EmergencyModel extends Equatable {
  final String id;
  final String vehicleId;
  final String conductorUid;
  final EmergencyStatus estado;
  final RoutePoint? origen;
  final RoutePoint? destino;
  final LocationModel? ultimaUbicacion;
  final int conductoresAlertados;
  final DateTime timestampInicio;
  final DateTime? timestampFin;

  const EmergencyModel({
    required this.id,
    required this.vehicleId,
    required this.conductorUid,
    required this.estado,
    this.origen,
    this.destino,
    this.ultimaUbicacion,
    this.conductoresAlertados = 0,
    required this.timestampInicio,
    this.timestampFin,
  });

  bool get estaActiva => estado == EmergencyStatus.activa;

  factory EmergencyModel.fromMap(Map<String, dynamic> map) {
    return EmergencyModel(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      conductorUid: map['conductor_uid'] as String,
      estado: EmergencyStatus.values.firstWhere(
        (s) => s.name == map['estado'],
        orElse: () => EmergencyStatus.inactiva,
      ),
      origen: map['origen'] != null
          ? RoutePoint.fromMap(map['origen'] as Map<String, dynamic>)
          : null,
      destino: map['destino'] != null
          ? RoutePoint.fromMap(map['destino'] as Map<String, dynamic>)
          : null,
      conductoresAlertados: map['conductores_alertados'] as int? ?? 0,
      timestampInicio: DateTime.parse(map['timestamp_inicio'] as String),
      timestampFin: map['timestamp_fin'] != null
          ? DateTime.parse(map['timestamp_fin'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicle_id': vehicleId,
    'conductor_uid': conductorUid,
    'estado': estado.name,
    'origen': origen?.toMap(),
    'destino': destino?.toMap(),
    'conductores_alertados': conductoresAlertados,
    'timestamp_inicio': timestampInicio.toIso8601String(),
    'timestamp_fin': timestampFin?.toIso8601String(),
  };

  EmergencyModel copyWith({
    EmergencyStatus? estado,
    RoutePoint? origen,
    RoutePoint? destino,
    LocationModel? ultimaUbicacion,
    int? conductoresAlertados,
    DateTime? timestampFin,
  }) {
    return EmergencyModel(
      id: id,
      vehicleId: vehicleId,
      conductorUid: conductorUid,
      estado: estado ?? this.estado,
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      ultimaUbicacion: ultimaUbicacion ?? this.ultimaUbicacion,
      conductoresAlertados: conductoresAlertados ?? this.conductoresAlertados,
      timestampInicio: timestampInicio,
      timestampFin: timestampFin ?? this.timestampFin,
    );
  }

  @override
  List<Object?> get props => [id, vehicleId, estado, timestampInicio];
}
