// lib/services/permission_service.dart
// Gestiona permisos de ubicación (while-in-use, always/background) y
// notificaciones con pre-prompt, manejo de denied/permanentlyDenied y
// cache de estado para revalidar en AppLifecycleState.resumed.
//
// TASK-00 del spec funciones.md (REQ-02).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:geolocator/geolocator.dart';

/// Resultado de la validación de permisos.
enum PermissionResult {
  /// Todos los permisos concedidos.
  granted,
  /// Ubicación concedida, notificaciones denegadas (continuar con aviso).
  locationGrantedNotificationsDenied,
  /// Ubicación denegada — bloquear activación.
  locationDenied,
  /// Ubicación permanentemente denegada — abrir ajustes.
  locationPermanentlyDenied,
  /// GPS del dispositivo apagado.
  locationServiceDisabled,
}

class PermissionService {
  // ── Cache de estado ──────────────────────────────────────────
  bool _locationChecked = false;
  bool _notificationsChecked = false;

  bool get isLocationChecked => _locationChecked;
  bool get isNotificationsChecked => _notificationsChecked;

  // ── Verificar si el GPS está activo ──────────────────────────
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  // ── Solicitar abrir ajustes de ubicación ─────────────────────
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  // ── Abrir ajustes de la app ──────────────────────────────────
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  // ── Flujo completo de solicitud de permisos ──────────────────
  /// Ejecuta la secuencia del spec REQ-02:
  /// 1. Verificar GPS activo.
  /// 2. Solicitar locationWhenInUse.
  /// 3. Solicitar locationAlways (background).
  /// 4. Solicitar notification.
  ///
  /// [context] se usa para mostrar el pre-prompt.
  /// Retorna el resultado de la validación.
  Future<PermissionResult> requestAllPermissions(
    BuildContext context,
  ) async {
    // 1. Verificar GPS
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return PermissionResult.locationServiceDisabled;
    }

    // 2. Pre-prompt: explicar por qué necesitamos ubicación
    final shouldProceed = await _showPrePrompt(
      context,
      title: 'Ubicación en tiempo real',
      message:
          'Necesitamos tu ubicación en tiempo real para que la central '
          'siga tu unidad durante la emergencia.',
    );
    if (!shouldProceed) {
      return PermissionResult.locationDenied;
    }

    // 3. Solicitar locationWhenInUse
    var statusWhenInUse = await ph.Permission.locationWhenInUse.status;
    if (statusWhenInUse.isDenied || statusWhenInUse.isRestricted) {
      statusWhenInUse = await ph.Permission.locationWhenInUse.request();
    }

    if (statusWhenInUse.isPermanentlyDenied) {
      _locationChecked = false;
      return PermissionResult.locationPermanentlyDenied;
    }

    if (!statusWhenInUse.isGranted) {
      _locationChecked = false;
      return PermissionResult.locationDenied;
    }

    // 4. Solicitar locationAlways (background) con segunda explicación
    var statusAlways = await ph.Permission.locationAlways.status;
    if (statusAlways.isDenied || statusAlways.isRestricted) {
      final shouldContinueBg = await _showPrePrompt(
        context,
        title: 'Ubicación en segundo plano',
        message:
            'Para mantener la transmisión activa aunque minimices la app '
            'o bloquees la pantalla, necesitamos ubicación siempre.',
      );
      if (shouldContinueBg) {
        statusAlways = await ph.Permission.locationAlways.request();
      }
    }

    // Si no se concede background, no es bloqueante (whileInUse basta para activar)
    _locationChecked = true;

    // 5. Solicitar notificaciones
    var notifStatus = await ph.Permission.notification.status;
    if (notifStatus.isDenied || notifStatus.isRestricted) {
      notifStatus = await ph.Permission.notification.request();
    }

    _notificationsChecked = true;

    if (!notifStatus.isGranted) {
      return PermissionResult.locationGrantedNotificationsDenied;
    }

    return PermissionResult.granted;
  }

  // ── Revalidar permisos (para AppLifecycleState.resumed) ──────
  /// Verifica que los permisos siguen activos sin mostrar diálogos.
  /// Retorna false si la ubicación fue revocada.
  Future<bool> revalidatePermissions() async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final locationStatus = await ph.Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) return false;

    return true;
  }

  // ── Estado rápido (sin solicitar) ────────────────────────────
  Future<bool> get hasLocationPermission async {
    final status = await ph.Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  Future<bool> get hasNotificationPermission async {
    final status = await ph.Permission.notification.status;
    return status.isGranted;
  }

  // ── Pre-prompt dialog ────────────────────────────────────────
  Future<bool> _showPrePrompt(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
