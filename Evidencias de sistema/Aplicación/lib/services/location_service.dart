// lib/services/location_service.dart
// Gestiona GPS en tiempo real y publica la ubicación en Firebase Realtime DB.
//
// DISEÑO: Un único StreamController broadcast expone las posiciones GPS.
// Un solo Geolocator.getPositionStream() alimenta ese controller.
// La publicación a RTDB se activa/desactiva mediante _publishingOwnerId.
// Así no hay doble subscripción al stream nativo (causa de bloqueo en Android).

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../models/location_model.dart';

class LocationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Stream compartido (broadcast) ─────────────────────────────
  // Un único listener al GPS nativo; múltiples consumidores de la app.
  final StreamController<Position> _posCtrl =
      StreamController<Position>.broadcast();

  StreamSubscription<Position>? _gpsSubscription;

  // UID del conductor cuya ubicación se está publicando en RTDB.
  // null = no se está publicando.
  String? _publishingOwnerId;
  bool _foregroundServiceActive = false;

  // ── Arrancar el stream GPS (llamar en initState) ───────────────
  /// Inicia la escucha del GPS si no estaba activa.
  /// [enableBackground] activa WakeLock/ForegroundService únicamente
  /// durante una transmisión de emergencia activa para no drenar batería.
  Future<void> startStream({bool enableBackground = false}) async {
    if (_gpsSubscription != null &&
        _foregroundServiceActive == enableBackground) {
      return; // ya activo en el mismo modo
    }

    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _foregroundServiceActive = enableBackground;

    _gpsSubscription =
        _buildGpsStream(enableBackground: enableBackground).listen(
      (pos) {
        // Distribuir a todos los consumidores del broadcast
        if (!_posCtrl.isClosed) _posCtrl.add(pos);

        // Publicar en RTDB solo si hay una emergencia activa
        final ownerId = _publishingOwnerId;
        if (ownerId != null) {
          final location = LocationModel(
            id: const Uuid().v4(),
            ownerId: ownerId,
            lat: pos.latitude,
            lng: pos.longitude,
            speedKmh: (pos.speed * 3.6).clamp(0.0, 200.0),
            heading: pos.heading,
            accuracy: pos.accuracy,
            timestamp: DateTime.now(),
          );
          _db
              .ref('${AppConstants.rtdbActiveLocations}/$ownerId')
              .set(location.toMap());
        }
      },
      onError: (dynamic e) => debugPrint('[LocationService] GPS stream error: $e'),
    );
  }

  // ── Detener el stream GPS por completo (libera hardware y WakeLock) ──
  Future<void> stopStream() async {
    _publishingOwnerId = null;
    _foregroundServiceActive = false;
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    debugPrint('[LocationService] Stream GPS detenido por completo');
  }

  // ── Stream público (broadcast) ────────────────────────────────
  Stream<Position> get positionStream => _posCtrl.stream;

  // ── Activar publicación a RTDB ────────────────────────────────
  Future<void> startPublishingLocation(String ownerId) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permiso de ubicación denegado');

    // Asegurar que el stream GPS esté corriendo con soporte de emergencia activa
    await startStream(enableBackground: true);

    _publishingOwnerId = ownerId;
    debugPrint('[LocationService] Publicando ubicación para $ownerId');
  }

  // ── Detener publicación a RTDB y liberar WakeLock de emergencia ──
  /// Sincrónico a propósito: no hace await sobre nada que pueda colgar.
  /// El nodo de RTDB se elimina en segundo plano.
  void stopPublishingLocation(String ownerId) {
    _publishingOwnerId = null;
    debugPrint('[LocationService] Detenida publicación para $ownerId');
    if (_foregroundServiceActive) {
      // Bajar de modo foreground-service con WakeLock a GPS normal de pantalla
      startStream(enableBackground: false);
    }
    // Limpiar nodo RTDB en background (fire-and-forget)
    _db
        .ref('${AppConstants.rtdbActiveLocations}/$ownerId')
        .remove()
        .catchError((dynamic e) {
      debugPrint('[LocationService] RTDB remove error: $e');
    });
  }

  // ── Permisos ──────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  // ── Ubicación única (snapshot) ────────────────────────────────
  Future<Position> getCurrentPosition() async {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // ── Captura instantánea de coordenadas de inicio de misión ────
  Future<Position> captureOriginPosition() async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permiso de ubicación denegado');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('GPS no disponible');

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // ── Escuchar ubicación de un vehículo de emergencia ───────────
  Stream<LocationModel?> watchEmergencyLocation(String vehicleId) {
    return _db
        .ref('${AppConstants.rtdbActiveLocations}/$vehicleId')
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      return LocationModel.fromMap(Map<String, dynamic>.from(data as Map));
    });
  }

  // ── Construir stream GPS según plataforma ─────────────────────
  Stream<Position> _buildGpsStream({bool enableBackground = false}) {
    if (!kIsWeb && Platform.isAndroid) {
      return Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          intervalDuration: const Duration(
              milliseconds: AppConstants.locationUpdateIntervalMs),
          distanceFilter: 5,
          foregroundNotificationConfig: enableBackground
              ? const ForegroundNotificationConfig(
                  notificationText: 'Baliza de emergencia activa',
                  notificationTitle: 'Vía Libre',
                  enableWakeLock: true,
                  enableWifiLock: true,
                )
              : null,
        ),
      );
    } else if (!kIsWeb && Platform.isIOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          allowBackgroundLocationUpdates: enableBackground,
          showBackgroundLocationIndicator: enableBackground,
          pauseLocationUpdatesAutomatically: !enableBackground,
        ),
      );
    } else {
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );
    }
  }

  // ── Liberar recursos ──────────────────────────────────────────
  void dispose() {
    _publishingOwnerId = null;
    _foregroundServiceActive = false;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    if (!_posCtrl.isClosed) {
      _posCtrl.close();
    }
  }
}
