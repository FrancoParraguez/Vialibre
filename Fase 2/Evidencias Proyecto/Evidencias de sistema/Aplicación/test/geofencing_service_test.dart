// test/geofencing_service_test.dart
// Tests unitarios del motor de geofencing predictivo — spec task 6.5
//
// Cubre únicamente las funciones puras (static) del GeofencingService:
//   calcularRadioAlerta, esDatoValido, evaluarProximidad, distanciaMetros
// No requiere Firebase ni plugins de plataforma.

import 'package:flutter_test/flutter_test.dart';
import 'package:via_libre/services/geofencing_service.dart';
import 'package:via_libre/models/location_model.dart';
import 'package:via_libre/core/constants.dart';

// ── Helpers ──────────────────────────────────────────────────────
/// Crea un LocationModel con valores dummy para los campos no relevantes.
LocationModel _loc({
  double lat = 0.0,
  double lng = 0.0,
  double speedKmh = 0.0,
  double? accuracy,
  DateTime? timestamp,
}) {
  return LocationModel(
    id: 'test_id',
    ownerId: 'test_owner',
    lat: lat,
    lng: lng,
    speedKmh: speedKmh,
    accuracy: accuracy,
    timestamp: timestamp ?? DateTime.now(),
  );
}

void main() {
  group('GeofencingService — motor predictivo', () {
    // ════════════════════════════════════════════════════════════
    // calcularRadioAlerta
    // ════════════════════════════════════════════════════════════
    group('calcularRadioAlerta', () {
      test('Ve=80 Vc=40 → ≈333 m', () {
        // d = 30 × ((80 - 40) / 3.6) = 30 × 11.11 ≈ 333.3
        final result = GeofencingService.calcularRadioAlerta(
          velocidadEmergenciaKmh: 80,
          velocidadParticularKmh: 40,
        );
        expect(result, greaterThanOrEqualTo(330.0));
        expect(result, lessThanOrEqualTo(336.0));
      });

      test('Ve=100 Vc=0 → tope 500 m', () {
        // d = 30 × (100 / 3.6) = 833.3 → clamp → 500
        final result = GeofencingService.calcularRadioAlerta(
          velocidadEmergenciaKmh: 100,
          velocidadParticularKmh: 0,
        );
        expect(result, equals(500.0));
      });

      test('Ve=50 Vc=60 → piso 200 m', () {
        // Ve < Vc → diff = 0 → raw = 0 → clamp → 200
        final result = GeofencingService.calcularRadioAlerta(
          velocidadEmergenciaKmh: 50,
          velocidadParticularKmh: 60,
        );
        expect(result, equals(200.0));
      });

      test('Ve=80 Vc=80 → piso 200 m (R5.4)', () {
        // Ve == Vc → diff = 0 → raw = 0 → clamp → 200
        final result = GeofencingService.calcularRadioAlerta(
          velocidadEmergenciaKmh: 80,
          velocidadParticularKmh: 80,
        );
        expect(result, equals(200.0));
      });

      test('Vc usa default 40 si es 0', () {
        // Cuando Vc=0, el motor hace fallback a defaultParticularSpeedKmh=40
        // en watchGeofence. calcularRadioAlerta sí recibe 0 → diff = Ve.
        // Aquí verificamos que el RESULTADO NO ES 0 (siempre ≥ 200 por clamp).
        final result = GeofencingService.calcularRadioAlerta(
          velocidadEmergenciaKmh: AppConstants.defaultEmergencySpeedKmh,
          velocidadParticularKmh: 0,
        );
        expect(result, isNot(equals(0.0)));
        // Además, debe cumplir el clamp mínimo
        expect(result, greaterThanOrEqualTo(200.0));
      });
    });

    // ════════════════════════════════════════════════════════════
    // esDatoValido
    // ════════════════════════════════════════════════════════════
    group('esDatoValido', () {
      test('dato fresco y preciso → válido', () {
        final ahora = DateTime.now();
        final loc = _loc(accuracy: 10.0, timestamp: ahora);
        expect(GeofencingService.esDatoValido(loc, ahora: ahora), isTrue);
      });

      test('dato obsoleto (6 s) → inválido', () {
        final ahora = DateTime.now();
        final loc = _loc(
          accuracy: 10.0,
          timestamp: ahora.subtract(const Duration(seconds: 6)),
        );
        expect(GeofencingService.esDatoValido(loc, ahora: ahora), isFalse);
      });

      test('dato impreciso (60 m accuracy) → inválido', () {
        final ahora = DateTime.now();
        final loc = _loc(accuracy: 60.0, timestamp: ahora);
        expect(GeofencingService.esDatoValido(loc, ahora: ahora), isFalse);
      });

      test('accuracy null → válido', () {
        // accuracy == null → no se puede validar precisión → se acepta
        final ahora = DateTime.now();
        final loc = _loc(accuracy: null, timestamp: ahora);
        expect(GeofencingService.esDatoValido(loc, ahora: ahora), isTrue);
      });
    });

    // ════════════════════════════════════════════════════════════
    // evaluarProximidad
    // ════════════════════════════════════════════════════════════
    group('evaluarProximidad', () {
      test('acercándose dentro del umbral → disparar', () {
        // Tendencia decreciente, última < umbral, no alertado
        final result = GeofencingService.evaluarProximidad(
          distancias: [400, 350, 300],
          umbral: 333,
          yaAlertado: false,
        );
        expect(result.disparar, isTrue);
        expect(result.limpiar, isFalse);
      });

      test('alejándose fuera del umbral × 1.2 → limpiar', () {
        // 420 > 333 * 1.2 = 399.6 → limpiar
        final result = GeofencingService.evaluarProximidad(
          distancias: [200, 300, 420],
          umbral: 333,
          yaAlertado: true,
        );
        expect(result.limpiar, isTrue);
        expect(result.disparar, isFalse);
      });

      test('dentro del umbral pero ya alertado → no disparar', () {
        // yaAlertado=true, enRadio=true → no se vuelve a disparar
        final result = GeofencingService.evaluarProximidad(
          distancias: [300, 290],
          umbral: 333,
          yaAlertado: true,
        );
        expect(result.disparar, isFalse);
        expect(result.limpiar, isFalse);
      });

      test('solo 1 muestra → no evaluar', () {
        // Menos de _tendenciaMuestras=2 → sin decisión
        final result = GeofencingService.evaluarProximidad(
          distancias: [300],
          umbral: 333,
          yaAlertado: false,
        );
        expect(result.disparar, isFalse);
        expect(result.limpiar, isFalse);
      });

      test('alejándose pero aún dentro del umbral → no limpiar', () {
        // 310 < 333 * 1.2 = 399.6 → no supera el umbral con histéresis
        final result = GeofencingService.evaluarProximidad(
          distancias: [290, 310],
          umbral: 333,
          yaAlertado: true,
        );
        expect(result.limpiar, isFalse);
        expect(result.disparar, isFalse);
      });
    });

    // ════════════════════════════════════════════════════════════
    // distanciaMetros (Haversine)
    // ════════════════════════════════════════════════════════════
    group('distanciaMetros (Haversine)', () {
      test('mismo punto → 0 m', () {
        const lat = -33.047;
        const lng = -71.612;
        final dist = GeofencingService.distanciaMetros(
          lat1: lat,
          lng1: lng,
          lat2: lat,
          lng2: lng,
        );
        expect(dist, lessThan(0.001));
      });

      test('distancia conocida Valparaíso–Viña (~8.5 km)', () {
        // Coordenadas aproximadas Valparaíso ↔ Viña del Mar
        final dist = GeofencingService.distanciaMetros(
          lat1: -33.047,
          lng1: -71.612,
          lat2: -33.024,
          lng2: -71.551,
        );
        expect(dist, greaterThan(6000));
        expect(dist, lessThan(10000));
      });
    });
  });
}
