// lib/services/permission_status_service.dart
// Monitorea en tiempo real el estado de los permisos necesarios para el
// conductor particular y emite un ReadinessState cada 3 segundos.
// Requisito R3.1 del spec alerta-proximidad-particular.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'readiness_state.dart';

class PermissionStatusService {
  // ── Stream broadcast ─────────────────────────────────────────
  final StreamController<ReadinessState> _controller =
      StreamController<ReadinessState>.broadcast();

  Stream<ReadinessState> get readinessStream => _controller.stream;

  Timer? _timer;

  // ── evaluate ─────────────────────────────────────────────────
  /// Comprueba el estado actual de todos los permisos y devuelve
  /// un [ReadinessState] actualizado.
  Future<ReadinessState> evaluate() async {
    final ItemStatus locationStatus;
    final ItemStatus backgroundStatus;
    final ItemStatus notificationsStatus;

    if (kIsWeb) {
      // En web ninguno de los tres permisos nativo está disponible.
      locationStatus = ItemStatus.unavailable;
      backgroundStatus = ItemStatus.unavailable;
      notificationsStatus = ItemStatus.unavailable;
    } else {
      // ── 1. locationRealtime ─────────────────────────────────
      final bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
      final ph.PermissionStatus whenInUse =
          await ph.Permission.locationWhenInUse.status;
      final ph.PermissionStatus always =
          await ph.Permission.locationAlways.status;

      final bool locationGranted =
          whenInUse.isGranted || always.isGranted;

      locationStatus =
          (gpsEnabled && locationGranted) ? ItemStatus.ok : ItemStatus.missing;

      // ── 2. backgroundExec ───────────────────────────────────
      if (Platform.isAndroid) {
        final ph.PermissionStatus alwaysStatus =
            await ph.Permission.locationAlways.status;
        backgroundStatus =
            alwaysStatus.isGranted ? ItemStatus.ok : ItemStatus.missing;
      } else if (Platform.isIOS) {
        // En iOS el sistema gestiona el background de forma transparente.
        backgroundStatus = ItemStatus.ok;
      } else {
        backgroundStatus = ItemStatus.unavailable;
      }

      // ── 3. notifications ────────────────────────────────────
      final ph.PermissionStatus notifStatus =
          await ph.Permission.notification.status;
      notificationsStatus =
          notifStatus.isGranted ? ItemStatus.ok : ItemStatus.missing;
    }

    return ReadinessState(
      locationRealtime: locationStatus,
      backgroundExec: backgroundStatus,
      notifications: notificationsStatus,
    );
  }

  // ── startWatching ────────────────────────────────────────────
  /// Inicia un polling de 3 segundos que emite el estado actualizado
  /// en [readinessStream].
  void startWatching() {
    // Emitir estado inmediato al arrancar.
    evaluate().then((state) {
      if (!_controller.isClosed) _controller.add(state);
    });

    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final state = await evaluate();
      if (!_controller.isClosed) {
        _controller.add(state);
      }
    });
  }

  // ── stopWatching ─────────────────────────────────────────────
  /// Cancela el polling y cierra el stream.
  void stopWatching() {
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
