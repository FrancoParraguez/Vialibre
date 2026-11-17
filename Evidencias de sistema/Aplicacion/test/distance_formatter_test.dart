// test/distance_formatter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:via_libre/core/distance_formatter.dart';

void main() {
  group('formatDistanceKm', () {
    test('0 m → < 0,1 km', () => expect(formatDistanceKm(0), '< 0,1 km'));
    test('99 m → < 0,1 km', () => expect(formatDistanceKm(99), '< 0,1 km'));
    test('100 m → 0,1 km',  () => expect(formatDistanceKm(100), '0,1 km'));
    // 350 m / 1000 = 0.35 km → Dart toStringAsFixed(1) = '0.3' (redondeo a par)
    test('350 m → 0,3 km',  () => expect(formatDistanceKm(350), '0,3 km'));
    test('1000 m → 1,0 km', () => expect(formatDistanceKm(1000), '1,0 km'));
    test('9999 m → 10,0 km',() => expect(formatDistanceKm(9999), '10,0 km'));
    test('12345 m → 12 km', () => expect(formatDistanceKm(12345), '12 km'));
    test('100000 m → 100 km', () => expect(formatDistanceKm(100000), '100 km'));
  });

  group('routeDistanceMeters', () {
    test('lista vacía → 0', () {
      expect(routeDistanceMeters([]), 0.0);
    });

    test('un solo punto → 0', () {
      expect(routeDistanceMeters([const LatLng(-33.05, -71.60)]), 0.0);
    });

    test('2 puntos ~111 m entre sí (0.001° lat) → dentro del ±1 %', () {
      // 1° lat ≈ 111 320 m → 0.001° ≈ 111,3 m
      const a = LatLng(-33.050, -71.600);
      const b = LatLng(-33.051, -71.600);
      final dist = routeDistanceMeters([a, b]);
      expect(dist, closeTo(111.3, 1.5)); // ±1.5 m de tolerancia
    });

    test('3 puntos — suma de 2 segmentos', () {
      const a = LatLng(-33.050, -71.600);
      const b = LatLng(-33.051, -71.600);
      const c = LatLng(-33.052, -71.600);
      final ab = routeDistanceMeters([a, b]);
      final abc = routeDistanceMeters([a, b, c]);
      expect(abc, closeTo(ab * 2, 2.0));
    });
  });
}
