// lib/screens/admin/admin_screen.dart
// Panel de administración web — layout corporativo con AdminShell.
// Gestión de flota y conductores de la institución del administrador.
// Spec: web-admin-corporativo

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/admin_design.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../models/vehicle_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin_shell.dart';
import '../../widgets/admin_components.dart';

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
  Stream<List<UserModel>>?    _conductoresStreamCache;

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

  // ── CRUD ──────────────────────────────────────────────────────
  Future<void> _agregarVehiculo(VehicleModel v) async =>
      _firestore.collection(AppConstants.colVehicles).doc(v.id).set(v.toMap());

  Future<void> _toggleVehiculo(VehicleModel v) async =>
      _firestore.collection(AppConstants.colVehicles).doc(v.id).update({
        'activo': !v.activo,
        'updated_at': FieldValue.serverTimestamp(),
      });

  Future<void> _asignarConductor(VehicleModel v, String? uid) async =>
      _authSvc.asignarConductor(vehiculoId: v.id, conductorUid: uid);

  Future<void> _toggleConductor(UserModel c) async =>
      _authSvc.setConductorActivo(c.uid, !c.activo);

  // ── Diálogos ──────────────────────────────────────────────────
  void _showAgregarVehiculoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _VehicleFormDialog(
        institucionId:     _admin?.institucionId ?? '',
        institucionNombre: _admin?.nombre ?? '',
        onSave: (v) async {
          Navigator.pop(ctx);
          await _agregarVehiculo(v);
          if (mounted) showSuccessSnackBar(context, 'Vehículo ${v.patente} registrado.');
        },
      ),
    );
  }

  void _showAgregarConductorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _ConductorFormDialog(
        institucionId:  _admin?.institucionId ?? '',
        vehiculosStream: _vehiculosStream,
        onSave: (nombre, email, password) async {
          Navigator.pop(ctx);
          try {
            if (_admin?.institucionId == null) {
              throw Exception(
                  'Tu cuenta de administrador no tiene una institución asignada.');
            }
            final c = await _authSvc.createConductor(
              email:        email,
              password:     password,
              nombre:       nombre,
              institucionId: _admin!.institucionId!,
            );
            if (mounted) showSuccessSnackBar(context, 'Conductor ${c.nombre} creado.');
          } catch (e) {
            if (mounted) showErrorSnackBar(context, _parseError(e.toString()));
          }
        },
      ),
    );
  }

  void _showAsignarDialog(VehicleModel v, List<UserModel> conductores) {
    showDialog(
      context: context,
      builder: (ctx) => _AsignarConductorDialog(
        vehiculo:    v,
        conductores: conductores,
        onAsignar: (uid) async {
          Navigator.pop(ctx);
          await _asignarConductor(v, uid);
          if (mounted) {
            showSuccessSnackBar(context, uid == null
                ? 'Conductor desasignado de ${v.patente}.'
                : 'Conductor asignado a ${v.patente}.');
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
    return 'Error al crear conductor. Intenta nuevamente.';
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AdminShell(
      activeRoute: AppConstants.routeAdmin,
      body: _admin == null
          ? const Center(child: CircularProgressIndicator())
          : _PanelContent(
              admin:              _admin!,
              tabController:      _tabController,
              vehiculosStream:    _vehiculosStream,
              conductoresStream:  _conductoresStream,
              onToggleVehiculo:   _toggleVehiculo,
              onAsignar:          _showAsignarDialog,
              onToggleConductor:  _toggleConductor,
              onAgregarVehiculo:  _showAgregarVehiculoDialog,
              onAgregarConductor: _showAgregarConductorDialog,
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CONTENIDO PRINCIPAL DEL PANEL
// ══════════════════════════════════════════════════════════════════
class _PanelContent extends StatelessWidget {
  final UserModel                                  admin;
  final TabController                              tabController;
  final Stream<List<VehicleModel>>                 vehiculosStream;
  final Stream<List<UserModel>>                    conductoresStream;
  final void Function(VehicleModel)                onToggleVehiculo;
  final void Function(VehicleModel, List<UserModel>) onAsignar;
  final void Function(UserModel)                   onToggleConductor;
  final VoidCallback                               onAgregarVehiculo;
  final VoidCallback                               onAgregarConductor;

  const _PanelContent({
    required this.admin,
    required this.tabController,
    required this.vehiculosStream,
    required this.conductoresStream,
    required this.onToggleVehiculo,
    required this.onAsignar,
    required this.onToggleConductor,
    required this.onAgregarVehiculo,
    required this.onAgregarConductor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // PageHeader con acciones
      ListenableBuilder(
        listenable: tabController,
        builder: (_, __) => PageHeader(
          title: tabController.index == 0
              ? 'Flota de vehículos'
              : 'Conductores',
          description: tabController.index == 0
              ? 'Gestión de vehículos de ${admin.institucionId ?? "la institución"}'
              : 'Conductores activos de la institución',
          actions: [
            FilledButton.icon(
              onPressed: tabController.index == 0
                  ? onAgregarVehiculo
                  : onAgregarConductor,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tabController.index == 0
                  ? 'Agregar vehículo'
                  : 'Agregar conductor'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),

      // TabBar
      Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: TabBar(
          controller: tabController,
          tabs: const [
            Tab(icon: Icon(Icons.directions_car), text: 'Vehículos'),
            Tab(icon: Icon(Icons.badge_outlined),  text: 'Conductores'),
          ],
        ),
      ),

      // Contenido de tabs
      Expanded(
        child: TabBarView(
          controller: tabController,
          children: [
            _VehiculosTab(
              vehiculosStream:   vehiculosStream,
              conductoresStream: conductoresStream,
              onToggle:          onToggleVehiculo,
              onAsignar:         onAsignar,
            ),
            _ConductoresTab(
              stream:    conductoresStream,
              onToggle:  onToggleConductor,
            ),
          ],
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
// TABS
// ══════════════════════════════════════════════════════════════════
class _VehiculosTab extends StatelessWidget {
  final Stream<List<VehicleModel>> vehiculosStream;
  final Stream<List<UserModel>>    conductoresStream;
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
      builder: (ctx, condSnap) {
        final conductores = condSnap.data ?? [];
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
              return AdminEmptyState(
                icon:       Icons.local_shipping_outlined,
                mensaje:    'Sin vehículos registrados',
                sugerencia: 'Toca "Agregar vehículo" para registrar el primero',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AdminDesign.s3),
              itemCount: vehiculos.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AdminDesign.s1),
              itemBuilder: (ctx, i) {
                final v = vehiculos[i];
                final cAsignado = conductores
                    .where((c) => c.uid == v.conductorAsignadoUid)
                    .firstOrNull;
                return _VehicleCard(
                  vehicle:           v,
                  conductorAsignado: cAsignado,
                  onToggle:          () => onToggle(v),
                  onAsignar:         () => onAsignar(v, conductores),
                );
              },
            );
          },
        );
      },
    );
  }
}

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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final conductores = snap.data ?? [];
        if (conductores.isEmpty) {
          return AdminEmptyState(
            icon:       Icons.badge_outlined,
            mensaje:    'Sin conductores registrados',
            sugerencia: 'Toca "Agregar conductor" para crear el primero',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AdminDesign.s3),
          itemCount: conductores.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AdminDesign.s1),
          itemBuilder: (ctx, i) => _ConductorCard(
            conductor: conductores[i],
            onToggle:  () => onToggle(conductores[i]),
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
  final UserModel?   conductorAsignado;
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
            const SizedBox(width: AdminDesign.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vehicle.patente, style: tt.titleMedium),
                  const SizedBox(height: 2),
                  AdminStatusChip(
                    activo: vehicle.activo,
                    label:  '${vehicle.tipoLabel} · '
                            '${vehicle.activo ? "Activo" : "Inactivo"}',
                  ),
                  const SizedBox(height: 2),
                  Text(vehicle.institucionNombre, style: tt.bodySmall),
                ],
              ),
            ),
            Semantics(
              label: vehicle.activo
                  ? 'Desactivar ${vehicle.patente}'
                  : 'Activar ${vehicle.patente}',
              child: Switch(
                value:     vehicle.activo,
                onChanged: (_) => onToggle(),
              ),
            ),
          ]),

          const Divider(height: AdminDesign.s3),

          Row(children: [
            Icon(
              conductorAsignado != null
                  ? Icons.person
                  : Icons.person_add_alt_1_outlined,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: AdminDesign.s1),
            Expanded(
              child: Text(
                conductorAsignado?.nombre ?? 'Sin conductor asignado',
                style: conductorAsignado != null
                    ? tt.bodyMedium
                    : tt.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                overflow: TextOverflow.ellipsis,
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
                padding:        const EdgeInsets.symmetric(
                    horizontal: AdminDesign.s1, vertical: 4),
                minimumSize:    Size.zero,
                tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  IconData _iconoTipo(VehicleType tipo) => switch (tipo) {
        VehicleType.ambulancia  => Icons.local_hospital,
        VehicleType.bomberos    => Icons.local_fire_department,
        VehicleType.carabineros => Icons.local_police,
        VehicleType.otro        => Icons.emergency,
      };
}

class _ConductorCard extends StatelessWidget {
  final UserModel    conductor;
  final VoidCallback onToggle;

  const _ConductorCard({
    required this.conductor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
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
        title: Text(conductor.nombre,
            style: tt.titleMedium,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conductor.email,
                style: tt.bodySmall,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            AdminStatusChip(
              activo: conductor.activo,
              label:  conductor.activo ? 'Activo' : 'Inactivo',
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Semantics(
          label: conductor.activo
              ? 'Desactivar ${conductor.nombre}'
              : 'Activar ${conductor.nombre}',
          child: Switch(
            value:     conductor.activo,
            onChanged: (_) => onToggle(),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// DIALOGS
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          const SizedBox(height: AdminDesign.s2),
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
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16,
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
      id:               const Uuid().v4(),
      patente:          _patenteCtrl.text.trim().toUpperCase(),
      tipo:             _tipo,
      institucionId:    widget.institucionId,
      institucionNombre: widget.institucionNombre,
      activo:           true,
      createdAt:        DateTime.now(),
    );
    await widget.onSave(vehicle);
  }

  @override
  void dispose() { _patenteCtrl.dispose(); super.dispose(); }
}

class _ConductorFormDialog extends StatefulWidget {
  final String                        institucionId;
  final Stream<List<VehicleModel>>    vehiculosStream;
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingresa el nombre' : null,
            ),
            const SizedBox(height: AdminDesign.s2),
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
            const SizedBox(height: AdminDesign.s2),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Contraseña temporal',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass
                      ? Icons.visibility_off : Icons.visibility),
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
            const SizedBox(height: AdminDesign.s1),
            Text(
              'El conductor usará estas credenciales para ingresar a la app.',
              style: tt.bodySmall,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16,
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
    _nombreCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }
}

class _AsignarConductorDialog extends StatefulWidget {
  final VehicleModel             vehiculo;
  final List<UserModel>          conductores;
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
    final tt     = Theme.of(context).textTheme;
    final activos = widget.conductores.where((c) => c.activo).toList();

    return AlertDialog(
      title: Text('Asignar conductor\n${widget.vehiculo.patente}',
          style: tt.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AdminDesign.s2),
              child: Text(
                'No hay conductores activos disponibles.\n'
                'Agrega conductores en la pestaña "Conductores".',
                style: tt.bodyMedium,
              ),
            )
          else ...[
            RadioListTile<String?>(
              value:      null,
              groupValue: _seleccionado,
              onChanged:  (v) => setState(() => _seleccionado = v),
              title: Text('Sin asignar',
                  style: tt.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const Divider(height: 8),
            ...activos.map((c) => RadioListTile<String?>(
                  value:      c.uid,
                  groupValue: _seleccionado,
                  onChanged:  (v) => setState(() => _seleccionado = v),
                  title:    Text(c.nombre, style: tt.bodyMedium),
                  subtitle: Text(c.email,  style: tt.bodySmall),
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
          onPressed: (_saving || activos.isEmpty) ? null : () async {
            setState(() => _saving = true);
            await widget.onAsignar(_seleccionado);
          },
          child: _saving
              ? const SizedBox(height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
