// lib/screens/emergency/emergency_screen.dart
// Pantalla del conductor de vehículo de emergencia.
// Implementa el flujo de activación de emergencia con permisos, búsqueda de
// destino, cálculo de ruta y modo sin punto fijo (spec funciones.md).
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
import '../../models/emergency_model.dart';
import '../../models/user_model.dart';
import '../../models/vehicle_model.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../services/directions_routing_service.dart';
import '../../widgets/emergency_fab.dart';
import '../../widgets/emergency_dispatch_dialog.dart';
import '../../services/driver_profile_repository.dart';

// ── Enum de estados de la baliza (TASK-02) ────────────────────────
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
  final _authSvc     = AuthService();
  final _locationSvc = LocationService();
  final _permissionSvc = PermissionService();
  final _routingSvc    = DirectionsRoutingService();
  final _profileRepo   = DriverProfileRepository();
  final _firestore   = FirebaseFirestore.instance;
  final _rtdb        = FirebaseDatabase.instance;

  GoogleMapController? _mapCtrl;
  UserModel? _user;
  VehicleModel? _vehicle;

  // ── Perfil del conductor (menú AppBar, task 2.3) ──────────────
  DriverProfileInfo? _perfil;
  StreamSubscription<DriverProfileInfo>? _perfilSub;

  // ── Estado de la baliza ───────────────────────────────────────
  EmergencyState _state = EmergencyState.idle;
  String? _emergenciaActivaId;
  int _conductoresAlertados = 0;
  bool _notificationsEnabled = true;

  // ── Datos de la misión ────────────────────────────────────────
  LatLng? _destino;
  String? _destinoLabel;
  bool _hasFixedDestination = false;
  RouteResult? _routeResult;

  // ── Datos en vivo del GPS ─────────────────────────────────────
  LatLng? _miUbicacion;
  double _velocidadKmh = 0;
  double _heading = 0;

  // ── Renderizado del mapa ──────────────────────────────────────
  final Map<String, Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // ── Subscriptions ─────────────────────────────────────────────
  StreamSubscription<Position>? _posSub;
  StreamSubscription<DocumentSnapshot>? _alertCountSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revalidar permisos al volver a primer plano (REQ-02, CP-00e)
    if (state == AppLifecycleState.resumed &&
        _state == EmergencyState.transmitting) {
      _permissionSvc.revalidatePermissions().then((ok) {
        if (!ok && _user != null) {
          // Permiso revocado durante la misión
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

    // Cargar vehículo asignado al conductor
    final vehicleSnap = await _firestore
        .collection(AppConstants.colVehicles)
        .where('conductor_asignado_uid', isEqualTo: _user!.uid)
        .limit(1)
        .get();

    if (vehicleSnap.docs.isNotEmpty) {
      _vehicle = VehicleModel.fromMap(vehicleSnap.docs.first.data());
    }

    // Suscribir perfil del conductor en tiempo real (task 2.2)
    _perfilSub = _profileRepo.watchProfile(_user!.uid).listen((p) {
      if (mounted) setState(() => _perfil = p);
    });

    // Verificar estado de notificaciones
    _notificationsEnabled = await _permissionSvc.hasNotificationPermission;

    final ok = await _locationSvc.requestPermissions();
    if (!ok) return;

    // Arrancar el stream GPS compartido (un solo listener nativo)
    await _locationSvc.startStream();

    // Suscribir la UI al broadcast
    _posSub = _locationSvc.positionStream.listen(_onPositionUpdate);
  }

  // ── Callback de posición GPS (TASK-05 + TASK-06) ──────────────
  void _onPositionUpdate(Position pos) {
    final latLng = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _miUbicacion = latLng;
      _velocidadKmh = (pos.speed * 3.6).clamp(0.0, 200.0);
      _heading = pos.heading;
    });

    // Animar cámara: seguir posición + rotar según heading (TASK-06)
    if (_state == EmergencyState.transmitting && _mapCtrl != null) {
      _mapCtrl!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 18,
            bearing: _heading,
            tilt: 45,
          ),
        ),
      );
    } else if (_mapCtrl != null) {
      _mapCtrl!.animateCamera(CameraUpdate.newLatLng(latLng));
    }

    _updateVehicleMarker();

    if (_routeResult != null && _miUbicacion != null) {
      _updateRouteMarker();
    }

    // Publicar telemetría en active_emergencies/{uid}/current_location (TASK-07)
    if (_state == EmergencyState.transmitting && _user != null) {
      _rtdb
          .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}/current_location')
          .update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed_kmh': (pos.speed * 3.6).clamp(0.0, 200.0),
        'heading': pos.heading,
      });
    }
  }

  void _updateVehicleMarker() {
    if (_miUbicacion == null) return;

    final markerId = const MarkerId('vehicle');
    _markers[markerId.value] = Marker(
      markerId: markerId,
      position: _miUbicacion!,
      rotation: _heading,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Mi vehículo'),
    );
    if (mounted) setState(() {});
  }

  void _updateRouteMarker() {
    if (_miUbicacion == null || _routeResult == null) return;

    final destId = const MarkerId('destination');
    _markers[destId.value] = Marker(
      markerId: destId,
      position: _routeResult!.destination,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title: 'Destino',
        snippet: _destinoLabel ?? 'Destino de la ruta',
      ),
    );
    if (mounted) setState(() {});
  }

  // ── Flujo de activación (TASK-02: state machine) ───────────────
  void _onFabPressed() {
    if (_state == EmergencyState.transmitting) {
      _showDesactivarConfirm();
    } else if (_state == EmergencyState.idle ||
        _state == EmergencyState.permissionDenied) {
      _startActivationFlow();
    }
  }

  Future<void> _startActivationFlow() async {
    // TASK-00: Verificar y solicitar permisos
    setState(() => _state = EmergencyState.checkingPermissions);

    final permResult = await _permissionSvc.requestAllPermissions(context);

    switch (permResult) {
      case PermissionResult.locationServiceDisabled:
        _showGpsDisabledDialog();
        setState(() => _state = EmergencyState.idle);
        return;

      case PermissionResult.locationDenied:
        setState(() => _state = EmergencyState.permissionDenied);
        return;

      case PermissionResult.locationPermanentlyDenied:
        setState(() => _state = EmergencyState.permissionDenied);
        return;

      case PermissionResult.locationGrantedNotificationsDenied:
        _notificationsEnabled = false;
        // Continuar con advertencia
        break;

      case PermissionResult.granted:
        _notificationsEnabled = true;
        break;
    }

    // TASK-03: Capturar coordenadas de inicio
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

    // TASK-01: Desplegar modal de selección de destino
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
      // Modo con destino: resolver coordenadas y calcular ruta
      setState(() {
        _destino = result.destination;
        _destinoLabel = result.destinationLabel;
        _hasFixedDestination = true;
        _state = EmergencyState.calculatingRoute;
      });

      await _calculateRouteAndTransmit(origin, result.destination!);
    } else {
      // Modo sin destino fijo: transmitir directamente
      setState(() {
        _hasFixedDestination = false;
        _state = EmergencyState.transmitting;
      });

      await _startTransmission(origin);
    }
  }

  // ── Calcular ruta (TASK-05) y luego transmitir ─────────────────
  Future<void> _calculateRouteAndTransmit(
    LatLng origin,
    LatLng destination,
  ) async {
    // Asegurar que el overlay "Calculando ruta..." sea visible
    if (mounted) setState(() => _state = EmergencyState.calculatingRoute);

    try {
      debugPrint('[Ruta] Calculando desde $origin hasta $destination');
      final route = await _routingSvc.calculateRoute(
        origin: origin,
        destination: destination,
      );
      debugPrint(
        '[Ruta] OK — ${route.polylinePoints.length} pts, '
        '${route.distanceMeters} m, ${route.durationSeconds} s',
      );

      if (!mounted) return;
      setState(() {
        _routeResult = route;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('emergency_route'),
            points: route.polylinePoints,
            color: AppColors.alertCritical,
            width: 6,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
        _state = EmergencyState.transmitting;
      });

      _updateRouteMarker();

      // Zoom para mostrar toda la ruta en el mapa
      if (_mapCtrl != null && route.polylinePoints.isNotEmpty) {
        final bounds = _boundsFromPoints(route.polylinePoints);
        _mapCtrl!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );
      }

      await _startTransmission(origin);
    } catch (e, st) {
      debugPrint('[Ruta] Error: $e\n$st');

      // Fallback (TASK-05): si la API de rutas falla, continuar en modo
      // sin destino fijo sin bloquear la baliza.
      if (mounted) _showFallbackSnackBar(e.toString());

      if (mounted) {
        setState(() {
          _hasFixedDestination = false;
          _destino = null;
          _routeResult = null;
          _polylines = {};
          _state = EmergencyState.transmitting;
        });
      }

      await _startTransmission(origin);
    }
  }

  /// Calcula el LatLngBounds que encierra todos los puntos de la polyline.
  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.alertAnticipation,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ── Iniciar transmisión a Firebase (TASK-07) ──────────────────
  Future<void> _startTransmission(LatLng origin) async {
    if (_user == null) return;

    final id = const Uuid().v4();
    _emergenciaActivaId = id;

    // 1. Crear documento en Firestore
    final emergency = EmergencyModel(
      id: id,
      vehicleId: _vehicle?.id ?? _user!.uid,
      conductorUid: _user!.uid,
      estado: EmergencyStatus.activa,
      origen: RoutePoint(lat: origin.latitude, lng: origin.longitude),
      destino: _hasFixedDestination && _destino != null
          ? RoutePoint(lat: _destino!.latitude, lng: _destino!.longitude)
          : null,
      timestampInicio: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.colEmergencies)
        .doc(id)
        .set(emergency.toMap());

    // 2. Publicar payload de inicio en RTDB (TASK-07)
    await _publishEmergencyStart(origin);

    // 3. Escuchar cambios en conductores_alertados
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

    // 4. Iniciar publicación continua de telemetría en active_locations (1 Hz)
    await _locationSvc.startPublishingLocation(_user!.uid);
  }

  // ── Payload de inicio en RTDB (TASK-07) ────────────────────────
  Future<void> _publishEmergencyStart(LatLng origin) async {
    if (_user == null) return;

    final payload = <String, dynamic>{
      'vehicle_id': _vehicle?.patente ?? _user!.uid,
      'driver_uid': _user!.uid,
      'timestamp_inicio': DateTime.now().toIso8601String(),
      'has_fixed_destination': _hasFixedDestination,
      if (_hasFixedDestination && _destino != null)
        'destination': {
          'place_name': _destinoLabel ?? 'Destino',
          'lat': _destino!.latitude,
          'lng': _destino!.longitude,
        },
      'current_location': {
        'lat': origin.latitude,
        'lng': origin.longitude,
        'speed_kmh': _velocidadKmh,
        'heading': _heading,
      },
    };

    await _rtdb
        .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}')
        .set(payload);
  }

  // ── Desactivar emergencia (CP-04: Finalización y Limpieza) ────
  Future<void> _desactivarEmergencia() async {
    // Capturar datos antes de cualquier await para evitar nulls tardíos
    final uid = _user?.uid;
    final emergId = _emergenciaActivaId;

    // 1. Detener publicación RTDB de forma síncrona — NO puede colgar
    if (uid != null) {
      _locationSvc.stopPublishingLocation(uid);
    }

    // 2. Cancelar subscripción de alertados
    _alertCountSub?.cancel();
    _alertCountSub = null;

    // 3. Reset de UI inmediato — el usuario ve el cambio aunque Firebase tarde
    if (mounted) {
      setState(() {
        _state = EmergencyState.idle;
        _emergenciaActivaId = null;
        _conductoresAlertados = 0;
        _polylines = {};
        _markers.remove('destination');
        _routeResult = null;
        _destino = null;
        _destinoLabel = null;
        _hasFixedDestination = false;
      });
    }

    // 4. Actualizar Firestore en background (fire-and-forget con timeout)
    if (uid != null && emergId != null) {
      _firestore
          .collection(AppConstants.colEmergencies)
          .doc(emergId)
          .update({
        'estado': 'inactiva',
        'timestamp_fin': DateTime.now().toIso8601String(),
      }).timeout(
        const Duration(seconds: 8),
        onTimeout: () => debugPrint('[Desactivar] Firestore timeout — sin red'),
      ).catchError((e) {
        debugPrint('[Desactivar] Firestore update error: $e');
      });
    }

    // 5. Purgar nodo RTDB en background
    if (uid != null) {
      _rtdb
          .ref('${AppConstants.rtdbActiveEmergencies}/$uid')
          .remove()
          .catchError((e) {
        debugPrint('[Desactivar] RTDB remove error: $e');
      });
    }

    // 6. Confirmación visual
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Emergencia finalizada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Diálogos de permisos (TASK-02) ────────────────────────────
  void _showGpsDisabledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS apagado'),
        content: const Text(
          'Necesitas activar el GPS para usar el modo emergencia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
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
            child: const Text('Continuar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(0, 40),
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
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    // Detener publicación RTDB de forma síncrona antes de cerrar sesión
    final uid = _user?.uid;
    if (uid != null && _state == EmergencyState.transmitting) {
      _locationSvc.stopPublishingLocation(uid);
      // Purgar nodo RTDB en background
      _rtdb
          .ref('${AppConstants.rtdbActiveEmergencies}/$uid')
          .remove()
          .catchError((_) {});
      // Actualizar Firestore en background
      final emergId = _emergenciaActivaId;
      if (emergId != null) {
        _firestore
            .collection(AppConstants.colEmergencies)
            .doc(emergId)
            .update({
          'estado': 'inactiva',
          'timestamp_fin': DateTime.now().toIso8601String(),
        }).catchError((_) {});
      }
    }

    // Cancelar subscripciones
    _alertCountSub?.cancel();

    // Cerrar sesión Firebase (opera offline, no puede colgar)
    try {
      await _authSvc.signOut();
    } catch (e) {
      debugPrint('[Logout] signOut error: $e');
    }

    // Navegar a login siempre
    if (mounted) {
      context.go(AppConstants.routeLogin);
    }
  }

  // ── Helper: fila del menú de perfil (task 2.3) ────────────────
  Widget _buildProfileRow({
    required IconData icon,
    required String label,
    required String valor,
    bool sinVehiculo = false,
  }) {
    return Row(
      children: [
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
            Text(
              valor,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sinVehiculo
                    ? AppColors.textDisabled
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── UI ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final initialPos = _miUbicacion ?? const LatLng(-33.0472, -71.6127);

    final isTransmitting = _state == EmergencyState.transmitting;
    final isCalculating = _state == EmergencyState.calculatingRoute;
    final isCheckingPerms = _state == EmergencyState.checkingPermissions;
    final isPermissionDenied = _state == EmergencyState.permissionDenied;

    final appBarBg = isTransmitting
        ? AppColors.alertCritical
        : AppColors.background;
    final appBarFg = isTransmitting
        ? AppColors.onPrimary
        : AppColors.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isTransmitting ? '🚨 MODO EMERGENCIA' : AppConstants.appName,
          style: TextStyle(fontWeight: FontWeight.w800, color: appBarFg),
        ),
        actions: [
          // ── Menú del conductor (task 2.3) ──────────────────────
          PopupMenuButton<String>(
            icon: Icon(Icons.account_circle_outlined, color: appBarFg),
            tooltip: 'Datos del conductor',
            color: AppColors.surface,
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              // ── Encabezado: nombre del conductor ──────────────
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16,
                            color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Conductor',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _perfil?.nombreConductor.isNotEmpty == true
                          ? _perfil!.nombreConductor
                          : _user?.nombre ?? '—',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Divider(height: 16),
                  ],
                ),
              ),
              // ── Tipo de vehículo ───────────────────────────────
              PopupMenuItem<String>(
                enabled: false,
                child: _buildProfileRow(
                  icon: Icons.directions_car,
                  label: 'Tipo de vehículo',
                  valor: _perfil?.tieneVehiculo == true
                      ? _perfil!.tipoVehiculo ?? '—'
                      : 'Sin vehículo asignado',
                  sinVehiculo: _perfil?.tieneVehiculo == false,
                ),
              ),
              // ── Patente ────────────────────────────────────────
              PopupMenuItem<String>(
                enabled: false,
                child: _buildProfileRow(
                  icon: Icons.badge_outlined,
                  label: 'Patente',
                  valor: _perfil?.tieneVehiculo == true
                      ? _perfil!.patenteFormateada
                      : '—',
                  sinVehiculo: _perfil?.tieneVehiculo == false,
                ),
              ),
              const PopupMenuDivider(),
              // ── Cerrar sesión ──────────────────────────────────
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.error),
                    SizedBox(width: 10),
                    Text(
                      'Cerrar sesión',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            initialCameraPosition: CameraPosition(target: initialPos, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: Set<Marker>.of(_markers.values),
            polylines: _polylines,
          ),

          // ── Overlay: Verificando permisos ─────────────────────
          if (isCheckingPerms)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.accent),
                        const SizedBox(height: 16),
                        Text('Verificando permisos...', style: tt.titleMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Overlay: Calculando ruta ──────────────────────────
          if (isCalculating)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.accent),
                        const SizedBox(height: 16),
                        Text('Calculando ruta óptima...', style: tt.titleMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Estado: Permiso denegado ───────────────────────────
          if (isPermissionDenied)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off, color: AppColors.error, size: 48),
                        const SizedBox(height: 16),
                        Text('Permiso de ubicación requerido',
                            style: tt.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Sin acceso a tu ubicación no podemos activar la baliza.',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton(
                              onPressed: _startActivationFlow,
                              child: const Text('Reintentar'),
                            ),
                            ElevatedButton(
                              onPressed: () => _permissionSvc.openAppSettings(),
                              child: const Text('Abrir ajustes'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Panel de métricas — solo cuando está transmitiendo ──
          if (isTransmitting)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMetricsCard(tt),
                  // ── Indicador de modo sin destino fijo (task 1.4) ──
                  if (!_hasFixedDestination) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.info, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            AppConstants.openRouteModeIndicator,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.info,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // ── Panel inferior ─────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_velocidadKmh > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speed, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${_velocidadKmh.toStringAsFixed(0)} km/h',
                              style: tt.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (isTransmitting && _routeResult != null && _miUbicacion != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_car,
                                color: AppColors.alertCritical, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${_routeResult!.distanceRemainingFrom(_miUbicacion!).toStringAsFixed(0)} m al destino',
                              style: tt.titleMedium?.copyWith(
                                color: AppColors.alertCritical,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                EmergencyFab(
                  activo: isTransmitting,
                  onPressed: _onFabPressed,
                ),

                const SizedBox(height: 8),
                Text(_stateLabel, style: tt.bodySmall),
              ],
            ),
          ),
        ],
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

  Widget _buildMetricsCard(TextTheme tt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MetricItem(
              icono: Icons.notifications_active,
              valor: _conductoresAlertados.toString(),
              etiqueta: 'Alertados',
              color: AppColors.alertAnticipation,
              labelStyle: tt.bodySmall,
            ),
            _MetricItem(
              icono: Icons.speed,
              valor: '${_velocidadKmh.toStringAsFixed(0)} km/h',
              etiqueta: 'Velocidad',
              color: AppColors.primary,
              labelStyle: tt.bodySmall,
            ),
            _MetricItem(
              icono: _hasFixedDestination
                  ? Icons.flag
                  : Icons.navigation_outlined,
              valor: _hasFixedDestination
                  ? 'Con destino'
                  : AppConstants.openRouteModeLabel,
              etiqueta: 'Modo',
              color: _hasFixedDestination ? AppColors.accent : AppColors.info,
              labelStyle: tt.bodySmall,
            ),
          ],
        ),
      ),
    );
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

class _MetricItem extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;
  final Color color;
  final TextStyle? labelStyle;

  const _MetricItem({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          valor,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(etiqueta, style: labelStyle),
      ],
    );
  }
}
