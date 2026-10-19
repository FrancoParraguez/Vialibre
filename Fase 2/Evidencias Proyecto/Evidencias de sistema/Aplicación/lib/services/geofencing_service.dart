// lib/services/geofencing_service.dart
// Motor de geofencing predictivo.
// Fórmula: d = T × ((Ve - Vc) / 3.6)
// Donde Ve = velocidad del vehículo de emergencia (km/h)
//       Vc = velocidad del conductor particular (km/h)
// Resultado d en metros, clampado entre 200 m y 500 m (spec R5.4).

import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import '../core/constants.dart';
import '../models/location_model.dart';

class GeofencingService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Constantes de filtrado de datos GPS (spec R5.5 / R5.6) ───
  /// Antigüedad máxima aceptable de un dato GPS (ms). Datos más viejos
  /// que esto se consideran obsoletos.
  static const int _maxDataAgeMs = 5000;

  /// Precisión GPS máxima aceptable (m). Lecturas con peor precisión
  /// se descartan para evitar alertas falsas.
  static const double _maxGpsAccuracyM = 50.0;

  /// Número de muestras consecutivas necesarias para confirmar tendencia
  /// de acercamiento (spec R5.5).
  static const int _tendenciaMuestras = 2;

  /// Factor de histéresis: la alerta se limpia sólo cuando la distancia
  /// supera umbral × _histericaFactor (spec R5.6 / R6.5).
  static const double _histericaFactor = 1.2;

  // ── Cálculo del radio de alerta ───────────────────────────────
  /// Devuelve la distancia de alerta en metros, clampada entre 200 m y
  /// 500 m. Si Ve ≤ Vc se aplica el mínimo de 200 m (spec R5.4).
  static double calcularRadioAlerta({
    required double velocidadEmergenciaKmh,
    required double velocidadParticularKmh,
  }) {
    const double minMetros = 200.0;
    const double maxMetros = 500.0;
    // Si Ve <= Vc, diff = 0 → raw = 0 → clamp devuelve minMetros (spec R5.4)
    final diff =
        math.max(velocidadEmergenciaKmh - velocidadParticularKmh, 0.0);
    final raw = AppConstants.alertLeadTimeSec * (diff / 3.6);
    return raw.clamp(minMetros, maxMetros);
  }

  // ── Validación de dato GPS (spec R5.6) ────────────────────────
  /// Retorna `true` si el dato de ubicación es reciente y suficientemente
  /// preciso para usarse en el cálculo de geofencing.
  static bool esDatoValido(LocationModel loc, {DateTime? ahora}) {
    final now = ahora ?? DateTime.now();
    final age = now.difference(loc.timestamp).inMilliseconds;
    if (age > _maxDataAgeMs) return false;
    if ((loc.accuracy ?? 0) > _maxGpsAccuracyM && (loc.accuracy ?? 0) > 0) {
      return false;
    }
    return true;
  }

  // ── Evaluación de proximidad con tendencia e histéresis ───────
  /// Evalúa si se debe disparar o limpiar una alerta.
  ///
  /// [distancias] = últimas N distancias en orden cronológico (más
  ///                antiguo primero).
  /// [umbral]     = resultado de [calcularRadioAlerta].
  /// [yaAlertado] = si ya se disparó una alerta para esta emergencia.
  ///
  /// Requiere al menos 2 muestras para confirmar tendencia (spec R5.5).
  /// La alerta sólo se limpia cuando la distancia supera umbral × 1.2
  /// (histéresis, spec R6.5).
  static ProximityResult evaluarProximidad({
    required List<double> distancias,
    required double umbral,
    required bool yaAlertado,
  }) {
    if (distancias.length < _tendenciaMuestras) {
      return const ProximityResult(disparar: false, limpiar: false);
    }
    final ultima = distancias.last;
    final penultima = distancias[distancias.length - 2];
    final acercandose = ultima < penultima;
    final enRadio = ultima <= umbral;
    final fuera = ultima > umbral * _histericaFactor;

    if (!yaAlertado && enRadio && acercandose) {
      return const ProximityResult(disparar: true, limpiar: false);
    }
    if (yaAlertado && fuera) {
      return const ProximityResult(disparar: false, limpiar: true);
    }
    return const ProximityResult(disparar: false, limpiar: false);
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
  /// Retorna `true` si el conductor particular está dentro del radio de
  /// alerta. Usa el radio clampado (200–500 m).
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

    final distancia = distanciaMetros(
      lat1: emergencyLocation.lat,
      lng1: emergencyLocation.lng,
      lat2: particularLocation.lat,
      lng2: particularLocation.lng,
    );

    return distancia <= radio;
  }

  // ── Stream: monitorear si el conductor está en alerta ─────────
  /// Escucha la ubicación del vehículo de emergencia activo y emite un
  /// [GeofenceEvent] cada vez que cambia la posición.
  ///
  /// Novedades (spec R5.4 / R5.6):
  /// - Datos obsoletos o imprecisos se descartan antes de calcular radio.
  /// - El radio usa [calcularRadioAlerta] con clamp 200–500 m.
  /// - La velocidad del particular por defecto es [AppConstants.defaultParticularSpeedKmh].
  Stream<GeofenceEvent> watchGeofence({
    required String emergencyVehicleId,
    required LocationModel particularLocation,
  }) {
    return watchEmergencyLocationV2(emergencyVehicleId).map((emergLoc) {
      if (emergLoc == null) {
        return const GeofenceEvent(enRadio: false, radio: 0, distancia: 0);
      }

      // Filtrar datos obsoletos o imprecisos (spec R5.6)
      if (!esDatoValido(emergLoc)) {
        return const GeofenceEvent(enRadio: false, radio: 0, distancia: 0);
      }

      final radio = calcularRadioAlerta(
        velocidadEmergenciaKmh: emergLoc.speedKmh,
        velocidadParticularKmh: particularLocation.speedKmh > 0
            ? particularLocation.speedKmh
            : AppConstants.defaultParticularSpeedKmh,
      );

      final distancia = distanciaMetros(
        lat1: emergLoc.lat,
        lng1: emergLoc.lng,
        lat2: particularLocation.lat,
        lng2: particularLocation.lng,
      );

      return GeofenceEvent(
        enRadio: distancia <= radio,
        radio: radio,
        distancia: distancia,
        emergencyLocation: emergLoc,
      );
    });
  }

  // ── Obtener todas las emergencias activas ─────────────────────
  /// Devuelve los driver_uids de todas las emergencias activas.
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

  // ── Escuchar ubicación de emergencia con fallback ─────────────
  /// Intenta leer current_location del nodo active_emergencies (formato
  /// task2.md). Si no existe, hace fallback a active_locations (formato
  /// legacy de LocationService).
  Stream<LocationModel?> watchEmergencyLocationV2(String driverUid) {
    final controller = StreamController<LocationModel?>();
    bool usingFallback = false;

    // Listener principal: active_emergencies/{uid}/current_location
    final mainSub = _db
        .ref(
            '${AppConstants.rtdbActiveEmergencies}/$driverUid/current_location')
        .onValue
        .listen((event) {
      final data = event.snapshot.value;
      if (data != null) {
        usingFallback = false;
        final map = Map<String, dynamic>.from(data as Map);
        controller.add(LocationModel(
          id: 'emergency_$driverUid',
          ownerId: driverUid,
          lat: (map['lat'] as num).toDouble(),
          lng: (map['lng'] as num).toDouble(),
          speedKmh: (map['speed_kmh'] as num?)?.toDouble() ?? 0.0,
          heading: (map['heading'] as num?)?.toDouble(),
          timestamp: DateTime.now(),
        ));
      } else if (!usingFallback) {
        // current_location es null → activar fallback
        usingFallback = true;
        controller.add(null);
      }
    });

    // Listener fallback: active_locations/{uid} (vía LocationService)
    final fallbackSub = _db
        .ref('${AppConstants.rtdbActiveLocations}/$driverUid')
        .onValue
        .listen((event) {
      // Solo emitir del fallback si el principal no tiene datos
      if (usingFallback) {
        final data = event.snapshot.value;
        if (data == null) {
          controller.add(null);
          return;
        }
        final map = Map<String, dynamic>.from(data as Map);
        controller.add(LocationModel(
          id: map['id'] as String? ?? 'loc_$driverUid',
          ownerId: map['owner_id'] as String? ?? driverUid,
          lat: (map['lat'] as num).toDouble(),
          lng: (map['lng'] as num).toDouble(),
          speedKmh: (map['speed_kmh'] as num).toDouble(),
          heading: (map['heading'] as num?)?.toDouble(),
          accuracy: (map['accuracy'] as num?)?.toDouble(),
          timestamp: map['timestamp'] != null
              ? DateTime.parse(map['timestamp'] as String)
              : DateTime.now(),
        ));
      }
    });

    controller.onCancel = () {
      mainSub.cancel();
      fallbackSub.cancel();
    };

    return controller.stream;
  }
}

// ── Resultado del evento de geofencing ───────────────────────────
class GeofenceEvent {
  final bool enRadio;
  final double radio; // metros
  final double distancia; // metros
  final LocationModel? emergencyLocation;

  const GeofenceEvent({
    required this.enRadio,
    required this.radio,
    required this.distancia,
    this.emergencyLocation,
  });
}

// ── Resultado de evaluación de proximidad con tendencia ──────────
/// Encapsula la decisión del motor de geofencing para una iteración:
/// si hay que disparar una nueva alerta o limpiar una existente.
class ProximityResult {
  final bool disparar;
  final bool limpiar;

  const ProximityResult({required this.disparar, required this.limpiar});
}
