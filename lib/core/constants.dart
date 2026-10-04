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

  // ── Misc ──────────────────────────────────────────────────────
  static const Duration splashDuration = Duration(seconds: 2);
}

class AppColors {
  AppColors._();

  // Paleta principal
  static const int _primaryValue = 0xFF1565C0;   // Azul institucional

  // Brand
  static const int primaryBlue   = 0xFF1565C0;
  static const int accentRed     = 0xFFD32F2F;   // Modo emergencia activo
  static const int alertOrange   = 0xFFE65100;   // Alerta activa
  static const int successGreen  = 0xFF2E7D32;
  static const int backgroundDark = 0xFF0D1B2A;  // Fondo modo oscuro / mapa
  static const int surfaceLight  = 0xFFF5F7FA;
  static const int textPrimary   = 0xFF1A1A2E;
  static const int textSecondary = 0xFF5C6BC0;
}
