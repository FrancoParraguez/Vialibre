// lib/screens/particular/home_screen.dart
// Pantalla principal del conductor particular.
// Muestra el mapa en tiempo real y el overlay de alerta hands-free cuando
// el conductor entra en el radio de un vehículo de emergencia activo.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/geofencing_service.dart';
import '../../services/notification_service.dart';
import '../../services/monitoring_controller.dart';
import '../../services/permission_status_service.dart';
import '../../services/permission_service.dart';
import '../../services/readiness_state.dart';
import '../../models/user_model.dart';
import '../../models/location_model.dart';
import '../../widgets/alert_overlay.dart';
import '../../widgets/permission_status_panel.dart';
import 'package:go_router/go_router.dart';

class HomeParticularScreen extends StatefulWidget {
  const HomeParticularScreen({super.key});

  @override
  State<HomeParticularScreen> createState() => _HomeParticularScreenState();
}

class _HomeParticularScreenState extends State<HomeParticularScreen> {
  final _authSvc     = AuthService();
  final _locationSvc = LocationService();
  final _geofenceSvc = GeofencingService();
  final _notifSvc    = NotificationService();

  // ── Nuevos: MonitoringController y PermissionStatusService ────
  late final MonitoringController _monitoringCtrl;
  late final PermissionStatusService _permissionStatusSvc;

  ReadinessState _readiness = ReadinessState.unknown;
  StreamSubscription<ReadinessState>? _readinessSub;

  // ── Mapa ──────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  UserModel? _user;

  LatLng?  _miUbicacion;
  double   _miVelocidadKmh = 0;

  // ── Estado de alerta (alimentado por MonitoringController) ────
  bool    _alertaActiva = false;
  double? _distanciaAlerta;
  double? _radioAlerta;
  AlertLevel _nivelAlerta = AlertLevel.anticipation;

  final Map<String, Marker> _markers = {};

  // Suscripción al stream de marcadores de emergencia en el mapa
  StreamSubscription<GeofenceEvent>? _geofenceSub;
  StreamSubscription<List<String>>?  _emergencyIdsSub;

  // Suscripción al stream de estados del MonitoringController
  StreamSubscription<MonitoringState>? _monitoringStateSub;

  // Suscripción al positionStream para actualizar la cámara del mapa
  StreamSubscription<Position>? _mapPosSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final firebaseUser = _authSvc.currentUser;
    if (firebaseUser == null) return;
    _user = await _authSvc.getUserById(firebaseUser.uid);

    await _notifSvc.initialize();
    await _notifSvc.saveTokenToFirestore(_user!.uid);

    // ── Inicializar PermissionStatusService y MonitoringController ──
    _permissionStatusSvc = PermissionStatusService();
    _monitoringCtrl = MonitoringController(
      _locationSvc,
      _geofenceSvc,
      _notifSvc,
      _permissionStatusSvc,
    );

    // Escuchar cambios de readiness para actualizar la UI
    _readinessSub = _permissionStatusSvc.readinessStream.listen((s) {
      if (mounted) setState(() => _readiness = s);
    });
    _permissionStatusSvc.startWatching();

    // Inicializar el controlador (evalúa permisos)
    await _monitoringCtrl.initialize();

    // Escuchar cambios de estado del monitoreo para refrescar la UI
    _monitoringStateSub = _monitoringCtrl.stateStream.listen(_onMonitoringState);

    // Suscribir al stream GPS solo para mover la cámara del mapa
    // (el MonitoringController ya maneja la lógica de geofencing)
    _mapPosSub = _locationSvc.positionStream.listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _miUbicacion    = latLng;
          _miVelocidadKmh = pos.speed * 3.6;
        });
        _mapCtrl?.animateCamera(CameraUpdate.newLatLng(latLng));
      }
    });

    // Suscribir al stream de emergencias para mostrar marcadores en el mapa
    _emergencyIdsSub = _geofenceSvc
        .watchActiveEmergencyVehicleIds()
        .listen(_onActiveEmergenciesChanged);

    // Arrancar el monitoreo si los permisos ya están listos
    if (_readiness.isReady) {
      await _monitoringCtrl.startMonitoring();
    }
  }

  // ── Reacciona a cambios de estado del MonitoringController ────
  void _onMonitoringState(MonitoringState monState) {
    if (!mounted) return;
    setState(() {
      switch (monState) {
        case MonitoringState.alertando:
          _alertaActiva    = true;
          _distanciaAlerta = _monitoringCtrl.distanciaActual;
          _radioAlerta     = _monitoringCtrl.radioActual;
          final esCritico  = _distanciaAlerta != null &&
              _radioAlerta != null &&
              _distanciaAlerta! <= _radioAlerta! * 0.3;
          _nivelAlerta = esCritico ? AlertLevel.critical : AlertLevel.anticipation;

        case MonitoringState.monitoreando:
        case MonitoringState.listo:
        case MonitoringState.sinPermisos:
          _alertaActiva    = false;
          _distanciaAlerta = null;
          _radioAlerta     = null;
          _nivelAlerta     = AlertLevel.anticipation;
      }
    });
  }

  // ── Markers de emergencia en el mapa (visual únicamente) ──────
  void _onActiveEmergenciesChanged(List<String> vehicleIds) {
    _geofenceSub?.cancel();
    if (vehicleIds.isEmpty) {
      if (mounted) {
        setState(() => _markers.removeWhere((k, _) => k.startsWith('emergency_')));
      }
      return;
    }

    final vehicleId = vehicleIds.first;
    if (_miUbicacion == null) return;

    final particularLoc = LocationModel(
      id: 'map_tmp',
      ownerId: _user?.uid ?? '',
      lat: _miUbicacion!.latitude,
      lng: _miUbicacion!.longitude,
      speedKmh: _miVelocidadKmh,
      timestamp: DateTime.now(),
    );

    _geofenceSub = _geofenceSvc
        .watchGeofence(
          emergencyVehicleId: vehicleId,
          particularLocation: particularLoc,
        )
        .listen(_onGeofenceMarker);
  }

  /// Solo actualiza el marcador del mapa — no dispara alertas (eso lo hace el controller).
  void _onGeofenceMarker(GeofenceEvent event) {
    if (!mounted) return;
    if (event.emergencyLocation != null) {
      final loc      = event.emergencyLocation!;
      final markerId = MarkerId('emergency_${loc.ownerId}');
      final marker   = Marker(
        markerId: markerId,
        position: LatLng(loc.lat, loc.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: '🚨 Emergencia activa'),
      );
      setState(() => _markers[markerId.value] = marker);
    }
  }

  // ── Solicitar permisos faltantes ──────────────────────────────
  Future<void> _requestMissingPermissions() async {
    if (!mounted) return;
    final permSvc = PermissionService();
    final result = await permSvc.requestAllPermissions(context);

    if (!mounted) return;
    switch (result) {
      case PermissionResult.granted:
        // Reinicializar el MonitoringController con los nuevos permisos
        await _monitoringCtrl.initialize();
        if (_monitoringCtrl.state == MonitoringState.listo) {
          await _monitoringCtrl.startMonitoring();
        }

      case PermissionResult.locationGrantedNotificationsDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación concedida. Activa las notificaciones para alertas hands-free.'),
          ),
        );
        await _monitoringCtrl.initialize();
        if (_monitoringCtrl.state == MonitoringState.listo) {
          await _monitoringCtrl.startMonitoring();
        }

      case PermissionResult.locationServiceDisabled:
        await Geolocator.openLocationSettings();

      case PermissionResult.locationPermanentlyDenied:
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Permiso denegado permanentemente'),
              content: const Text(
                'Ve a Configuración > Permisos y activa la ubicación para Vía Libre.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await permSvc.openAppSettings();
                  },
                  child: const Text('Abrir ajustes'),
                ),
              ],
            ),
          );
        }

      case PermissionResult.locationDenied:
        break; // usuario canceló el pre-prompt
    }
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> _logout() async {
    _monitoringCtrl.stopMonitoring();
    await _authSvc.signOut();
    if (mounted) context.go(AppConstants.routeLogin);
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final initialPos = _miUbicacion ?? const LatLng(-33.0472, -71.6127);

    final appBarBg = _alertaActiva ? _nivelAlerta.color  : AppColors.background;
    final appBarFg = _alertaActiva ? _nivelAlerta.onColor : AppColors.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _alertaActiva
              ? (_nivelAlerta == AlertLevel.critical
                  ? '🚨 EMERGENCIA INMINENTE'
                  : '⚠️ EMERGENCIA CERCANA')
              : AppConstants.appName,
          style: TextStyle(
            fontWeight: _alertaActiva ? FontWeight.w900 : FontWeight.w600,
            color: appBarFg,
          ),
        ),
        actions: [
          if (_miVelocidadKmh > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(
                    '${_miVelocidadKmh.toStringAsFixed(0)} km/h',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: appBarFg,
                    ),
                  ),
                  backgroundColor: appBarFg.withValues(alpha: 0.15),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: appBarFg,
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            initialCameraPosition: CameraPosition(target: initialPos, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            markers: Set<Marker>.of(_markers.values),
          ),

          if (_alertaActiva)
            AlertOverlay(
              activo: _alertaActiva,
              nivel: _nivelAlerta,
              distanciaMetros: _distanciaAlerta,
              radioMetros: _radioAlerta,
            ),

          // Panel de estado de permisos — siempre visible en la parte inferior
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: PermissionStatusPanel(
              readiness: _readiness,
              onRequestPermissions: _requestMissingPermissions,
            ),
          ),

          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildStatusCard(tt),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(TextTheme tt) {
    final dotColor  = _alertaActiva ? _nivelAlerta.color : AppColors.primary;
    final iconColor = _alertaActiva ? _nivelAlerta.color : AppColors.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _alertaActiva ? 'Alerta activa' : 'Sin emergencias cercanas',
                    style: tt.titleMedium,
                  ),
                  Text('Vigilancia en tiempo real activada', style: tt.bodyMedium),
                ],
              ),
            ),
            Icon(
              _alertaActiva ? _nivelAlerta.icon : Icons.check_circle_outline,
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }

  // ── dispose ───────────────────────────────────────────────────
  @override
  void dispose() {
    _readinessSub?.cancel();
    _monitoringStateSub?.cancel();
    _mapPosSub?.cancel();
    _geofenceSub?.cancel();
    _emergencyIdsSub?.cancel();
    _permissionStatusSvc.stopWatching();
    _monitoringCtrl.dispose();
    _locationSvc.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }
}
