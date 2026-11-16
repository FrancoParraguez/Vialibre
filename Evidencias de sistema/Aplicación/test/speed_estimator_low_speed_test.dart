import 'package:flutter_test/flutter_test.dart';
import 'package:via_libre/services/speed_estimator.dart';

SpeedSample _s(int sec, double kmh, {double acc = 0.5}) => SpeedSample(
      timestamp: DateTime(2026, 1, 1).add(Duration(seconds: sec)),
      speedMs: kmh / 3.6,
      speedAccuracyMs: acc,
      accuracyM: 5,
      lat: -33.0,
      lng: -70.0,
    );

void main() {
  test('baja rápido de 40 a 5 km/h sin quedarse en valores altos', () {
    final e = SpeedEstimator();
    for (var i = 0; i < 5; i++) {
      e.addSample(_s(i, 40));
    }
    e.addSample(_s(5, 5));
    e.addSample(_s(6, 5));
    // La mediana(3) confirma el cambio en 2 muestras; luego sigue al instante.
    expect(e.addSample(_s(7, 5)), lessThan(10));
  });

  test('detenido reporta 0', () {
    final e = SpeedEstimator();
    e.addSample(_s(0, 30));
    for (var i = 1; i < 5; i++) {
      e.addSample(_s(i, 0));
    }
    expect(e.addSample(_s(5, 0)), 0);
  });

  test('tras un hueco > 3 s no devuelve el valor viejo', () {
    final e = SpeedEstimator();
    for (var i = 0; i < 4; i++) {
      e.addSample(_s(i, 40));
    }
    expect(e.addSample(_s(20, 3)), lessThan(5));
  });
}
