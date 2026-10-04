// lib/services/geofencing_service.dart
// Motor de geofencing predictivo.
// Fórmula: d = 30 * ((Ve - Vc) / 3.6)
// Donde Ve = velocidad del vehículo de emergencia (km/h)
//       Vc = velocidad del conductor particular (km/h)
// Resultado d en metros.

import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import '../core/constants.dart';
import '../models/location_model.dart';

class GeofencingService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Cálculo del radio de alerta ───────────────────────────────
  /// Devuelve la distancia de alerta en metros.
  /// Si Ve <= Vc, el vehículo de emergencia no se acerca → retorna 0.
  static double calcularRadioAlerta({
    required double velocidadEmergenciaKmh,
    required double velocidadParticularKmh,
  }) {
    final diff = velocidadEmergenciaKmh - velocidadParticularKmh;
    if (diff <= 0) return 0.0;
    return AppConstants.alertLeadTimeSec * (diff / 3.6);
  }

  // ── Distancia entre dos puntos (Haversine) ────────────────────
  /// Devuelve la distancia en metros entre dos coordenadas.
  static double distanciaMetros({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const double radioTierraM = 6371000;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radioTierraM * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  // ── Verificar si un conductor está dentro del geofence ────────
  /// Retorna `true` si el conductor particular está dentro del radio de alerta.
  static bool conductorEnRadio({
    required LocationModel emergencyLocation,
    required LocationModel particularLocation,
    double? velocidadParticularKmh,
  }) {
    final radio = calcularRadioAlerta(
      velocidadEmergenciaKmh: emergencyLocation.speedKmh,
      velocidadParticularKmh:
          velocidadParticularKmh ?? AppConstants.defaultParticularSpeedKmh,
    );

    if (radio <= 0) return false;

    final distancia = distanciaMetros(
      lat1: emergencyLocation.lat,
      lng1: emergencyLocation.lng,
      lat2: particularLocation.lat,
      lng2: particularLocation.lng,
    );

    return distancia <= radio;
  }

  // ── Stream: monitorear si el conductor está en alerta ─────────
  /// Escucha la ubicación del vehículo de emergencia activo y emite
  /// `true` cuando el conductor particular entra al geofence.
  Stream<GeofenceEvent> watchGeofence({
    required String emergencyVehicleId,
    required LocationModel particularLocation,
  }) {
    return _db
        .ref('${AppConstants.rtdbActiveLocations}/$emergencyVehicleId')
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) {
        return const GeofenceEvent(enRadio: false, radio: 0, distancia: 0);
      }

      final emergLoc = LocationModel.fromMap(
        Map<String, dynamic>.from(data as Map),
      );

      final radio = calcularRadioAlerta(
        velocidadEmergenciaKmh: emergLoc.speedKmh,
        velocidadParticularKmh: particularLocation.speedKmh,
      );

      final distancia = distanciaMetros(
        lat1: emergLoc.lat,
        lng1: emergLoc.lng,
        lat2: particularLocation.lat,
        lng2: particularLocation.lng,
      );

      return GeofenceEvent(
        enRadio: distancia <= radio && radio > 0,
        radio: radio,
        distancia: distancia,
        emergencyLocation: emergLoc,
      );
    });
  }

  // ── Obtener todas las emergencias activas ─────────────────────
  Stream<List<String>> watchActiveEmergencyVehicleIds() {
    return _db
        .ref(AppConstants.rtdbActiveEmergencies)
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) return <String>[];
      return (data as Map).keys.map((k) => k.toString()).toList();
    });
  }
}

// ── Resultado del evento de geofencing ───────────────────────────
class GeofenceEvent {
  final bool enRadio;
  final double radio;          // metros
  final double distancia;      // metros
  final LocationModel? emergencyLocation;

  const GeofenceEvent({
    required this.enRadio,
    required this.radio,
    required this.distancia,
    this.emergencyLocation,
  });
}
