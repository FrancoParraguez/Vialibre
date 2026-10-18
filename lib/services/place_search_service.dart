// lib/services/place_search_service.dart
// Servicio de búsqueda de lugares: Google Places API (New) v1.
// Autocomplete (POST), Place Details (GET con FieldMask) y
// geocodificación inversa para tap en mapa.
// Separado de DirectionsRoutingService (TASK-04 del spec funciones.md).

import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import '../core/constants.dart';

/// Sugerencia de autocompletado de Places API.
class PlaceSuggestion {
  final String placeId;
  final String description;

  PlaceSuggestion({required this.placeId, required this.description});
}

/// Resultado de la resolución de un lugar a coordenadas.
class PlaceResult {
  final LatLng coordinates;
  final String name;

  PlaceResult({required this.coordinates, required this.name});
}

class PlaceSearchService {
  // ── Autocompletado (Places API New — POST) ───────────────────
  /// Usa el endpoint v1: POST https://places.googleapis.com/v1/places:autocomplete
  /// Headers: X-Goog-Api-Key, X-Goog-FieldMask
  /// Body: { "input": "...", "includedRegionCodes": ["cl"], "languageCode": "es" }
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    String? language,
  }) async {
    if (query.trim().isEmpty) return [];

    final url = Uri.parse(AppConstants.googlePlacesAutocompleteUrl);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': AppConstants.googleMapsApiKey,
        'X-Goog-FieldMask': 'suggestions.placePrediction.placeId,suggestions.placePrediction.text',
      },
      body: jsonEncode({
        'input': query,
        'includedRegionCodes': ['cl'],
        'languageCode': language ?? 'es',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Places API HTTP ${response.statusCode}: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    // La API New puede devolver 'error' en vez de 'suggestions'
    if (body.containsKey('error')) {
      final error = body['error'] as Map<String, dynamic>;
      final message = error['message'] as String? ?? 'UNKNOWN';
      throw Exception('Places API: $message');
    }

    final suggestions = body['suggestions'] as List? ?? [];

    return suggestions
        .where((s) => (s as Map<String, dynamic>).containsKey('placePrediction'))
        .map((s) {
          final pred = s['placePrediction'] as Map<String, dynamic>;
          final placeId = pred['placeId'] as String;
          // text es un objeto { text: "..." }
          final textObj = pred['text'] as Map<String, dynamic>?;
          final description = textObj?['text'] as String? ?? placeId;
          return PlaceSuggestion(placeId: placeId, description: description);
        })
        .toList();
  }

  // ── Place Details (Places API New — GET con FieldMask) ────────
  /// Usa el endpoint v1: GET https://places.googleapis.com/v1/places/{placeId}
  /// Headers: X-Goog-Api-Key, X-Goog-FieldMask: displayName,location
  Future<PlaceResult> getPlaceDetails(String placeId) async {
    final url = Uri.parse('${AppConstants.googlePlacesDetailsBaseUrl}/$placeId');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': AppConstants.googleMapsApiKey,
        'X-Goog-FieldMask': 'displayName,location',
        'Accept-Language': 'es',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Place Details API HTTP ${response.statusCode}: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body.containsKey('error')) {
      final error = body['error'] as Map<String, dynamic>;
      final message = error['message'] as String? ?? 'UNKNOWN';
      throw Exception('Place Details API: $message');
    }

    // location es { latitude: ..., longitude: ... }
    final location = body['location'] as Map<String, dynamic>;
    // displayName es { text: "...", languageCode: "..." }
    final displayName = body['displayName'] as Map<String, dynamic>?;
    final name = displayName?['text'] as String? ?? '';

    return PlaceResult(
      coordinates: LatLng(
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      ),
      name: name,
    );
  }

  // ── Geocodificación inversa: LatLng → nombre legible ─────────
  /// Usa el paquete geocoding para obtener el nombre aproximado
  /// de la calle/zona a partir de coordenadas (para tap en mapa).
  Future<String> reverseGeocode(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return 'Destino en mapa';

      final pm = placemarks.first;
      final parts = <String>[
        if (pm.street?.isNotEmpty == true) pm.street!,
        if (pm.locality?.isNotEmpty == true) pm.locality!,
      ];
      return parts.isNotEmpty ? parts.join(', ') : 'Destino en mapa';
    } catch (_) {
      return 'Destino en mapa';
    }
  }
}
