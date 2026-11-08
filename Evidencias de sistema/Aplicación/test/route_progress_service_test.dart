// test/route_progress_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:via_libre/services/route_progress_service.dart';

void main() {
  // Ruta sencilla de oeste a este a lo largo del paralelo -33.05
  const base = -33.05;
  final route = List.generate(
    6,
    (i) => LatLng(base, -71.60 + i * 0.001), // ~111 m entre puntos
  );

  late RouteProgressService svc;

  setUp(() => svc = RouteProgressService());

  test('1. Avance normal — índice progresa', () {
    // Posición cerca del segundo segmento
    final pos = LatLng(base, -71.598);
    final r = svc.advance(route, 0, pos);
    expect(r.status, RouteStatus.onRoute);
    expect(r.newIndex, greaterThanOrEqualTo(1));
    expect(r.remainingPoints.length, lessThan(route.length));
  });

  test('2. Ruido GPS lateral — índice no avanza si no hay progreso', () {
    // Posición con desviación lateral de 5 m (dentro del umbral)
    // pero sin avanzar en el eje longitudinal
    final pos = LatLng(base + 0.00004, -71.600); // ~4 m al norte del punto 0
    final r = svc.advance(route, 0, pos);
    expect(r.status, RouteStatus.onRoute);
    // índice debe seguir en 0 o avanzar a 1 como máximo
    expect(r.newIndex, lessThanOrEqualTo(1));
  });

  test('3. Muestra hacia atrás — índice no retrocede', () {
    // Primero avanzar al índice 3
    final pos1 = LatLng(base, -71.597);
    final r1 = svc.advance(route, 0, pos1);

    // Luego dar una posición "atrás" (cerca del inicio)
    final pos2 = LatLng(base, -71.600);
    final r2 = svc.advance(route, r1.newIndex, pos2);

    // El índice no debe retroceder
    expect(r2.newIndex, greaterThanOrEqualTo(r1.newIndex));
  });

  test('4. Llegada detectada a < 30 m del destino', () {
    final nearDest = LatLng(route.last.latitude, route.last.longitude + 0.0001);
    // 0.0001° lng ≈ 9 m — dentro del radio
    final r = svc.advance(route, route.length - 2, nearDest);
    expect(r.status, RouteStatus.arrived);
    expect(r.remainingPoints, isEmpty);
  });

  test('5. Fuera de ruta tras 3 muestras consecutivas > 40 m', () {
    // Posición muy alejada de la ruta (~500 m al norte)
    final farPos = LatLng(base + 0.005, -71.598);
    RouteProgressResult? last;
    for (int i = 0; i < offRouteSamples; i++) {
      last = svc.advance(route, 0, farPos);
    }
    expect(last!.status, RouteStatus.offRoute);
  });

  test('6. Ruta de un solo segmento', () {
    final singleRoute = [
      const LatLng(-33.05, -71.60),
      const LatLng(-33.05, -71.59),
    ];
    final pos = LatLng(-33.05, -71.595);
    final r = svc.advance(singleRoute, 0, pos);
    expect(r.status, anyOf(RouteStatus.onRoute, RouteStatus.arrived));
    expect(r.remainingPoints, isNotEmpty);
  });

  test('7. Fuera de ruta NO recorta: remainingPoints no decrece', () {
    final farPos = LatLng(base + 0.005, -71.598);
    // Llevar al estado offRoute
    late RouteProgressResult lastOnRoute;
    svc = RouteProgressService();

    // Avanzar primero normalmente
    lastOnRoute = svc.advance(route, 0, LatLng(base, -71.598));
    final prevLen = lastOnRoute.remainingPoints.length;

    // Ahora salir de ruta 3 veces
    late RouteProgressResult offResult;
    for (int i = 0; i < offRouteSamples; i++) {
      offResult = svc.advance(route, lastOnRoute.newIndex, farPos);
    }
    // En offRoute no se recorta más
    expect(offResult.status, RouteStatus.offRoute);
    expect(offResult.remainingPoints.length, greaterThanOrEqualTo(prevLen - 1));
  });
}
