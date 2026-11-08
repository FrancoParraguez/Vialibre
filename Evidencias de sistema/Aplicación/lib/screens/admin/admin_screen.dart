// lib/screens/admin/admin_screen.dart
// Panel de administración para gestión de flota institucional.
// Colores: 100 % via AppColors tokens o Theme.of(context). Sin TextStyle(color:) en widgets.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
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

  Stream<List<VehicleModel>> get _vehiculosStream =>
      _vehiculosStreamCache ?? Stream.value([]);

  Stream<List<UserModel>> get _conductoresStream =>
      _conductoresStreamCache ?? Stream.value([]);

  // ── CRUD vehículos ────────────────────────────────────────────
  Future<void> _agregarVehiculo(VehicleModel v) async =>
      _firestore.collection(AppConstants.colVehicles).doc(v.id).set(v.toMap());

  // TASK-04: soft-delete con updated_at — sin hard delete
  Future<void> _toggleVehiculo(VehicleModel v) async =>
      _firestore.collection(AppConstants.colVehicles).doc(v.id).update({
        'activo': !v.activo,
        'updated_at': FieldValue.serverTimestamp(),
      });

  Future<void> _asignarConductor(VehicleModel v, String? uid) async =>
      _authSvc.asignarConductor(vehiculoId: v.id, conductorUid: uid);

  void _showAsignarDialog(VehicleModel v, List<UserModel> conductores) {
    showDialog(
      context: context,
      builder: (ctx) => _AsignarConductorDialog(
        vehiculo: v,
        conductores: conductores,
        onAsignar: (uid) async {
          Navigator.pop(ctx);
          await _asignarConductor(v, uid);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(uid == null
                  ? 'Conductor desasignado de ${v.patente}.'
                  : 'Conductor asignado a ${v.patente}.'),
            ));
          }
        },
      ),
    );
  }

  // TASK-04: soft-delete con updated_at — sin hard delete
  Future<void> _toggleConductor(UserModel c) async =>
      _authSvc.setConductorActivo(c.uid, !c.activo);

  // ── Diálogos ──────────────────────────────────────────────────

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
                'Tu cuenta de administrador no tiene una institución asignada.',
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
              // Error de sistema: SnackBar con contenedor errorSoft + texto error
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_parseError(e.toString()))),
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await _authSvc.signOut();
              if (mounted) context.go(AppConstants.routeLogin);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
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
                label: Text(_tabController.index == 0
                    ? 'Agregar vehículo'
                    : 'Agregar conductor'),
              ),
            ),
      body: _admin == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Encabezado institución — surfaceTint con texto del tema
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  color: cs.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(Icons.business,
                          color: cs.onSurfaceVariant, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _admin!.nombre,
                          style: tt.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _VehiculosTab(
                        vehiculosStream: _vehiculosStream,
                        conductoresStream: _conductoresStream,
                        onToggle: _toggleVehiculo,
                        onAsignar: _showAsignarDialog,
                      ),
                      _ConductoresTab(
                        stream: _conductoresStream,
                        onToggle: _toggleConductor,
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
  final void Function(VehicleModel, List<UserModel>) onAsignar;

  const _VehiculosTab({
    required this.vehiculosStream,
    required this.conductoresStream,
    required this.onToggle,
    required this.onAsignar,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: conductoresStream,
      builder: (ctx, conductoresSnap) {
        final conductores = conductoresSnap.data ?? [];
        return StreamBuilder<List<VehicleModel>>(
          stream: vehiculosStream,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snap.hasError)
              return Center(child: Text('Error: ${snap.error}'));

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
                final conductorAsignado = conductores
                    .where((c) => c.uid == v.conductorAsignadoUid)
                    .firstOrNull;
                return _VehicleCard(
                  vehicle: v,
                  conductorAsignado: conductorAsignado,
                  onToggle: () => onToggle(v),
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

  const _ConductoresTab({
    required this.stream,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snap.hasError)
          return Center(child: Text('Error: ${snap.error}'));

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
  final VoidCallback onAsignar;

  const _VehicleCard({
    required this.vehicle,
    required this.conductorAsignado,
    required this.onToggle,
    required this.onAsignar,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar: accentSoft cuando activo, surfaceTint cuando inactivo
                CircleAvatar(
                  backgroundColor: vehicle.activo
                      ? AppColors.accentSoft
                      : AppColors.surfaceTint,
                  child: Icon(
                    _iconoTipo(vehicle.tipo),
                    color: vehicle.activo
                        ? AppColors.accentDark
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TASK-01: patente
                      Text(vehicle.patente, style: tt.titleMedium),
                      const SizedBox(height: 2),
                      // TASK-01: tipo + estado en chip
                      _StatusChip(activo: vehicle.activo, label:
                          '${vehicle.tipoLabel} · ${vehicle.activo ? "Activo" : "Inactivo"}'),
                      const SizedBox(height: 2),
                      // TASK-01: institución asignada
                      Text(vehicle.institucionNombre, style: tt.bodySmall),
                    ],
                  ),
                ),
                // Switch — soft-delete únicamente (TASK-03: sin botón eliminar)
                Switch(
                  value: vehicle.activo,
                  onChanged: (_) => onToggle(),
                ),
              ],
            ),

            const Divider(height: 20),

            // TASK-01: conductor asignado
            Row(
              children: [
                Icon(
                  conductorAsignado != null
                      ? Icons.person
                      : Icons.person_add_alt_1_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conductorAsignado != null
                        ? conductorAsignado!.nombre
                        : 'Sin conductor asignado',
                    style: conductorAsignado != null
                        ? tt.bodyMedium?.copyWith(color: cs.onSurface)
                        : tt.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
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

  const _ConductorCard({
    required this.conductor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: conductor.activo
              ? AppColors.accentSoft
              : AppColors.surfaceTint,
          child: Text(
            conductor.nombre.isNotEmpty
                ? conductor.nombre[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: conductor.activo
                  ? AppColors.accentDark
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
        // TASK-02: nombre, email y badge de estado
        title: Text(conductor.nombre, style: tt.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conductor.email, style: tt.bodySmall),
            const SizedBox(height: 4),
            _StatusChip(
              activo: conductor.activo,
              label: conductor.activo ? 'Activo' : 'Inactivo',
            ),
          ],
        ),
        isThreeLine: true,
        // TASK-03: solo Switch de inhabilitación, sin botón eliminar
        trailing: Switch(
          value: conductor.activo,
          onChanged: (_) => onToggle(),
        ),
      ),
    );
  }
}

// ── Chip de estado reutilizable ───────────────────────────────────
class _StatusChip extends StatelessWidget {
  final bool activo;
  final String label;

  const _StatusChip({required this.activo, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: activo ? AppColors.accentSoft : AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: activo ? AppColors.accentDark : AppColors.textSecondary,
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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Contenedor con fondo surfaceTint para el ícono — spec §7
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(mensaje, style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(sugerencia, style: tt.bodyMedium),
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
            child: const Text('Cancelar')),
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
  final Future<void> Function(String, String, String) onSave;

  const _ConductorFormDialog({
    required this.institucionId,
    required this.vehiculosStream,
    required this.onSave,
  });

  @override
  State<_ConductorFormDialog> createState() => _ConductorFormDialogState();
}

class _ConductorFormDialogState extends State<_ConductorFormDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool _obscurePass = true;
  bool _saving      = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Registrar conductor'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Contraseña temporal',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_off
                        : Icons.visibility),
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
              // Texto informativo — usa bodySmall del tema (color textSecondary)
              Text(
                'El conductor usará estas credenciales para ingresar a la app.',
                style: tt.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
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
  final Future<void> Function(String?) onAsignar;

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
    _seleccionado = widget.vehiculo.conductorAsignadoUid;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final activos = widget.conductores.where((c) => c.activo).toList();

    return AlertDialog(
      title: Text(
        'Asignar conductor\n${widget.vehiculo.patente}',
        style: tt.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No hay conductores activos disponibles.\n'
                'Agrega conductores en la pestaña "Conductores".',
                style: tt.bodyMedium,
              ),
            )
          else ...[
            RadioListTile<String?>(
              value: null,
              groupValue: _seleccionado,
              onChanged: (v) => setState(() => _seleccionado = v),
              title: Text(
                'Sin asignar',
                style: tt.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const Divider(height: 8),
            ...activos.map((c) => RadioListTile<String?>(
                  value: c.uid,
                  groupValue: _seleccionado,
                  onChanged: (v) => setState(() => _seleccionado = v),
                  title: Text(c.nombre, style: tt.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Text(c.email, style: tt.bodySmall),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: (_saving || activos.isEmpty)
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onAsignar(_seleccionado);
                },
          child: _saving
              ? const SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
