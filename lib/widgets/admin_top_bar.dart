// lib/widgets/admin_top_bar.dart
// Barra superior corporativa fija del panel web de administración.
// Altura 64 dp. Logo + nombre a la izquierda; fecha + bloque usuario a la derecha.
// Spec: web-admin-corporativo — Task 3

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/admin_design.dart';
import '../core/corporate_date_formatter.dart';
import '../core/theme/app_colors.dart';
import '../models/admin_header_info.dart';
import '../services/admin_header_repository.dart';
import '../services/date_provider.dart';

class AdminTopBar extends StatefulWidget implements PreferredSizeWidget {
  final VoidCallback? onLogout;
  final VoidCallback? onPerfil;

  const AdminTopBar({
    super.key,
    this.onLogout,
    this.onPerfil,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AdminDesign.topBarHeight);

  @override
  State<AdminTopBar> createState() => _AdminTopBarState();
}

class _AdminTopBarState extends State<AdminTopBar> {
  final _repo = AdminHeaderRepository();
  AdminHeaderInfo? _info;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _repo.watchHeaderInfo().listen(
      (info) { if (mounted) setState(() { _info = info; _error = null; }); },
      onError: (e) { if (mounted) setState(() => _error = e); },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < AdminDesign.breakpointCompact;
    final isMedium  = width < AdminDesign.breakpointMedium;

    return Material(
      color:     AppColors.primary,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AdminDesign.topBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AdminDesign.s3),
            child: Row(children: [
              // ── Logo + nombre ─────────────────────────────────
              _LogoSection(compact: isCompact),

              const Spacer(),

              // ── Fecha ─────────────────────────────────────────
              if (!isCompact)
                _DateSection(abbreviated: isMedium),

              const SizedBox(width: AdminDesign.s3),

              // ── Bloque de usuario ─────────────────────────────
              _UserBlock(
                info:      _info,
                error:     _error,
                compact:   isCompact,
                onLogout:  widget.onLogout,
                onPerfil:  widget.onPerfil,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Logo + "Vía Libre" ────────────────────────────────────────────
class _LogoSection extends StatelessWidget {
  final bool compact;
  const _LogoSection({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vía Libre — Panel de administración',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SvgPicture.asset(
          'assets/images/logo-app.svg',
          width: 36, height: 36,
        ),
        if (!compact) ...[
          const SizedBox(width: AdminDesign.s1),
          const Text(
            'Vía Libre',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Fecha ─────────────────────────────────────────────────────────
class _DateSection extends StatelessWidget {
  final bool abbreviated;
  const _DateSection({required this.abbreviated});

  @override
  Widget build(BuildContext context) {
    final today = context.watch<DateProvider>().today;
    final label = abbreviated
        ? formatCorporateDateShort(today)
        : formatCorporateDate(today);

    return Semantics(
      label: 'Fecha actual: $label',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined,
            size: 14, color: AppColors.onPrimary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ]),
    );
  }
}

// ── Bloque de usuario ─────────────────────────────────────────────
class _UserBlock extends StatelessWidget {
  final AdminHeaderInfo? info;
  final Object? error;
  final bool compact;
  final VoidCallback? onLogout;
  final VoidCallback? onPerfil;

  const _UserBlock({
    required this.info,
    required this.error,
    required this.compact,
    this.onLogout,
    this.onPerfil,
  });

  @override
  Widget build(BuildContext context) {
    // Estado de carga
    if (info == null && error == null) return _skeleton();

    // Estado de error
    if (error != null) {
      return Tooltip(
        message: error.toString(),
        child: const Icon(Icons.error_outline,
            color: AppColors.onPrimary, size: 20),
      );
    }

    final h = info!;

    return Semantics(
      button: true,
      label: 'Menú de usuario: ${h.nombre}, ${h.institucionLabel}',
      child: PopupMenuButton<String>(
        tooltip: 'Opciones de usuario',
        offset: const Offset(0, AdminDesign.topBarHeight - 8),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminDesign.radiusCard),
          side: const BorderSide(color: AppColors.divider),
        ),
        onSelected: (v) {
          if (v == 'logout' && onLogout != null) onLogout!();
          if (v == 'perfil' && onPerfil != null) onPerfil!();
        },
        itemBuilder: (_) => [
          // Encabezado informativo (no seleccionable)
          PopupMenuItem<String>(
            enabled: false,
            child: _UserMenuHeader(info: h),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'perfil',
            child: const Row(children: [
              Icon(Icons.person_outline,
                  size: 18, color: AppColors.textSecondary),
              SizedBox(width: AdminDesign.s1),
              Text('Mi perfil'),
            ]),
          ),
          PopupMenuItem<String>(
            value: 'logout',
            child: const Row(children: [
              Icon(Icons.logout, size: 18, color: AppColors.error),
              SizedBox(width: AdminDesign.s1),
              Text('Cerrar sesión',
                  style: TextStyle(color: AppColors.error)),
            ]),
          ),
        ],
        child: _UserChip(info: h, compact: compact),
      ),
    );
  }

  Widget _skeleton() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: AdminDesign.s1),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                width: 90, height: 10,
                color: AppColors.onPrimary.withValues(alpha: 0.2)),
            const SizedBox(height: 4),
            Container(
                width: 60, height: 8,
                color: AppColors.onPrimary.withValues(alpha: 0.15)),
          ],
        ),
      ],
    ]);
  }
}

// ── Chip visual del usuario (trigger del menú) ────────────────────
class _UserChip extends StatelessWidget {
  final AdminHeaderInfo info;
  final bool compact;
  const _UserChip({required this.info, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Avatar con iniciales
      CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.accent,
        child: Text(
          info.iniciales,
          style: const TextStyle(
            color: AppColors.onAccent,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: AdminDesign.s1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.nombre,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
              Tooltip(
                message: info.institucionLabel,
                child: Text(
                  info.institucionLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: info.sinInstitucion
                        ? AppColors.onPrimary.withValues(alpha: 0.5)
                        : AppColors.onPrimary.withValues(alpha: 0.8),
                    fontStyle: info.sinInstitucion
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.arrow_drop_down,
            color: AppColors.onPrimary, size: 18),
      ],
    ]);
  }
}

// ── Encabezado del menú desplegable ───────────────────────────────
class _UserMenuHeader extends StatelessWidget {
  final AdminHeaderInfo info;
  const _UserMenuHeader({required this.info});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.accentSoft,
            child: Text(
              info.iniciales,
              style: const TextStyle(
                color: AppColors.accentDark,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: AdminDesign.s1),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.nombre,
                    style: tt.titleMedium,
                    overflow: TextOverflow.ellipsis),
                const Text('Administrador',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.business_outlined,
              size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              info.institucionLabel,
              style: TextStyle(
                fontSize: 12,
                color: info.sinInstitucion
                    ? AppColors.textDisabled
                    : AppColors.textSecondary,
                fontStyle: info.sinInstitucion
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ],
    );
  }
}
