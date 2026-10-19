// lib/screens/emergency/emergency_screen.dart
// Pantalla del conductor de vehículo de emergencia.
// Implementa el flujo de activación de emergencia con permisos, búsqueda de
// destino, cálculo de ruta y modo sin punto fijo (spec funciones.md).
//
// Task 2: polilínea que se consume (RouteProgressService)
// Task 5: diseño responsive (LayoutBuilder, SafeArea, breakpoints)
// Task 6: integración SpeedEstimator + RouteProgressService + telemetría
//
// Estados de la baliza (TASK-02):
//   idle → checking_permissions → searching_destination →
//   resolving_coordinates → calculating_route → transmitting
//   (o permission_denied con reintento / abrir ajustes)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/distance_formatter.dart';
import '../../models/emergency_model.dart';
import '../../models/user_model.dart';
import '../../models/vehicle_model.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../services/directions_routing_service.dart';
import '../../services/route_progress_service.dart';
import '../../services/speed_estimator.dart';
import '../../widgets/emergency_fab.dart';
import '../../widgets/emergency_dispatch_dialog.dart';
import '../../services/driver_profile_repository.dart';

// ── Enum de estados de la baliza ──────────────────────────────────
enum EmergencyState {
  idle,
  checkingPermissions,
  searchingDestination,
  resolvingCoordinates,
  calculatingRoute,
  transmitting,
  permissionDenied,
}

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with WidgetsBindingObserver {
  final _authSvc       = AuthService();
  final _locationSvc   = LocationService();
  final _permissionSvc = PermissionService();
  final _routingSvc    = DirectionsRoutingService();
  final _profileRepo   = DriverProfileRepository();
  final _firestore     = FirebaseFirestore.instance;
  final _rtdb          = FirebaseDatabase.instance;

  // ── Task 6: servicios de estimación ───────────────────────────
  final _speedEstimator    = SpeedEstimator();
  final _routeProgressSvc  = RouteProgressService();

  GoogleMapController? _mapCtrl;
  UserModel?    _user;
  VehicleModel? _vehicle;

  // ── Perfil del conductor ───────────────────────────────────────
  DriverProfileInfo? _perfil;
  StreamSubscription<DriverProfileInfo>? _perfilSub;

  // ── Estado de la baliza ────────────────────────────────────────
  EmergencyState _state = EmergencyState.idle;
  String? _emergenciaActivaId;
  int  _conductoresAlertados = 0;
  bool _notificationsEnabled = true;

  // ── Datos de la misión ─────────────────────────────────────────
  LatLng? _destino;
  String? _destinoLabel;
  bool    _hasFixedDestination = false;
  RouteResult? _routeResult;

  // ── Task 2: estado de progreso de ruta ────────────────────────
  int    _progressIndex    = 0;
  String? _routeStatusMsg;   // null = onRoute, "Fuera de ruta" = offRoute

  // ── Task 6: distancia restante en metros ──────────────────────
  double? _remainingMeters;

  // ── Datos en vivo del GPS ──────────────────────────────────────
  LatLng? _miUbicacion;
  double  _velocidadKmh = 0;
  double  _lastPublishedSpeedKmh = 0;
  double  _heading      = 0;

  // ── Renderizado del mapa ───────────────────────────────────────
  final Map<String, Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // ── Subscriptions ──────────────────────────────────────────────
  StreamSubscription<Position>?         _posSub;
  StreamSubscription<DocumentSnapshot>? _alertCountSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _state == EmergencyState.transmitting) {
      _permissionSvc.revalidatePermissions().then((ok) {
        if (!ok && _user != null) {
          _rtdb
              .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}/status')
              .set('location_lost');
          _showPermissionRevokedDialog();
        }
      });
    }
  }

  Future<void> _init() async {
    final firebaseUser = _authSvc.currentUser;
    if (firebaseUser == null) return;
    _user = await _authSvc.getUserById(firebaseUser.uid);

    final vehicleSnap = await _firestore
        .collection(AppConstants.colVehicles)
        .where('conductor_asignado_uid', isEqualTo: _user!.uid)
        .limit(1)
        .get();

    if (vehicleSnap.docs.isNotEmpty) {
      _vehicle = VehicleModel.fromMap(vehicleSnap.docs.first.data());
    }

    _perfilSub = _profileRepo.watchProfile(_user!.uid).listen((p) {
      if (mounted) setState(() => _perfil = p);
    });

    _notificationsEnabled = await _permissionSvc.hasNotificationPermission;

    final ok = await _locationSvc.requestPermissions();
    if (!ok) return;

    await _locationSvc.startStream();
    _posSub = _locationSvc.positionStream.listen(_onPositionUpdate);
  }

  // ── Callback GPS ───────────────────────────────────────────────
  void _onPositionUpdate(Position pos) {
    final latLng = LatLng(pos.latitude, pos.longitude);

    // ── Task 6: velocidad filtrada ────────────────────────────
    final sample = SpeedSample(
      timestamp:       pos.timestamp,
      speedMs:         pos.speed,
      speedAccuracyMs: pos.speedAccuracy,
      accuracyM:       pos.accuracy,
      lat:             pos.latitude,
      lng:             pos.longitude,
    );
    final estimatedKmh = _speedEstimator.addSample(sample);
    final speedToUse   = estimatedKmh ?? _lastPublishedSpeedKmh;

    setState(() {
      _miUbicacion  = latLng;
      _velocidadKmh = speedToUse;
      _heading      = pos.heading;
    });

    // ── Task 2: consumir polilínea ────────────────────────────
    if (_routeResult != null && _state == EmergencyState.transmitting) {
      _updateRouteProgress(latLng);
    }

    // ── Cámara ────────────────────────────────────────────────
    if (_state == EmergencyState.transmitting && _mapCtrl != null) {
      _mapCtrl!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng, zoom: 18, bearing: _heading, tilt: 45,
          ),
        ),
      );
    } else if (_mapCtrl != null) {
      _mapCtrl!.animateCamera(CameraUpdate.newLatLng(latLng));
    }

    _updateVehicleMarker();
    if (_routeResult != null && _miUbicacion != null) _updateRouteMarker();

    // ── Task 6: telemetría con velocidad filtrada ─────────────
    if (_state == EmergencyState.transmitting && _user != null) {
      // Si addSample devuelve null, publicar el último valor válido (no null)
      if (estimatedKmh != null) _lastPublishedSpeedKmh = estimatedKmh;

      _rtdb
          .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}/current_location')
          .update({
        'lat':       pos.latitude,
        'lng':       pos.longitude,
        'speed_kmh': _lastPublishedSpeedKmh.round(),
        'heading':   pos.heading,
      });
    }
  }

  // ── Task 2: actualizar progreso y polilínea ───────────────────
  void _updateRouteProgress(LatLng latLng) {
    final route = _routeResult!.polylinePoints;
    if (route.isEmpty) return;

    final result = _routeProgressSvc.advance(route, _progressIndex, latLng);

    switch (result.status) {
      case RouteStatus.arrived:
        setState(() {
          _polylines          = {};
          _routeStatusMsg     = null;
          _remainingMeters    = 0;
          _progressIndex      = result.newIndex;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Llegaste al destino'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

      case RouteStatus.offRoute:
        setState(() {
          _routeStatusMsg  = 'Fuera de ruta';
          // No actualizar polilínea ni índice
        });

      case RouteStatus.onRoute:
        final remaining = routeDistanceMeters(result.remainingPoints);
        setState(() {
          _progressIndex   = result.newIndex;
          _routeStatusMsg  = null;
          _remainingMeters = remaining;
          _polylines = {
            Polyline(
              polylineId: const PolylineId('emergency_route'),
              points:     result.remainingPoints,
              color:      AppColors.alertCritical,
              width:      6,
              jointType:  JointType.round,
              startCap:   Cap.roundCap,
              endCap:     Cap.roundCap,
            ),
          };
        });
    }
  }

  void _updateVehicleMarker() {
    if (_miUbicacion == null) return;
    final id = const MarkerId('vehicle');
    _markers[id.value] = Marker(
      markerId: id,
      position: _miUbicacion!,
      rotation: _heading,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Mi vehículo'),
    );
    if (mounted) setState(() {});
  }

  void _updateRouteMarker() {
    if (_miUbicacion == null || _routeResult == null) return;
    final id = const MarkerId('destination');
    _markers[id.value] = Marker(
      markerId: id,
      position: _routeResult!.destination,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title:   'Destino',
        snippet: _destinoLabel ?? 'Destino de la ruta',
      ),
    );
    if (mounted) setState(() {});
  }

  // ── Flujo de activación ────────────────────────────────────────
  void _onFabPressed() {
    if (_state == EmergencyState.transmitting) {
      _showDesactivarConfirm();
    } else if (_state == EmergencyState.idle ||
        _state == EmergencyState.permissionDenied) {
      _startActivationFlow();
    }
  }

  Future<void> _startActivationFlow() async {
    setState(() => _state = EmergencyState.checkingPermissions);

    final permResult = await _permissionSvc.requestAllPermissions(context);

    switch (permResult) {
      case PermissionResult.locationServiceDisabled:
        _showGpsDisabledDialog();
        setState(() => _state = EmergencyState.idle);
        return;
      case PermissionResult.locationDenied:
      case PermissionResult.locationPermanentlyDenied:
        setState(() => _state = EmergencyState.permissionDenied);
        return;
      case PermissionResult.locationGrantedNotificationsDenied:
        _notificationsEnabled = false;
      case PermissionResult.granted:
        _notificationsEnabled = true;
    }

    LatLng origin;
    try {
      final pos = await _locationSvc.captureOriginPosition();
      origin = LatLng(pos.latitude, pos.longitude);
      setState(() => _miUbicacion = origin);
    } catch (e) {
      _showErrorDialog(
        'No se pudo obtener tu posición GPS',
        'Verifica que el GPS esté activo y los permisos concedidos.\n\n$e',
      );
      setState(() => _state = EmergencyState.idle);
      return;
    }

    setState(() => _state = EmergencyState.searchingDestination);
    if (!mounted) return;

    final result = await EmergencyDispatchDialog.show(
      context,
      origin: origin,
      notificationsEnabled: _notificationsEnabled,
    );

    if (result == null) {
      setState(() => _state = EmergencyState.idle);
      return;
    }

    if (result.hasFixedDestination && result.destination != null) {
      setState(() {
        _destino             = result.destination;
        _destinoLabel        = result.destinationLabel;
        _hasFixedDestination = true;
        _state               = EmergencyState.calculatingRoute;
      });
      await _calculateRouteAndTransmit(origin, result.destination!);
    } else {
      setState(() {
        _hasFixedDestination = false;
        _state               = EmergencyState.transmitting;
      });
      await _startTransmission(origin);
    }
  }

  Future<void> _calculateRouteAndTransmit(
      LatLng origin, LatLng destination) async {
    if (mounted) setState(() => _state = EmergencyState.calculatingRoute);

    try {
      final route = await _routingSvc.calculateRoute(
        origin: origin, destination: destination,
      );

      if (!mounted) return;
      setState(() {
        _routeResult   = route;
        _progressIndex = 0;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('emergency_route'),
            points:     route.polylinePoints,
            color:      AppColors.alertCritical,
            width:      6,
            jointType:  JointType.round,
            startCap:   Cap.roundCap,
            endCap:     Cap.roundCap,
          ),
        };
        _remainingMeters = route.distanceMeters.toDouble();
        _state = EmergencyState.transmitting;
      });

      _updateRouteMarker();

      if (_mapCtrl != null && route.polylinePoints.isNotEmpty) {
        final bounds = _boundsFromPoints(route.polylinePoints);
        _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      }

      await _startTransmission(origin);
    } catch (e, st) {
      debugPrint('[Ruta] Error: $e\n$st');
      if (mounted) _showFallbackSnackBar(e.toString());
      if (mounted) {
        setState(() {
          _hasFixedDestination = false;
          _destino             = null;
          _routeResult         = null;
          _polylines           = {};
          _state               = EmergencyState.transmitting;
        });
      }
      await _startTransmission(origin);
    }
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude,  maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _showFallbackSnackBar([String? reason]) {
    final msg = reason != null && reason.isNotEmpty
        ? 'No se pudo calcular la ruta ($reason). Iniciando en ${AppConstants.openRouteModeLabel}.'
        : 'No se pudo calcular la ruta. Iniciando en ${AppConstants.openRouteModeLabel}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.alertAnticipation,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _startTransmission(LatLng origin) async {
    if (_user == null) return;

    final id = const Uuid().v4();
    _emergenciaActivaId = id;

    final emergency = EmergencyModel(
      id:            id,
      vehicleId:     _vehicle?.id ?? _user!.uid,
      conductorUid:  _user!.uid,
      estado:        EmergencyStatus.activa,
      origen:        RoutePoint(lat: origin.latitude, lng: origin.longitude),
      destino: _hasFixedDestination && _destino != null
          ? RoutePoint(lat: _destino!.latitude, lng: _destino!.longitude)
          : null,
      timestampInicio: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.colEmergencies)
        .doc(id)
        .set(emergency.toMap());

    await _publishEmergencyStart(origin);

    _alertCountSub = _firestore
        .collection(AppConstants.colEmergencies)
        .doc(id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      if (mounted) {
        setState(() {
          _conductoresAlertados =
              snap.data()?['conductores_alertados'] as int? ?? 0;
        });
      }
    });

    await _locationSvc.startPublishingLocation(_user!.uid);
  }

  Future<void> _publishEmergencyStart(LatLng origin) async {
    if (_user == null) return;
    final payload = <String, dynamic>{
      'vehicle_id':           _vehicle?.patente ?? _user!.uid,
      'driver_uid':           _user!.uid,
      'timestamp_inicio':     DateTime.now().toIso8601String(),
      'has_fixed_destination': _hasFixedDestination,
      if (_hasFixedDestination && _destino != null)
        'destination': {
          'place_name': _destinoLabel ?? 'Destino',
          'lat': _destino!.latitude,
          'lng': _destino!.longitude,
        },
      'current_location': {
        'lat':       origin.latitude,
        'lng':       origin.longitude,
        'speed_kmh': _velocidadKmh.round(),
        'heading':   _heading,
      },
    };
    await _rtdb
        .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}')
        .set(payload);
  }

  // ── Desactivar emergencia ─────────────────────────────────────
  Future<void> _desactivarEmergencia() async {
    final uid    = _user?.uid;
    final emergId = _emergenciaActivaId;

    if (uid != null) _locationSvc.stopPublishingLocation(uid);

    _alertCountSub?.cancel();
    _alertCountSub = null;

    // Task 6: resetear estimadores
    _speedEstimator.reset();
    _routeProgressSvc.reset();

    if (mounted) {
      setState(() {
        _state                = EmergencyState.idle;
        _emergenciaActivaId   = null;
        _conductoresAlertados = 0;
        _polylines            = {};
        _markers.remove('destination');
        _routeResult          = null;
        _destino              = null;
        _destinoLabel         = null;
        _hasFixedDestination  = false;
        _progressIndex        = 0;
        _routeStatusMsg       = null;
        _remainingMeters      = null;
        _lastPublishedSpeedKmh = 0;
      });
    }

    if (uid != null && emergId != null) {
      _firestore
          .collection(AppConstants.colEmergencies)
          .doc(emergId)
          .update({
        'estado':        'inactiva',
        'timestamp_fin': DateTime.now().toIso8601String(),
      }).timeout(
        const Duration(seconds: 8),
        onTimeout: () => debugPrint('[Desactivar] Firestore timeout'),
      ).catchError((e) => debugPrint('[Desactivar] Firestore error: $e'));
    }

    if (uid != null) {
      _rtdb
          .ref('${AppConstants.rtdbActiveEmergencies}/$uid')
          .remove()
          .catchError((e) => debugPrint('[Desactivar] RTDB error: $e'));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Emergencia finalizada'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ));
    }
  }

  // ── Diálogos ───────────────────────────────────────────────────
  void _showGpsDisabledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS apagado'),
        content: const Text(
            'Necesitas activar el GPS para usar el modo emergencia.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _permissionSvc.openLocationSettings();
            },
            child: const Text('Activar GPS'),
          ),
        ],
      ),
    );
  }

  void _showPermissionRevokedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubicación revocada'),
        content: const Text(
          'El permiso de ubicación fue revocado. La central ha sido '
          'notificada. Reactiva el permiso para continuar la transmisión.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _permissionSvc.openAppSettings();
            },
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
  }

  void _showDesactivarConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Finalizar emergencia?'),
        content: const Text(
          'Se dejará de transmitir tu posición y se notificará el fin del traslado.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Continuar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(48, 48),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _desactivarEmergencia();
            },
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final uid    = _user?.uid;
    final emergId = _emergenciaActivaId;
    if (uid != null && _state == EmergencyState.transmitting) {
      _locationSvc.stopPublishingLocation(uid);
      _rtdb.ref('${AppConstants.rtdbActiveEmergencies}/$uid')
          .remove().catchError((_) {});
      if (emergId != null) {
        _firestore.collection(AppConstants.colEmergencies).doc(emergId)
            .update({
          'estado':        'inactiva',
          'timestamp_fin': DateTime.now().toIso8601String(),
        }).catchError((_) {});
      }
    }
    _alertCountSub?.cancel();
    try { await _authSvc.signOut(); } catch (e) {
      debugPrint('[Logout] signOut error: $e');
    }
    if (mounted) context.go(AppConstants.routeLogin);
  }

  // ── Helpers UI ─────────────────────────────────────────────────
  Widget _buildProfileRow({
    required IconData icon,
    required String   label,
    required String   valor,
    bool sinVehiculo = false,
  }) {
    return Row(children: [
      Icon(icon, size: 16,
          color: sinVehiculo ? AppColors.textDisabled : AppColors.accent),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          Text(valor,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sinVehiculo
                    ? AppColors.textDisabled
                    : AppColors.textPrimary,
              )),
        ],
      ),
    ]);
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tt          = Theme.of(context).textTheme;
    final initialPos  = _miUbicacion ?? const LatLng(-33.0472, -71.6127);
    final isTransmitting     = _state == EmergencyState.transmitting;
    final isCalculating      = _state == EmergencyState.calculatingRoute;
    final isCheckingPerms    = _state == EmergencyState.checkingPermissions;
    final isPermissionDenied = _state == EmergencyState.permissionDenied;

    final appBarBg = isTransmitting ? AppColors.alertCritical : AppColors.background;
    final appBarFg = isTransmitting ? AppColors.onPrimary      : AppColors.primary;

    return Scaffold(
      // Task 5: teclado no tapa contenido
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor:    appBarBg,
        foregroundColor:    appBarFg,
        surfaceTintColor:   Colors.transparent,
        elevation:          0,
        title: Text(
          isTransmitting ? '🚨 MODO EMERGENCIA' : AppConstants.appName,
          style: TextStyle(fontWeight: FontWeight.w800, color: appBarFg),
        ),
        actions: [
          PopupMenuButton<String>(
            icon:    Icon(Icons.account_circle_outlined, color: appBarFg),
            tooltip: 'Datos del conductor',
            color:   AppColors.surface,
            onSelected: (value) { if (value == 'logout') _logout(); },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Icon(Icons.person, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text('Conductor',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      _perfil?.nombreConductor.isNotEmpty == true
                          ? _perfil!.nombreConductor
                          : _user?.nombre ?? '—',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const Divider(height: 16),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                enabled: false,
                child: _buildProfileRow(
                  icon:  Icons.directions_car,
                  label: 'Tipo de vehículo',
                  valor: _perfil?.tieneVehiculo == true
                      ? _perfil!.tipoVehiculo ?? '—'
                      : 'Sin vehículo asignado',
                  sinVehiculo: _perfil?.tieneVehiculo == false,
                ),
              ),
              PopupMenuItem<String>(
                enabled: false,
                child: _buildProfileRow(
                  icon:  Icons.badge_outlined,
                  label: 'Patente',
                  valor: _perfil?.tieneVehiculo == true
                      ? _perfil!.patenteFormateada
                      : '—',
                  sinVehiculo: _perfil?.tieneVehiculo == false,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18, color: AppColors.error),
                  SizedBox(width: 10),
                  Text('Cerrar sesión',
                      style: TextStyle(color: AppColors.error)),
                ]),
              ),
            ],
          ),
        ],
      ),

      // Task 5: SafeArea + LayoutBuilder para responsive
      body: SafeArea(
        bottom: false, // el FAB maneja su propio espacio
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= AppConstants.breakpointCompact;
            return isWide
                ? _buildWideLayout(tt, initialPos, isTransmitting,
                    isCalculating, isCheckingPerms, isPermissionDenied)
                : _buildCompactLayout(tt, initialPos, isTransmitting,
                    isCalculating, isCheckingPerms, isPermissionDenied);
          },
        ),
      ),
    );
  }

  // ── Layout compacto (teléfono vertical < 600 dp) ──────────────
  Widget _buildCompactLayout(
    TextTheme tt,
    LatLng initialPos,
    bool isTransmitting,
    bool isCalculating,
    bool isCheckingPerms,
    bool isPermissionDenied,
  ) {
    return Stack(children: [
      _buildMap(initialPos),
      ..._buildOverlays(tt, isCheckingPerms, isCalculating, isPermissionDenied),

      // Panel superior de métricas
      if (isTransmitting)
        Positioned(
          top: 12, left: 12, right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMetricsCard(tt),
              if (_routeStatusMsg != null) ...[
                const SizedBox(height: 6),
                _buildOffRouteBanner(tt),
              ],
              if (!_hasFixedDestination) ...[
                const SizedBox(height: 6),
                _buildOpenModeChip(tt),
              ],
            ],
          ),
        ),

      // Panel inferior
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isTransmitting) _buildSpeedBadge(tt),
                if (isTransmitting && _hasFixedDestination &&
                    _remainingMeters != null)
                  _buildDistanceBadge(tt),
                const SizedBox(height: 8),
                EmergencyFab(activo: isTransmitting, onPressed: _onFabPressed),
                const SizedBox(height: 8),
                Text(_stateLabel, style: tt.bodySmall),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  // ── Layout amplio (tablet / horizontal ≥ 600 dp) ─────────────
  Widget _buildWideLayout(
    TextTheme tt,
    LatLng initialPos,
    bool isTransmitting,
    bool isCalculating,
    bool isCheckingPerms,
    bool isPermissionDenied,
  ) {
    return Row(children: [
      // Mapa ocupa la mayor parte
      Expanded(
        flex: 3,
        child: Stack(children: [
          _buildMap(initialPos),
          ..._buildOverlays(
              tt, isCheckingPerms, isCalculating, isPermissionDenied),
          if (isTransmitting && _routeStatusMsg != null)
            Positioned(
              top: 12, left: 12, right: 12,
              child: _buildOffRouteBanner(tt),
            ),
        ]),
      ),

      // Panel lateral derecho
      SizedBox(
        width: 200,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isTransmitting) ...[
                  _buildMetricsCard(tt),
                  const SizedBox(height: 12),
                  // Velocidad grande
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(Icons.speed,
                              color: AppColors.primary, size: 28),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${_velocidadKmh.round()} km/h',
                              style: tt.headlineSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text('Velocidad', style: tt.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  if (_hasFixedDestination && _remainingMeters != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            const Icon(Icons.flag,
                                color: AppColors.alertCritical, size: 24),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatDistanceKm(_remainingMeters!),
                                style: tt.titleMedium?.copyWith(
                                  color: AppColors.alertCritical,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text('Restante', style: tt.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!_hasFixedDestination) ...[
                    const SizedBox(height: 8),
                    _buildOpenModeChip(tt),
                  ],
                ],
                const Spacer(),
                EmergencyFab(activo: isTransmitting, onPressed: _onFabPressed),
                const SizedBox(height: 8),
                Text(_stateLabel,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildMap(LatLng initialPos) {
    return GoogleMap(
      onMapCreated:           (ctrl) => _mapCtrl = ctrl,
      initialCameraPosition:  CameraPosition(target: initialPos, zoom: 15),
      myLocationEnabled:      true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled:    false,
      markers:   Set<Marker>.of(_markers.values),
      polylines: _polylines,
    );
  }

  List<Widget> _buildOverlays(
    TextTheme tt,
    bool isCheckingPerms,
    bool isCalculating,
    bool isPermissionDenied,
  ) {
    return [
      if (isCheckingPerms)
        Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text('Verificando permisos...', style: tt.titleMedium),
                ]),
              ),
            ),
          ),
        ),
      if (isCalculating)
        Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text('Calculando ruta óptima...', style: tt.titleMedium),
                ]),
              ),
            ),
          ),
        ),
      if (isPermissionDenied)
        Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_off,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text('Permiso de ubicación requerido',
                      style: tt.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Sin acceso a tu ubicación no podemos activar la baliza.',
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: _startActivationFlow,
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        child: const Text('Reintentar'),
                      ),
                      ElevatedButton(
                        onPressed: () => _permissionSvc.openAppSettings(),
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        child: const Text('Abrir ajustes'),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
    ];
  }

  // ── Widgets de panel ───────────────────────────────────────────
  Widget _buildMetricsCard(TextTheme tt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MetricItem(
              icono:      Icons.notifications_active,
              valor:      _conductoresAlertados.toString(),
              etiqueta:   'Alertados',
              color:      AppColors.alertAnticipation,
              labelStyle: tt.bodySmall,
            ),
            _MetricItem(
              icono:      Icons.speed,
              valor:      '${_velocidadKmh.round()} km/h',
              etiqueta:   'Velocidad',
              color:      AppColors.primary,
              labelStyle: tt.bodySmall,
            ),
            _MetricItem(
              icono: _hasFixedDestination
                  ? Icons.flag
                  : Icons.navigation_outlined,
              valor: _hasFixedDestination
                  ? 'Con destino'
                  : AppConstants.openRouteModeLabel,
              etiqueta:   'Modo',
              color: _hasFixedDestination ? AppColors.accent : AppColors.info,
              labelStyle: tt.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffRouteBanner(TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        AppColors.alertAnticipation.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.textPrimary, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _routeStatusMsg ?? 'Fuera de ruta',
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall
                ?.copyWith(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _buildOpenModeChip(TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:  AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.info_outline, color: AppColors.info, size: 14),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            AppConstants.openRouteModeIndicator,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(
                color: AppColors.info, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _buildSpeedBadge(TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.speed, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('${_velocidadKmh.round()} km/h',
                style: tt.titleMedium),
          ]),
        ),
      ),
    );
  }

  Widget _buildDistanceBadge(TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.directions_car,
                color: AppColors.alertCritical, size: 20),
            const SizedBox(width: 8),
            Text(
              formatDistanceKm(_remainingMeters!),
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium
                  ?.copyWith(color: AppColors.alertCritical),
            ),
          ]),
        ),
      ),
    );
  }

  String get _stateLabel {
    switch (_state) {
      case EmergencyState.idle:
        return 'Toca para activar modo emergencia';
      case EmergencyState.checkingPermissions:
        return 'Verificando permisos...';
      case EmergencyState.searchingDestination:
        return 'Selecciona destino...';
      case EmergencyState.resolvingCoordinates:
        return 'Resolviendo coordenadas...';
      case EmergencyState.calculatingRoute:
        return 'Calculando ruta...';
      case EmergencyState.transmitting:
        return 'Toca para finalizar la emergencia';
      case EmergencyState.permissionDenied:
        return 'Permiso denegado — reintentar o abrir ajustes';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _alertCountSub?.cancel();
    _perfilSub?.cancel();
    _locationSvc.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }
}

// ── Widget auxiliar ────────────────────────────────────────────────
class _MetricItem extends StatelessWidget {
  final IconData    icono;
  final String      valor;
  final String      etiqueta;
  final Color       color;
  final TextStyle?  labelStyle;

  const _MetricItem({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, color: color, size: 20),
      const SizedBox(height: 4),
      Text(valor,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      Text(etiqueta, style: labelStyle),
    ]);
  }
}
