// lib/services/driver_profile_repository.dart
// Arma el perfil del conductor de emergencia (nombre, tipo de vehículo,
// patente) leyendo desde Firestore users/{uid} y vehicles/.
//
// Los datos se exponen como Stream para reflejar cambios de asignación
// en tiempo real (spec task 2.2, requisito 6).
//
// PRIVACIDAD (requisito 7): estos datos se leen solo desde Firestore.
// NUNCA se escriben en active_emergencies ni en ningún nodo de RTDB.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../models/vehicle_model.dart';

/// Datos del perfil del conductor visibles en el menú de EmergencyScreen.
class DriverProfileInfo {
  final String nombreConductor;
  final String? tipoVehiculo;   // null si sin vehículo asignado
  final String? patente;        // null si sin vehículo asignado
  final bool tieneVehiculo;

  const DriverProfileInfo({
    required this.nombreConductor,
    this.tipoVehiculo,
    this.patente,
    required this.tieneVehiculo,
  });

  /// Patente formateada en estilo chileno:
  /// - Nueva (4 letras + 2 dígitos): ABCD12 → ABCD·12
  /// - Antigua (2 letras + 2 letras + 2 dígitos): AB1234 → AB·1234  (legacy)
  /// Si el formato no coincide, devuelve la patente tal cual en mayúsculas.
  String get patenteFormateada {
    if (patente == null) return '—';
    final p = patente!.toUpperCase().replaceAll(RegExp(r'[-.\s]'), '');
    // Nueva patente: 4 letras + 2 dígitos  (ej. ABCD12)
    if (RegExp(r'^[A-Z]{4}\d{2}$').hasMatch(p)) {
      return '${p.substring(0, 4)}-${p.substring(4)}';
    }
    // Patente antigua: 2 letras + 4 dígitos (ej. AB1234)
    if (RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(p)) {
      return '${p.substring(0, 2)}-${p.substring(2)}';
    }
    return p;
  }

  static const DriverProfileInfo sinVehiculo = DriverProfileInfo(
    nombreConductor: '',
    tieneVehiculo: false,
  );
}

class DriverProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Stream en tiempo real (task 2.2, requisito 6) ─────────────
  /// Combina el perfil del usuario con el vehículo asignado.
  /// Emite un nuevo valor cada vez que cambia la asignación de vehículo.
  Stream<DriverProfileInfo> watchProfile(String uid) async* {
    // Leer nombre del conductor (campo estático — una sola vez)
    String nombreConductor = '';
    try {
      final userDoc = await _firestore
          .collection(AppConstants.colUsers)
          .doc(uid)
          .get();
      nombreConductor = userDoc.data()?['nombre'] as String? ?? '';
    } catch (_) {}

    // Stream del vehículo asignado: reemite cuando cambia la asignación
    yield* _firestore
        .collection(AppConstants.colVehicles)
        .where('conductor_asignado_uid', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) {
        return DriverProfileInfo(
          nombreConductor: nombreConductor,
          tieneVehiculo: false,
        );
      }
      final vehicle = VehicleModel.fromMap(snap.docs.first.data());
      return DriverProfileInfo(
        nombreConductor: nombreConductor,
        tipoVehiculo: vehicle.tipoLabel,
        patente: vehicle.patente,
        tieneVehiculo: true,
      );
    });
  }

  // ── Lectura única (para carga inicial sin stream) ─────────────
  Future<DriverProfileInfo> getProfile(String uid) async {
    final results = await Future.wait([
      _firestore.collection(AppConstants.colUsers).doc(uid).get(),
      _firestore
          .collection(AppConstants.colVehicles)
          .where('conductor_asignado_uid', isEqualTo: uid)
          .limit(1)
          .get(),
    ]);

    final userDoc     = results[0] as DocumentSnapshot;
    final vehicleSnap = results[1] as QuerySnapshot;

    final nombre = (userDoc.data() as Map<String, dynamic>?)?['nombre']
            as String? ??
        '';

    if (vehicleSnap.docs.isEmpty) {
      return DriverProfileInfo(
        nombreConductor: nombre,
        tieneVehiculo: false,
      );
    }

    final vehicle =
        VehicleModel.fromMap(vehicleSnap.docs.first.data() as Map<String, dynamic>);

    return DriverProfileInfo(
      nombreConductor: nombre,
      tipoVehiculo: vehicle.tipoLabel,
      patente: vehicle.patente,
      tieneVehiculo: true,
    );
  }
}
