// lib/screens/admin/admin_screen.dart
// Panel de administración para gestión de flota institucional.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../models/user_model.dart';
import '../../models/vehicle_model.dart';
import '../../services/auth_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _authSvc   = AuthService();
  final _firestore = FirebaseFirestore.instance;

  UserModel? _admin;
  late final TabController _tabController;

  // Streams cacheados como broadcast para permitir múltiples listeners
  Stream<List<VehicleModel>>? _vehiculosStreamCache;
  Stream<List<UserModel>>? _conductoresStreamCache;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAdmin();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmin() async {
    final fu = _authSvc.currentUser;
    if (fu == null) return;
    final user = await _authSvc.getUserById(fu.uid);
    setState(() {
      _admin = user;
      // Inicializar streams broadcast una sola vez
      if (user.institucionId != null) {
        _vehiculosStreamCache = _firestore
            .collection(AppConstants.colVehicles)
            .where('institucion_id', isEqualTo: user.institucionId)
            .snapshots()
            .map((snap) => snap.docs
                .map((d) => VehicleModel.fromMap({'id': d.id, ...d.data()}))
                .toList())
            .asBroadcastStream();

        _conductoresStreamCache = _authSvc
            .getConductoresByInstitucion(user.institucionId!)
            .asBroadcastStream();
      }
    });
  }

  // ── Streams ───────────────────────────────────────────────────
  Stream<List<VehicleModel>> get _vehiculosStream =>
      _vehiculosStreamCache ?? Stream.value([]);

  Stream<List<UserModel>> get _conductoresStream =>
      _conductoresStreamCache ?? Stream.value([]);

  // ── CRUD vehículos ────────────────────────────────────────────
  Future<void> _agregarVehiculo(VehicleModel v) async {
    await _firestore.collection(AppConstants.colVehicles).doc(v.id).set(v.toMap());
  }

  Future<void> _toggleVehiculo(VehicleModel v) async {
    await _firestore
        .collection(AppConstants.colVehicles)
        .doc(v.id)
        .update({'activo': !v.activo});
  }

  Future<void> _eliminarVehiculo(VehicleModel v) async {
    final ok = await _confirmDialog(
      title: '¿Eliminar vehículo?',
      content: 'Se eliminará permanentemente el vehículo ${v.patente}.',
    );
    if (ok) {
      await _firestore.collection(AppConstants.colVehicles).doc(v.id).delete();
    }
  }

  Future<void> _asignarConductor(VehicleModel v, String? conductorUid) async {
    await _authSvc.asignarConductor(
      vehiculoId: v.id,
      conductorUid: conductorUid,
    );
  }

  void _showAsignarDialog(VehicleModel v, List<UserModel> conductores) {
    showDialog(
      context: context,
      builder: (ctx) => _AsignarConductorDialog(
        vehiculo: v,
        conductores: conductores,
        onAsignar: (conductorUid) async {
          Navigator.pop(ctx);
          await _asignarConductor(v, conductorUid);
          if (mounted) {
            final msg = conductorUid == null
                ? 'Conductor desasignado de ${v.patente}.'
                : 'Conductor asignado a ${v.patente}.';
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
          }
        },
      ),
    );
  }

  Future<void> _toggleConductor(UserModel c) async {
    await _authSvc.setConductorActivo(c.uid, !c.activo);
  }

  Future<void> _eliminarConductor(UserModel c) async {
    final ok = await _confirmDialog(
      title: '¿Eliminar conductor?',
      content: 'Se eliminará el perfil de ${c.nombre}. '
          'La cuenta de Firebase Auth permanecerá inactiva.',
    );
    if (ok) {
      await _authSvc.deleteConductor(c.uid);
    }
  }

  // ── Diálogos ──────────────────────────────────────────────────
  Future<bool> _confirmDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showAgregarVehiculoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _VehicleFormDialog(
        institucionId: _admin?.institucionId ?? '',
        institucionNombre: _admin?.nombre ?? '',
        onSave: (v) async {
          Navigator.pop(ctx);
          await _agregarVehiculo(v);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Vehículo ${v.patente} registrado.')),
            );
          }
        },
      ),
    );
  }

  void _showAgregarConductorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _ConductorFormDialog(
        institucionId: _admin?.institucionId ?? '',
        vehiculosStream: _vehiculosStream,
        onSave: (nombre, email, password) async {
          Navigator.pop(ctx);
          try {
            if (_admin?.institucionId == null) {
              throw Exception(
                'Tu cuenta de administrador no tiene una institución asignada. '
                'Agrega el campo "institucion_id" en Firestore.',
              );
            }
            final c = await _authSvc.createConductor(
              email: email,
              password: password,
              nombre: nombre,
              institucionId: _admin!.institucionId!,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Conductor ${c.nombre} creado.')),
              );
            }
          } catch (e, stack) {
            // ignore: avoid_print
            print('ERROR createConductor: $e\n$stack');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_parseError(e.toString())),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  String _parseError(String e) {
    if (e.contains('EMAIL_EXISTS') || e.contains('email-already-in-use'))
      return 'El correo ya está registrado.';
    if (e.contains('WEAK_PASSWORD') || e.contains('weak-password'))
      return 'La contraseña es muy débil (mín. 6 caracteres).';
    if (e.contains('INVALID_EMAIL') || e.contains('invalid-email'))
      return 'Correo electrónico inválido.';
    if (e.contains('TOO_MANY_ATTEMPTS_TRY_LATER'))
      return 'Demasiados intentos. Espera unos minutos.';
    return 'Error al crear conductor. Intenta nuevamente.';
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authSvc.signOut();
              if (mounted) context.go(AppConstants.routeLogin);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.directions_car), text: 'Vehículos'),
            Tab(icon: Icon(Icons.badge_outlined), text: 'Conductores'),
          ],
        ),
      ),
      floatingActionButton: _admin == null
          ? null
          : ListenableBuilder(
              listenable: _tabController,
              builder: (_, __) => FloatingActionButton.extended(
                onPressed: _tabController.index == 0
                    ? _showAgregarVehiculoDialog
                    : _showAgregarConductorDialog,
                icon: const Icon(Icons.add),
                label: Text(
                  _tabController.index == 0
                      ? 'Agregar vehículo'
                      : 'Agregar conductor',
                ),
                backgroundColor: const Color(AppColors.primaryBlue),
              ),
            ),
      body: _admin == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Encabezado institución
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  color: const Color(AppColors.primaryBlue).withOpacity(0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.business,
                          color: Color(AppColors.primaryBlue), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _admin!.nombre,
                          style: const TextStyle(
                            color: Color(AppColors.primaryBlue),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Contenido de las pestañas
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _VehiculosTab(
                        vehiculosStream: _vehiculosStream,
                        conductoresStream: _conductoresStream,
                        onToggle: _toggleVehiculo,
                        onDelete: _eliminarVehiculo,
                        onAsignar: _showAsignarDialog,
                      ),
                      _ConductoresTab(
                        stream: _conductoresStream,
                        onToggle: _toggleConductor,
                        onDelete: _eliminarConductor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// TAB: VEHÍCULOS
// ══════════════════════════════════════════════════════════════════
class _VehiculosTab extends StatelessWidget {
  final Stream<List<VehicleModel>> vehiculosStream;
  final Stream<List<UserModel>> conductoresStream;
  final void Function(VehicleModel) onToggle;
  final void Function(VehicleModel) onDelete;
  final void Function(VehicleModel, List<UserModel>) onAsignar;

  const _VehiculosTab({
    required this.vehiculosStream,
    required this.conductoresStream,
    required this.onToggle,
    required this.onDelete,
    required this.onAsignar,
  });

  @override
  Widget build(BuildContext context) {
    // Combina ambos streams para tener vehículos y conductores disponibles
    return StreamBuilder<List<UserModel>>(
      stream: conductoresStream,
      builder: (ctx, conductoresSnap) {
        final conductores = conductoresSnap.data ?? [];

        return StreamBuilder<List<VehicleModel>>(
          stream: vehiculosStream,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }

            final vehiculos = snap.data ?? [];
            if (vehiculos.isEmpty) {
              return const _EmptyState(
                icon: Icons.local_shipping_outlined,
                mensaje: 'Sin vehículos registrados',
                sugerencia: 'Toca el botón + para agregar uno',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: vehiculos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final v = vehiculos[i];
                // Busca el nombre del conductor asignado si existe
                final conductorAsignado = conductores.where(
                  (c) => c.uid == v.conductorAsignadoUid,
                ).firstOrNull;

                return _VehicleCard(
                  vehicle: v,
                  conductorAsignado: conductorAsignado,
                  onToggle: () => onToggle(v),
                  onDelete: () => onDelete(v),
                  onAsignar: () => onAsignar(v, conductores),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// TAB: CONDUCTORES
// ══════════════════════════════════════════════════════════════════
class _ConductoresTab extends StatelessWidget {
  final Stream<List<UserModel>> stream;
  final void Function(UserModel) onToggle;
  final void Function(UserModel) onDelete;

  const _ConductoresTab({
    required this.stream,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final conductores = snap.data ?? [];
        if (conductores.isEmpty) {
          return const _EmptyState(
            icon: Icons.badge_outlined,
            mensaje: 'Sin conductores registrados',
            sugerencia: 'Toca el botón + para agregar uno',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: conductores.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _ConductorCard(
            conductor: conductores[i],
            onToggle: () => onToggle(conductores[i]),
            onDelete: () => onDelete(conductores[i]),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CARDS
// ══════════════════════════════════════════════════════════════════
class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final UserModel? conductorAsignado;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onAsignar;

  const _VehicleCard({
    required this.vehicle,
    required this.conductorAsignado,
    required this.onToggle,
    required this.onDelete,
    required this.onAsignar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila principal: icono, patente, controles
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: vehicle.activo
                      ? const Color(AppColors.successGreen).withOpacity(0.15)
                      : Colors.grey.shade200,
                  child: Icon(
                    _iconoTipo(vehicle.tipo),
                    color: vehicle.activo
                        ? const Color(AppColors.successGreen)
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicle.patente,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '${vehicle.tipoLabel} · ${vehicle.activo ? "Activo" : "Inactivo"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: vehicle.activo
                              ? const Color(AppColors.successGreen)
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: vehicle.activo,
                  onChanged: (_) => onToggle(),
                  activeThumbColor: const Color(AppColors.primaryBlue),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: onDelete,
                  tooltip: 'Eliminar',
                ),
              ],
            ),

            const Divider(height: 16),

            // Fila de conductor asignado
            Row(
              children: [
                Icon(
                  conductorAsignado != null
                      ? Icons.person
                      : Icons.person_add_alt_1_outlined,
                  size: 16,
                  color: conductorAsignado != null
                      ? const Color(AppColors.primaryBlue)
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conductorAsignado != null
                        ? conductorAsignado!.nombre
                        : 'Sin conductor asignado',
                    style: TextStyle(
                      fontSize: 13,
                      color: conductorAsignado != null
                          ? const Color(AppColors.textPrimary)
                          : Colors.grey,
                      fontStyle: conductorAsignado == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAsignar,
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text(
                    conductorAsignado != null ? 'Cambiar' : 'Asignar',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(AppColors.primaryBlue),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconoTipo(VehicleType tipo) {
    switch (tipo) {
      case VehicleType.ambulancia:  return Icons.local_hospital;
      case VehicleType.bomberos:    return Icons.local_fire_department;
      case VehicleType.carabineros: return Icons.local_police;
      case VehicleType.otro:        return Icons.emergency;
    }
  }
}

class _ConductorCard extends StatelessWidget {
  final UserModel conductor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ConductorCard({
    required this.conductor,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: conductor.activo
              ? const Color(AppColors.primaryBlue).withOpacity(0.12)
              : Colors.grey.shade200,
          child: Text(
            conductor.nombre.isNotEmpty
                ? conductor.nombre[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: conductor.activo
                  ? const Color(AppColors.primaryBlue)
                  : Colors.grey,
            ),
          ),
        ),
        title: Text(
          conductor.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conductor.email,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: conductor.activo
                    ? const Color(AppColors.successGreen).withOpacity(0.12)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                conductor.activo ? 'Activo' : 'Inactivo',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: conductor.activo
                      ? const Color(AppColors.successGreen)
                      : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: conductor.activo,
              onChanged: (_) => onToggle(),
              activeThumbColor: const Color(AppColors.primaryBlue),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onDelete,
              tooltip: 'Eliminar conductor',
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String mensaje;
  final String sugerencia;

  const _EmptyState({
    required this.icon,
    required this.mensaje,
    required this.sugerencia,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(mensaje,
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          Text(sugerencia,
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// DIALOG: AGREGAR VEHÍCULO
// ══════════════════════════════════════════════════════════════════
class _VehicleFormDialog extends StatefulWidget {
  final String institucionId;
  final String institucionNombre;
  final Future<void> Function(VehicleModel) onSave;

  const _VehicleFormDialog({
    required this.institucionId,
    required this.institucionNombre,
    required this.onSave,
  });

  @override
  State<_VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<_VehicleFormDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _patenteCtrl = TextEditingController();
  VehicleType _tipo  = VehicleType.ambulancia;
  bool _saving       = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar vehículo'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _patenteCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Patente',
                hintText: 'Ej: ABCD12',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa la patente';
                if (v.trim().length < 5) return 'Patente muy corta';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<VehicleType>(
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de vehículo',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              items: VehicleType.values.map((t) {
                const labels = {
                  VehicleType.ambulancia:  'Ambulancia',
                  VehicleType.bomberos:    'Bomberos',
                  VehicleType.carabineros: 'Carabineros',
                  VehicleType.otro:        'Otro',
                };
                return DropdownMenuItem(value: t, child: Text(labels[t]!));
              }).toList(),
              onChanged: (v) => setState(() => _tipo = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final vehicle = VehicleModel(
      id: const Uuid().v4(),
      patente: _patenteCtrl.text.trim().toUpperCase(),
      tipo: _tipo,
      institucionId: widget.institucionId,
      institucionNombre: widget.institucionNombre,
      activo: true,
      createdAt: DateTime.now(),
    );

    await widget.onSave(vehicle);
  }

  @override
  void dispose() {
    _patenteCtrl.dispose();
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════
// DIALOG: AGREGAR CONDUCTOR
// ══════════════════════════════════════════════════════════════════
class _ConductorFormDialog extends StatefulWidget {
  final String institucionId;
  final Stream<List<VehicleModel>> vehiculosStream;
  final Future<void> Function(String nombre, String email, String password) onSave;

  const _ConductorFormDialog({
    required this.institucionId,
    required this.vehiculosStream,
    required this.onSave,
  });

  @override
  State<_ConductorFormDialog> createState() => _ConductorFormDialogState();
}

class _ConductorFormDialogState extends State<_ConductorFormDialog> {
  final _formKey      = GlobalKey<FormState>();
  final _nombreCtrl   = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  bool _obscurePass   = true;
  bool _saving        = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar conductor'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresa el nombre'
                    : null,
              ),
              const SizedBox(height: 14),

              // Email
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa el correo';
                  if (!v.contains('@')) return 'Correo inválido';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Contraseña
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Contraseña temporal',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa una contraseña';
                  if (v.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),

              const SizedBox(height: 8),
              const Text(
                'El conductor usará estas credenciales para ingresar a la app.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Crear conductor'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _nombreCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}


// ══════════════════════════════════════════════════════════════════
// DIALOG: ASIGNAR CONDUCTOR A VEHÍCULO
// ══════════════════════════════════════════════════════════════════
class _AsignarConductorDialog extends StatefulWidget {
  final VehicleModel vehiculo;
  final List<UserModel> conductores;
  final Future<void> Function(String? conductorUid) onAsignar;

  const _AsignarConductorDialog({
    required this.vehiculo,
    required this.conductores,
    required this.onAsignar,
  });

  @override
  State<_AsignarConductorDialog> createState() =>
      _AsignarConductorDialogState();
}

class _AsignarConductorDialogState extends State<_AsignarConductorDialog> {
  late String? _seleccionado;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-seleccionar el conductor actualmente asignado
    _seleccionado = widget.vehiculo.conductorAsignadoUid;
  }

  @override
  Widget build(BuildContext context) {
    final conductoresActivos =
        widget.conductores.where((c) => c.activo).toList();

    return AlertDialog(
      title: Text('Asignar conductor\n${widget.vehiculo.patente}',
          style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conductoresActivos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No hay conductores activos disponibles.\n'
                'Agrega conductores en la pestaña "Conductores".',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else ...[
            // Opción: sin conductor
            RadioListTile<String?>(
              value: null,
              groupValue: _seleccionado,
              onChanged: (v) => setState(() => _seleccionado = v),
              title: const Text(
                'Sin asignar',
                style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey),
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const Divider(height: 8),

            // Lista de conductores activos
            ...conductoresActivos.map((c) => RadioListTile<String?>(
                  value: c.uid,
                  groupValue: _seleccionado,
                  onChanged: (v) => setState(() => _seleccionado = v),
                  title: Text(c.nombre,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(c.email,
                      style: const TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: (_saving || conductoresActivos.isEmpty)
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onAsignar(_seleccionado);
                },
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
