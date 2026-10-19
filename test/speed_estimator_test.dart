// test/speed_estimator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:via_libre/services/speed_estimator.dart';

SpeedSample _sample({
  required DateTime t,
  double speedMs = -1,
  double speedAccMs = 5.0,
  double accuracy = 10.0,
  double lat = -33.05,
  double lng = -71.60,
}) =>
    SpeedSample(
      timestamp: t,
      speedMs: speedMs,
      speedAccuracyMs: speedAccMs,
      accuracyM: accuracy,
      lat: lat,
      lng: lng,
    );

void main() {
  late SpeedEstimator est;
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  setUp(() => est = SpeedEstimator());

  test('1. Velocidad constante 60 km/h — error ≤ 3 km/h', () {
    // 60 km/h = 16.67 m/s
    const speedMs = 60 / 3.6;
    double? last;
    for (int i = 0; i < 10; i++) {
      last = est.addSample(_sample(
        t: t0.add(Duration(seconds: i)),
        speedMs: speedMs,
        speedAccMs: 0.5,
      ));
    }
    expect(last, isNotNull);
    expect((last! - 60).abs(), lessThanOrEqualTo(3.0));
  });

  test('2. Detenido con deriva GPS — devuelve 0', () {
    // speedMs < 2 km/h = 0.555 m/s
    double? last;
    for (int i = 0; i < 6; i++) {
      last = est.addSample(_sample(
        t: t0.add(Duration(seconds: i)),
        speedMs: 0.3,
        speedAccMs: 0.5,
      ));
    }
    expect(last, 0.0);
  });

  test('3. Salto de posición 200 m en 1 s (~720 km/h) — descartado', () {
    // Primera muestra base
    est.addSample(_sample(t: t0, speedMs: 10, speedAccMs: 0.5));

    // Segunda muestra: posición 200 m al este (~0.0018° lng)
    final result = est.addSample(_sample(
      t: t0.add(const Duration(seconds: 1)),
      speedMs: -1,      // sin Doppler
      speedAccMs: 5.0,
      lat: -33.05,
      lng: -71.598,     // ~200 m lejos del punto inicial
    ));

    // Debe descartar o devolver valor previo razonable, no 720 km/h
    // Si devuelve null o ≤ 200 km/h es correcto
    if (result != null) {
      expect(result, lessThanOrEqualTo(200.0));
    }
  });

  test('4. speedMs=-1 con respaldo distancia/tiempo', () {
    // Primera muestra en lat/lng base
    est.addSample(_sample(
      t: t0,
      speedMs: -1,
      speedAccMs: 5.0,
      lat: -33.05000,
      lng: -71.60000,
    ));

    // Segunda muestra ~50 m al este en 1 s → ~180 km/h... pero usamos velocidad menor
    // Para velocidad ~10 km/h: 10/3.6 ≈ 2.78 m/s → 2.78 m en 1 s
    // 2.78 m ≈ 0.000025° lng
    final result = est.addSample(_sample(
      t: t0.add(const Duration(seconds: 1)),
      speedMs: -1,
      speedAccMs: 5.0,
      lat: -33.05000,
      lng: -71.59997, // ~2.7 m ≈ ~10 km/h
    ));
    // Con solo 2 muestras válidas, devuelve valor directo
    expect(result, isNotNull);
    expect(result!, greaterThan(0.0));
  });

  test('5. accuracy > 50 m — muestra descartada', () {
    // Muestra con mala precisión
    final result = est.addSample(_sample(
      t: t0,
      speedMs: 20,
      speedAccMs: 0.5,
      accuracy: 60.0, // > 50 m
    ));
    // Sin muestras previas válidas → null
    expect(result, isNull);
  });

  test('6. reset() limpia el estado', () {
    for (int i = 0; i < 5; i++) {
      est.addSample(_sample(
        t: t0.add(Duration(seconds: i)),
        speedMs: 10,
        speedAccMs: 0.5,
      ));
    }
    est.reset();
    // Después de reset, la primera muestra da resultado sin EMA previo
    final result = est.addSample(_sample(
      t: t0.add(const Duration(seconds: 10)),
      speedMs: 5,
      speedAccMs: 0.5,
    ));
    // Solo una muestra → devuelve valor directo (no null)
    expect(result, isNotNull);
  });
}
