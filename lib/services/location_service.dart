// lib/services/location_service.dart
// Gestiona GPS en tiempo real y publica la ubicación en Firebase Realtime DB.

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../models/location_model.dart';

class LocationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  StreamSubscription<Position>? _positionSubscription;

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

  // ── Stream continuo de ubicación ──────────────────────────────
  Stream<Position> get positionStream => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(milliseconds: AppConstants.locationUpdateIntervalMs),
      distanceFilter: 5,           // metros mínimos para emitir nuevo evento
    ),
  );

  // ── Publicar ubicación en Realtime DB ─────────────────────────
  /// [ownerId] puede ser el UID de un conductor particular o el ID de un vehículo.
  Future<void> startPublishingLocation(String ownerId) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Permiso de ubicación denegado');

    _positionSubscription = positionStream.listen((position) {
      final location = LocationModel(
        id: const Uuid().v4(),
        ownerId: ownerId,
        lat: position.latitude,
        lng: position.longitude,
        speedKmh: (position.speed * 3.6).clamp(0.0, 200.0), // m/s → km/h
        heading: position.heading,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );

      _db
          .ref('${AppConstants.rtdbActiveLocations}/$ownerId')
          .set(location.toMap());
    });
  }

  Future<void> stopPublishingLocation(String ownerId) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _db.ref('${AppConstants.rtdbActiveLocations}/$ownerId').remove();
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

  void dispose() {
    _positionSubscription?.cancel();
  }
}
