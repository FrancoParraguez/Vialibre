// lib/services/route_progress_service.dart
// Motor de progreso de ruta: proyección, avance monótono, fuera de ruta y llegada.
// Todas las funciones son puras/sin dependencia de UI.
//
// Spec: ruta-emergencia-progreso — Task 1

import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ── Constantes configurables ──────────────────────────────────────
const double offRouteThresholdMeters = 40.0;
const int    offRouteSamples         = 3;
const double arrivalRadiusMeters     = 30.0;

// ── Estados de ruta ───────────────────────────────────────────────
enum RouteStatus { onRoute, offRoute, arrived }

// ── Resultado de advance() ────────────────────────────────────────
class RouteProgressResult {
  final LatLng projectedPoint;
  final int newIndex;
  final double lateralDistanceMeters;
  final List<LatLng> remainingPoints;
  final RouteStatus status;

  const RouteProgressResult({
    required this.projectedPoint,
    required this.newIndex,
    required this.lateralDistanceMeters,
    required this.remainingPoints,
    required this.status,
  });
}

// ── Servicio ──────────────────────────────────────────────────────
class RouteProgressService {
  int _consecutiveOffRoute = 0;

  /// Procesa una nueva posición GPS y devuelve el estado actualizado de la ruta.
  ///
  /// [route]     : lista completa de puntos de la ruta (no vacía).
  /// [lastIndex] : último índice de segmento confirmado (monótono).
  /// [position]  : posición actual del vehículo.
  RouteProgressResult advance(
    List<LatLng> route,
    int lastIndex,
    LatLng position,
  ) {
    assert(route.isNotEmpty, 'La ruta no puede estar vacía');

    // ── Verificar llegada ─────────────────────────────────────
    final distToDest = _haversine(position, route.last);
    if (distToDest <= arrivalRadiusMeters) {
      _consecutiveOffRoute = 0;
      return RouteProgressResult(
        projectedPoint: route.last,
        newIndex: route.length - 1,
        lateralDistanceMeters: 0,
        remainingPoints: const [],
        status: RouteStatus.arrived,
      );
    }

    // ── Ruta de un solo punto ─────────────────────────────────
    if (route.length == 1) {
      _consecutiveOffRoute = 0;
      return RouteProgressResult(
        projectedPoint: route.first,
        newIndex: 0,
        lateralDistanceMeters: distToDest,
        remainingPoints: List.unmodifiable(route),
        status: RouteStatus.onRoute,
      );
    }

    // ── Proyectar sobre ventana de segmentos ──────────────────
    final int windowStart = (lastIndex - 3).clamp(0, route.length - 2);
    final int windowEnd   = (lastIndex + 30).clamp(0, route.length - 2);

    double   bestDist  = double.infinity;
    LatLng   bestPoint = route[windowStart];
    int      bestIdx   = windowStart;

    for (int i = windowStart; i <= windowEnd; i++) {
      final projected = _projectOnSegment(position, route[i], route[i + 1]);
      final d = _haversine(position, projected);
      if (d < bestDist) {
        bestDist  = d;
        bestPoint = projected;
        bestIdx   = i;
      }
    }

    // ── Monotonía: el índice solo avanza ──────────────────────
    final int newIndex = bestIdx > lastIndex ? bestIdx : lastIndex;

    // ── Fuera de ruta ─────────────────────────────────────────
    if (bestDist > offRouteThresholdMeters) {
      _consecutiveOffRoute++;
    } else {
      _consecutiveOffRoute = 0;
    }

    if (_consecutiveOffRoute >= offRouteSamples) {
      // No recortar en estado offRoute
      final remaining = _buildRemaining(route, lastIndex, route[lastIndex]);
      return RouteProgressResult(
        projectedPoint: bestPoint,
        newIndex: lastIndex, // congelar índice
        lateralDistanceMeters: bestDist,
        remainingPoints: remaining,
        status: RouteStatus.offRoute,
      );
    }

    // ── En ruta ───────────────────────────────────────────────
    final remaining = _buildRemaining(route, newIndex, bestPoint);
    return RouteProgressResult(
      projectedPoint: bestPoint,
      newIndex: newIndex,
      lateralDistanceMeters: bestDist,
      remainingPoints: remaining,
      status: RouteStatus.onRoute,
    );
  }

  /// Reinicia el contador fuera de ruta (llamar al iniciar nueva misión).
  void reset() => _consecutiveOffRoute = 0;

  // ── Helpers ───────────────────────────────────────────────────

  /// [proyectado, ...puntos desde index+1 hasta el final]
  List<LatLng> _buildRemaining(
      List<LatLng> route, int index, LatLng projected) {
    final tail = route.sublist(
      (index + 1).clamp(0, route.length),
    );
    return List.unmodifiable([projected, ...tail]);
  }

  /// Proyecta [p] sobre el segmento [a]→[b], clampeado entre a y b.
  LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    // Trabajar en lat/lng directamente (distancias pequeñas, error < 0.1 %)
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final dx = bx - ax, dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a; // segmento degenerado

    final t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    final tc = t.clamp(0.0, 1.0);
    return LatLng(ay + tc * dy, ax + tc * dx);
  }

  /// Fórmula de Haversine entre dos puntos. Devuelve metros.
  static double _haversine(LatLng a, LatLng b) {
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

  static double _rad(double deg) => deg * math.pi / 180;
}
