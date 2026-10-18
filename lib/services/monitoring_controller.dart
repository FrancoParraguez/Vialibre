// lib/services/monitoring_controller.dart
// Orquesta el ciclo de vida del monitoreo de geofencing para el conductor
// particular. Centraliza la lógica que antes estaba dispersa en home_screen.
//
// El particular NUNCA escribe en Firebase (spec R7.1):
//   - No llama startPublishingLocation.
//   - No escribe en active_locations ni active_emergencies.
//
// Requisitos cubiertos: R3.1, R5.4, R5.5, R5.6, R6.5, R7.1.

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

import '../models/location_model.dart';
import 'geofencing_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'permission_status_service.dart';

// ── Estados del monitoreo ─────────────────────────────────────────
enum MonitoringState {
  sinPermisos,   // permisos faltantes → no puede monitorear
  listo,         // permisos ok, esperando startMonitoring()
  monitoreando,  // GPS activo, escuchando emergencias
  alertando,     // conductor dentro del radio de una emergencia
}

// ── MonitoringController ──────────────────────────────────────────
class MonitoringController {
  // Dependencias inyectadas
  final LocationService _locationSvc;
  final GeofencingService _geofenceSvc;
  final NotificationService _notifSvc;
  final PermissionStatusService _permissionStatusSvc;

  MonitoringController(
    this._locationSvc,
    this._geofenceSvc,
    this._notifSvc,
    this._permissionStatusSvc,
  );

  // ── Estado público ────────────────────────────────────────────
  MonitoringState _state = MonitoringState.sinPermisos;
  MonitoringState get state => _state;

  final StreamController<MonitoringState> _stateCtrl =
      StreamController<MonitoringState>.broadcast();

  /// Stream que emite cada cambio de [MonitoringState].
  Stream<MonitoringState> get stateStream => _stateCtrl.stream;

  // ── Datos de telemetría (expuestos a la UI) ───────────────────
  /// Distancia actual al vehículo de emergencia más cercano (metros).
  double? distanciaActual;

  /// Radio de alerta activo calculado por el motor de geofencing (metros).
  double? radioActual;

  // ── Estado interno ────────────────────────────────────────────
  /// Última posición GPS del conductor particular (solo en memoria, R7.1).
  LocationModel? _particularLocation;

  /// Muestras de distancia para el cálculo de tendencia (últimas 5).
  final List<double> _distanciasMuestras = [];
  static const int _maxMuestras = 5;

  /// Indica si ya se disparó una alerta para la emergencia activa.
  bool _yaAlertado = false;

  // ── Suscripciones activas ─────────────────────────────────────
  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<String>>? _emergencyIdsSub;
  StreamSubscription<GeofenceEvent>? _geofenceSub;

  // ── initialize ───────────────────────────────────────────────
  /// Evalúa el estado de permisos y establece el estado inicial.
  /// Debe llamarse una vez antes de [startMonitoring].
  Future<void> initialize() async {
    final readiness = await _permissionStatusSvc.evaluate();
    _setState(
      readiness.isReady ? MonitoringState.listo : MonitoringState.sinPermisos,
    );
    debugPrint('[MonitoringController] initialize() → $_state');
  }

  // ── startMonitoring ──────────────────────────────────────────
  /// Activa el GPS y escucha emergencias activas.
  ///
  /// Precondición: [initialize] debe haber establecido el estado [listo].
  /// Si el estado es [sinPermisos], este método retorna sin hacer nada.
  Future<void> startMonitoring() async {
    if (_state == MonitoringState.sinPermisos) {
      debugPrint('[MonitoringController] startMonitoring() ignorado: sinPermisos');
      return;
    }
    if (_state == MonitoringState.monitoreando ||
        _state == MonitoringState.alertando) {
      debugPrint('[MonitoringController] startMonitoring() ya activo');
      return;
    }

    // Arrancar stream GPS compartido (el particular NO publica, R7.1)
    await _locationSvc.startStream();

    // Suscribir al stream GPS para mantener _particularLocation en memoria
    _posSub = _locationSvc.positionStream.listen(_onPosition);

    // Suscribir a las emergencias activas en RTDB
    _emergencyIdsSub = _geofenceSvc
        .watchActiveEmergencyVehicleIds()
        .listen(_onActiveEmergenciesChanged);

    _setState(MonitoringState.monitoreando);
    debugPrint('[MonitoringController] Monitoreo iniciado');
  }

  // ── stopMonitoring ────────────────────────────────────────────
  /// Detiene el monitoreo y cancela todas las suscripciones.
  void stopMonitoring() {
    _posSub?.cancel();
    _posSub = null;
    _geofenceSub?.cancel();
    _geofenceSub = null;
    _emergencyIdsSub?.cancel();
    _emergencyIdsSub = null;

    _notifSvc.cancelarAlertas();
    _distanciasMuestras.clear();
    _yaAlertado = false;
    distanciaActual = null;
    radioActual = null;

    if (_state != MonitoringState.sinPermisos) {
      _setState(MonitoringState.listo);
    }
    debugPrint('[MonitoringController] Monitoreo detenido');
  }

  // ── dispose ───────────────────────────────────────────────────
  /// Detiene el monitoreo y libera todos los recursos.
  void dispose() {
    stopMonitoring();
    if (!_stateCtrl.isClosed) {
      _stateCtrl.close();
    }
    debugPrint('[MonitoringController] disposed');
  }

  // ── Handlers privados ─────────────────────────────────────────

  /// Actualiza la posición del particular (solo en memoria, sin RTDB).
  void _onPosition(Position pos) {
    _particularLocation = LocationModel(
      id: 'particular_tmp',
      ownerId: 'particular',
      lat: pos.latitude,
      lng: pos.longitude,
      speedKmh: pos.speed * 3.6,
      heading: pos.heading,
      accuracy: pos.accuracy,
      timestamp: DateTime.now(),
    );
  }

  /// Reacciona a cambios en la lista de emergencias activas.
  void _onActiveEmergenciesChanged(List<String> vehicleIds) {
    // Cancelar el geofence anterior
    _geofenceSub?.cancel();
    _geofenceSub = null;
    _distanciasMuestras.clear();

    if (vehicleIds.isEmpty) {
      // No hay emergencias — limpiar alertas si las había
      if (_state == MonitoringState.alertando) {
        _notifSvc.cancelarAlertas();
      }
      _yaAlertado = false;
      distanciaActual = null;
      radioActual = null;
      if (_state == MonitoringState.alertando ||
          _state == MonitoringState.monitoreando) {
        _setState(MonitoringState.monitoreando);
      }
      return;
    }

    // Monitorear la primera emergencia activa.
    // Cuando tengamos la posición, el stream se actualizará en cada tick.
    final vehicleId = vehicleIds.first;
    _suscribirGeofence(vehicleId);
  }

  /// Suscribe al stream de geofence para el vehículo dado.
  void _suscribirGeofence(String vehicleId) {
    // Si todavía no tenemos posición, usamos un stub para que el stream
    // arranque y reemplazamos en el primer tick de GPS real.
    // El guard en _onGeofenceEvent maneja `_particularLocation == null`.
    final particularLoc = _particularLocation ??
        LocationModel(
          id: 'stub',
          ownerId: 'particular',
          lat: 0,
          lng: 0,
          speedKmh: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        );

    _geofenceSub = _geofenceSvc
        .watchGeofence(
          emergencyVehicleId: vehicleId,
          particularLocation: particularLoc,
        )
        .listen(_onGeofenceEvent);
  }

  /// Procesa cada evento de geofencing.
  void _onGeofenceEvent(GeofenceEvent event) {
    // Guard: no evaluar hasta tener al menos una posición real del conductor.
    if (_particularLocation == null) return;

    // Acumular muestra de distancia (máx. _maxMuestras)
    _distanciasMuestras.add(event.distancia);
    if (_distanciasMuestras.length > _maxMuestras) {
      _distanciasMuestras.removeAt(0);
    }

    // Actualizar telemetría pública
    distanciaActual = event.distancia;
    radioActual = event.radio;

    // Evaluar tendencia e histéresis
    final result = GeofencingService.evaluarProximidad(
      distancias: List<double>.from(_distanciasMuestras),
      umbral: event.radio,
      yaAlertado: _yaAlertado,
    );

    if (result.disparar) {
      _notifSvc.mostrarAlertaEmergencia(
        titulo: '🚨 Vía Libre — Emergencia cercana',
        cuerpo:
            'Vehículo de emergencia a ${event.distancia.toStringAsFixed(0)} m. '
            'Cede el paso.',
      );
      _yaAlertado = true;
      _setState(MonitoringState.alertando);
      debugPrint(
        '[MonitoringController] ALERTA → ${event.distancia.toStringAsFixed(0)} m '
        '/ radio ${event.radio.toStringAsFixed(0)} m',
      );
      return;
    }

    if (result.limpiar) {
      _notifSvc.cancelarAlertas();
      _yaAlertado = false;
      distanciaActual = null;
      radioActual = null;
      _setState(MonitoringState.monitoreando);
      debugPrint('[MonitoringController] Alerta limpiada');
      return;
    }

    // También manejar el caso simple (sin tendencia completa) cuando
    // el evento indica explícitamente que estamos dentro del radio y
    // todavía no teníamos suficientes muestras para la tendencia.
    if (event.enRadio && !_yaAlertado) {
      _notifSvc.mostrarAlertaEmergencia(
        titulo: '🚨 Vía Libre — Emergencia cercana',
        cuerpo:
            'Vehículo de emergencia a ${event.distancia.toStringAsFixed(0)} m. '
            'Cede el paso.',
      );
      _yaAlertado = true;
      _setState(MonitoringState.alertando);
    } else if (!event.enRadio && _state == MonitoringState.alertando) {
      _notifSvc.cancelarAlertas();
      _yaAlertado = false;
      distanciaActual = null;
      radioActual = null;
      _setState(MonitoringState.monitoreando);
    }
  }

  // ── Helper: cambiar estado y emitir en stream ─────────────────
  void _setState(MonitoringState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(_state);
    }
  }
}
