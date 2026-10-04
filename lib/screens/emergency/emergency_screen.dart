// lib/screens/emergency/emergency_screen.dart
// Pantalla del conductor de vehículo de emergencia.
// Permite activar/desactivar modo emergencia y ver su posición en el mapa.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../models/emergency_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../widgets/emergency_fab.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _authSvc     = AuthService();
  final _locationSvc = LocationService();
  final _firestore   = FirebaseFirestore.instance;
  final _rtdb        = FirebaseDatabase.instance;

  GoogleMapController? _mapCtrl;
  UserModel? _user;

  bool    _modoEmergenciaActivo = false;
  LatLng? _miUbicacion;
  double  _velocidadKmh         = 0;
  String? _emergenciaActivaId;
  int     _conductoresAlertados = 0;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<DocumentSnapshot>? _alertCountSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final firebaseUser = _authSvc.currentUser;
    if (firebaseUser == null) return;
    _user = await _authSvc.getUserById(firebaseUser.uid);

    final ok = await _locationSvc.requestPermissions();
    if (!ok) return;

    // Escuchar posición para mostrar en mapa (sin publicar hasta activar emergencia)
    _posSub = _locationSvc.positionStream.listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _miUbicacion   = latLng;
        _velocidadKmh  = pos.speed * 3.6;
      });
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(latLng));
    });
  }

  // ── Activar modo emergencia ───────────────────────────────────
  Future<void> _activarEmergencia() async {
    if (_user == null) return;

    final id = const Uuid().v4();
    final emergencia = EmergencyModel(
      id: id,
      vehicleId: _user!.uid,  // En el MVP, vehicleId = uid del conductor
      conductorUid: _user!.uid,
      estado: EmergencyStatus.activa,
      timestampInicio: DateTime.now(),
    );

    // Guardar en Firestore
    await _firestore
        .collection(AppConstants.colEmergencies)
        .doc(id)
        .set(emergencia.toMap());

    // Marcar en Realtime DB (índice de emergencias activas para el geofencing)
    await _rtdb
        .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}')
        .set({'emergency_id': id, 'timestamp': DateTime.now().toIso8601String()});

    // Empezar a publicar ubicación en tiempo real
    await _locationSvc.startPublishingLocation(_user!.uid);

    // Escuchar conteo de conductores alertados
    _alertCountSub = _firestore
        .collection(AppConstants.colEmergencies)
        .doc(id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      setState(() {
        _conductoresAlertados =
            snap.data()?['conductores_alertados'] as int? ?? 0;
      });
    });

    setState(() {
      _modoEmergenciaActivo = true;
      _emergenciaActivaId   = id;
      _conductoresAlertados = 0;
    });
  }

  // ── Desactivar modo emergencia ────────────────────────────────
  Future<void> _desactivarEmergencia() async {
    if (_user == null || _emergenciaActivaId == null) return;

    // Detener publicación de ubicación
    await _locationSvc.stopPublishingLocation(_user!.uid);

    // Actualizar Firestore
    await _firestore
        .collection(AppConstants.colEmergencies)
        .doc(_emergenciaActivaId)
        .update({
      'estado': EmergencyStatus.inactiva.name,
      'timestamp_fin': DateTime.now().toIso8601String(),
    });

    // Remover de Realtime DB
    await _rtdb
        .ref('${AppConstants.rtdbActiveEmergencies}/${_user!.uid}')
        .remove();

    _alertCountSub?.cancel();

    setState(() {
      _modoEmergenciaActivo = false;
      _emergenciaActivaId   = null;
    });
  }

  void _toggleEmergencia() {
    if (_modoEmergenciaActivo) {
      _showDesactivarConfirm();
    } else {
      _activarEmergencia();
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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

  Future<void> _logout() async {
    if (_modoEmergenciaActivo) await _desactivarEmergencia();
    await _authSvc.signOut();
    if (mounted) context.go(AppConstants.routeLogin);
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initialPos = _miUbicacion ??
        const LatLng(-33.0472, -71.6127);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _modoEmergenciaActivo
            ? const Color(AppColors.accentRed)
            : const Color(AppColors.primaryBlue),
        title: Text(
          _modoEmergenciaActivo ? '🚨 MODO EMERGENCIA' : AppConstants.appName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Panel de métricas (solo cuando está activo)
          if (_modoEmergenciaActivo)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildMetricsCard(),
            ),

          // Panel inferior de estado
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Velocímetro
                if (_velocidadKmh > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_velocidadKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                // FAB de emergencia
                EmergencyFab(
                  activo: _modoEmergenciaActivo,
                  onPressed: _toggleEmergencia,
                ),

                const SizedBox(height: 8),
                Text(
                  _modoEmergenciaActivo
                      ? 'Toca para finalizar la emergencia'
                      : 'Toca para activar modo emergencia',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _MetricItem(
              icono: Icons.notifications_active,
              valor: _conductoresAlertados.toString(),
              etiqueta: 'Alertados',
              color: Colors.orange,
            ),
            _MetricItem(
              icono: Icons.speed,
              valor: '${_velocidadKmh.toStringAsFixed(0)} km/h',
              etiqueta: 'Velocidad',
              color: Colors.white,
            ),
            _MetricItem(
              icono: Icons.radio_button_checked,
              valor: '${GeofencingRadioCalc.radio(_velocidadKmh).toStringAsFixed(0)} m',
              etiqueta: 'Radio alerta',
              color: Colors.greenAccent,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _alertCountSub?.cancel();
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

  const _MetricItem({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(etiqueta, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

/// Helper para calcular el radio visible en el panel de métricas,
/// usando velocidad de emergencia y velocidad particular por defecto.
class GeofencingRadioCalc {
  static double radio(double veKmh) {
    final diff = veKmh - AppConstants.defaultParticularSpeedKmh;
    if (diff <= 0) return 0;
    return 30 * (diff / 3.6);
  }
}
