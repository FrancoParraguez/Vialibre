// lib/screens/particular/home_screen.dart
// Pantalla principal del conductor particular.
// Muestra el mapa en tiempo real y el overlay de alerta hands-free cuando
// el conductor entra en el radio de un vehículo de emergencia activo.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/geofencing_service.dart';
import '../../services/notification_service.dart';
import '../../models/user_model.dart';
import '../../models/location_model.dart';
import '../../widgets/alert_overlay.dart';
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

  GoogleMapController? _mapCtrl;
  UserModel? _user;

  // Estado de ubicación propia
  LatLng? _miUbicacion;
  double  _miVelocidadKmh = 0;

  // Estado de alerta
  bool   _alertaActiva = false;
  double? _distanciaAlerta;
  double? _radioAlerta;

  // Marcadores activos en el mapa
  final Map<String, Marker> _markers = {};

  StreamSubscription<GeofenceEvent>? _geofenceSub;
  StreamSubscription<List<String>>?  _emergencyIdsSub;
  StreamSubscription<Position>?      _posSub;

  // ── Ciclo de vida ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Cargar usuario actual
    final firebaseUser = _authSvc.currentUser;
    if (firebaseUser == null) return;
    _user = await _authSvc.getUserById(firebaseUser.uid);

    // Inicializar notificaciones
    await _notifSvc.initialize();
    await _notifSvc.saveTokenToFirestore(_user!.uid);

    // Solicitar permisos y empezar a publicar ubicación
    final ok = await _locationSvc.requestPermissions();
    if (!ok) {
      _showPermissionDialog();
      return;
    }

    await _locationSvc.startPublishingLocation(_user!.uid);

    // Escuchar posición propia para actualizar mapa
    _posSub = _locationSvc.positionStream.listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _miUbicacion     = latLng;
        _miVelocidadKmh  = pos.speed * 3.6;
      });
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(latLng));
    });

    // Escuchar emergencias activas y suscribirse al geofence de cada una
    _emergencyIdsSub = _geofenceSvc
        .watchActiveEmergencyVehicleIds()
        .listen(_onActiveEmergenciesChanged);
  }

  void _onActiveEmergenciesChanged(List<String> vehicleIds) {
    _geofenceSub?.cancel();
    if (vehicleIds.isEmpty) {
      setState(() {
        _alertaActiva = false;
        _markers.removeWhere((key, _) => key.startsWith('emergency_'));
      });
      _notifSvc.cancelarAlertas();
      return;
    }

    // Por simplicidad del MVP monitoreamos la primera emergencia activa.
    // En producción se haría merge de múltiples streams.
    final vehicleId = vehicleIds.first;

    if (_miUbicacion == null) return;

    final particularLoc = LocationModel(
      id: 'tmp',
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
        .listen(_onGeofenceEvent);
  }

  void _onGeofenceEvent(GeofenceEvent event) {
    // Actualizar marcador del vehículo de emergencia
    if (event.emergencyLocation != null) {
      final loc = event.emergencyLocation!;
      final markerId = MarkerId('emergency_${loc.ownerId}');
      final marker = Marker(
        markerId: markerId,
        position: LatLng(loc.lat, loc.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: '🚨 Emergencia activa'),
      );
      setState(() => _markers[markerId.value] = marker);
    }

    // Disparar o limpiar alerta
    if (event.enRadio && !_alertaActiva) {
      _notifSvc.mostrarAlertaEmergencia(
        titulo: '🚨 Vía Libre — Emergencia cercana',
        cuerpo: 'Vehículo de emergencia a ${event.distancia.toStringAsFixed(0)} m. Cede el paso.',
      );
    } else if (!event.enRadio && _alertaActiva) {
      _notifSvc.cancelarAlertas();
    }

    setState(() {
      _alertaActiva     = event.enRadio;
      _distanciaAlerta  = event.distancia;
      _radioAlerta      = event.radio;
    });
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> _logout() async {
    if (_user != null) {
      await _locationSvc.stopPublishingLocation(_user!.uid);
    }
    await _authSvc.signOut();
    if (mounted) context.go(AppConstants.routeLogin);
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initialPos = _miUbicacion ??
        const LatLng(-33.0472, -71.6127); // Valparaíso por defecto

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _alertaActiva ? '🚨 EMERGENCIA CERCANA' : AppConstants.appName,
          style: TextStyle(
            color: _alertaActiva ? Colors.white : null,
            fontWeight: _alertaActiva ? FontWeight.w800 : null,
          ),
        ),
        backgroundColor: _alertaActiva
            ? const Color(AppColors.accentRed)
            : const Color(AppColors.primaryBlue),
        actions: [
          if (_miVelocidadKmh > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text('${_miVelocidadKmh.toStringAsFixed(0)} km/h',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: Colors.white24,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mapa
          GoogleMap(
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            initialCameraPosition: CameraPosition(
              target: initialPos,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            markers: Set<Marker>.of(_markers.values),
          ),

          // Overlay de alerta hands-free
          if (_alertaActiva)
            AlertOverlay(
              activo: _alertaActiva,
              distanciaMetros: _distanciaAlerta,
              radioMetros: _radioAlerta,
            ),

          // Panel inferior de estado
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildStatusCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _alertaActiva
                    ? const Color(AppColors.accentRed)
                    : const Color(AppColors.successGreen),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _alertaActiva ? 'Alerta activa' : 'Sin emergencias cercanas',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    'Vigilancia en tiempo real activada',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              _alertaActiva ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: _alertaActiva
                  ? const Color(AppColors.accentRed)
                  : const Color(AppColors.successGreen),
            ),
          ],
        ),
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso requerido'),
        content: const Text(
          'Vía Libre necesita acceso a tu ubicación para alertarte cuando haya un vehículo de emergencia cerca.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Abrir configuración'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _geofenceSub?.cancel();
    _emergencyIdsSub?.cancel();
    _locationSvc.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }
}
