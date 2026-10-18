// lib/core/constants.dart
// Constantes globales del proyecto Vía Libre

class AppConstants {
  AppConstants._();

  // Nombre de la app
  static const String appName = 'Vía Libre';

  // ── Rutas de navegación ──────────────────────────────────────
  static const String routeLogin        = '/login';
  static const String routeRegister     = '/register';
  static const String routeHomeParticular = '/home';
  static const String routeEmergency    = '/emergency';
  static const String routeAdmin        = '/admin';

  // ── Roles de usuario ─────────────────────────────────────────
  static const String roleParticular  = 'particular';
  static const String roleEmergencia  = 'emergencia';
  static const String roleAdmin       = 'admin';

  // ── Colecciones de Firestore ──────────────────────────────────
  static const String colUsers        = 'users';
  static const String colVehicles     = 'vehicles';
  static const String colEmergencies  = 'emergencies';
  static const String colLocations    = 'locations';
  static const String colReports      = 'reports';

  // ── Geofencing ────────────────────────────────────────────────
  /// Anticipación mínima en segundos para disparar la alerta
  static const double alertLeadTimeSec = 30.0;

  /// Velocidad por defecto del conductor particular cuando no se puede
  /// calcular (km/h). Se usa en la fórmula d = 30*((Ve-Vc)/3.6)
  static const double defaultParticularSpeedKmh = 40.0;

  /// Velocidad por defecto del vehículo de emergencia (km/h)
  static const double defaultEmergencySpeedKmh = 80.0;

  /// Intervalo de actualización de ubicación (milisegundos)
  static const int locationUpdateIntervalMs = 1000;

  // ── Firebase Realtime DB paths ────────────────────────────────
  static const String rtdbActiveEmergencies = 'active_emergencies';
  static const String rtdbActiveLocations   = 'active_locations';

  // ── Google Maps / Directions API ──────────────────────────────
  static const String googleMapsApiKey = 'AIzaSyBQNeft9P6O4-E4A0x5O1gIoCCHxt5JjpA';
  static const String googleDirectionsUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  // Places API (New) — endpoints v1
  static const String googlePlacesAutocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const String googlePlacesDetailsBaseUrl =
      'https://places.googleapis.com/v1/places';

  // ── Misc ──────────────────────────────────────────────────────
  static const Duration splashDuration = Duration(seconds: 2);

  // ── Privacidad ────────────────────────────────────────────────
  /// Versión actual del aviso de privacidad. Incrementar cuando se actualice el texto.
  static const int privacyNoticeCurrentVersion = 1;
  static const String routePrivacyNotice = '/privacy-notice';
}

// AppColors fue migrado a lib/core/theme/app_colors.dart (sistema "Pulso").
// Importar desde allí: import 'package:vialibre/core/theme/app_colors.dart';
