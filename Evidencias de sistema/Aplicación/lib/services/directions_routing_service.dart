// lib/services/directions_routing_service.dart
// Servicio de enrutamiento: Google Directions API con decodificación de
// polyline y fallback a modo sin destino fijo si la API falla.
// La lógica de Places Autocomplete/Details está en PlaceSearchService.
//
// TASK-05 del spec funciones.md (REQ-05).

import 'dart:convert';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Resultado del cálculo de ruta.
class RouteResult {
  /// Lista de puntos decodificados de la polyline.
  final List<LatLng> polylinePoints;

  /// Distancia total en metros.
  final int distanceMeters;

  /// Duración total en segundos.
  final int durationSeconds;

  /// Coordenada de destino.
  final LatLng destination;

  RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.destination,
  });

  /// Distancia restante aproximada desde una posición hasta el destino.
  double distanceRemainingFrom(LatLng currentPos) {
    if (polylinePoints.isEmpty) return 0;
    final dest = polylinePoints.last;
    const double radioTierraM = 6371000;
    final dLat = _toRad(dest.latitude - currentPos.latitude);
    final dLng = _toRad(dest.longitude - currentPos.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(currentPos.latitude)) *
            math.cos(_toRad(dest.latitude)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radioTierraM * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

class DirectionsRoutingService {
  // ── Calcular ruta entre origen y destino (Directions API) ──────
  /// Llama a Google Directions API para obtener la polyline óptima.
  /// Lanza excepción si la API falla, para que el llamador pueda
  /// hacer fallback a modo sin destino fijo.
  Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final url = Uri.parse(AppConstants.googleDirectionsUrl).replace(
      queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'key': AppConstants.googleMapsApiKey,
        'language': 'es',
        'region': 'cl',
      },
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Directions API error: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = body['status'] as String?;

    if (status != 'OK') {
      throw Exception('Directions API status: $status');
    }

    final route = (body['routes'] as List).first as Map<String, dynamic>;
    final leg = (route['legs'] as List).first as Map<String, dynamic>;
    final encodedPolyline = route['overview_polyline']['points'] as String;

    final points = _decodePolyline(encodedPolyline);

    return RouteResult(
      polylinePoints: points,
      distanceMeters: leg['distance']['value'] as int,
      durationSeconds: leg['duration']['value'] as int,
      destination: destination,
    );
  }

  // ── Decodificar polyline de Google ────────────────────────────
  /// Algoritmo de decodificación estándar de Google Polyline.
  /// Convierte un string codificado a una lista de LatLng.
  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}
