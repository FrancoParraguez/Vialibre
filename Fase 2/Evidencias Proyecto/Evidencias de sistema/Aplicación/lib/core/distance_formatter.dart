// lib/core/distance_formatter.dart
// Formateo de distancias en km con separador decimal coma (es-CL)
// y cálculo de distancia acumulada sobre una polilínea.
//
// Spec: ruta-emergencia-progreso — Task 4

import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Formatea [meters] como distancia en km con notación es-CL.
///
/// - < 100 m      → '< 0,1 km'
/// - 100 – 9 999 m → '0,4 km' / '3,4 km'  (1 decimal)
/// - ≥ 10 000 m   → '12 km'               (sin decimales)
String formatDistanceKm(double meters) {
  if (meters < 100) return '< 0,1 km';

  final km = meters / 1000.0;

  if (km < 10) {
    // 1 decimal, separador coma
    final formatted = km.toStringAsFixed(1).replaceAll('.', ',');
    return '$formatted km';
  }

  // Sin decimales
  return '${km.round()} km';
}

/// Suma la distancia acumulada (Haversine) de todos los segmentos
/// consecutivos de [points]. Devuelve metros.
double routeDistanceMeters(List<LatLng> points) {
  if (points.length < 2) return 0;
  double total = 0;
  for (int i = 0; i < points.length - 1; i++) {
    total += _haversine(points[i], points[i + 1]);
  }
  return total;
}

double _haversine(LatLng a, LatLng b) {
  const R = 6371000.0;
  final dLat = _rad(b.latitude  - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final h = sinLat * sinLat +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          sinLng * sinLng;
  return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double deg) => deg * math.pi / 180;
