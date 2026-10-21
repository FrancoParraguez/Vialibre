// lib/widgets/admin_components.dart
// Componentes reutilizables del panel web corporativo.
// PageHeader, AppCard, AdminEmptyState, helpers de snackbar.
// Spec: web-admin-corporativo — Tasks 4.2, 5.1, 5.5, 5.6

import 'package:flutter/material.dart';
import '../core/admin_design.dart';
import '../core/theme/app_colors.dart';

// ══════════════════════════════════════════════════════════════════
// PAGE HEADER
// ══════════════════════════════════════════════════════════════════

/// Encabezado de página con título, descripción y acciones opcionales.
class PageHeader extends StatelessWidget {
  final String   title;
  final String?  description;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AdminDesign.s3, AdminDesign.s3, AdminDesign.s3, AdminDesign.s2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: tt.titleLarge,
                    overflow: TextOverflow.ellipsis),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(description!,
                      style: tt.bodyMedium,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AdminDesign.s2),
            Wrap(
              spacing: AdminDesign.s1,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// APP CARD
// ══════════════════════════════════════════════════════════════════

/// Tarjeta corporativa con título, contenido y acciones opcionales.
class AppCard extends StatelessWidget {
  final String?  title;
  final Widget   child;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;

  const AppCard({
    super.key,
    this.title,
    required this.child,
    this.actions = const [],
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(AdminDesign.radiusCard),
        border:       Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AdminDesign.s2, AdminDesign.s2, AdminDesign.s2, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: tt.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  ...actions,
                ],
              ),
            ),
          Padding(
            padding: padding ??
                EdgeInsets.fromLTRB(
                  AdminDesign.s2,
                  title != null ? AdminDesign.s2 : AdminDesign.s2,
                  AdminDesign.s2,
                  AdminDesign.s2,
                ),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════

/// Estado vacío corporativo con ícono, mensaje y acción sugerida.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String   mensaje;
  final String   sugerencia;
  final Widget?  action;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.mensaje,
    required this.sugerencia,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AdminDesign.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AdminDesign.s3),
              decoration: const BoxDecoration(
                color: AppColors.surfaceTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 48, color: AppColors.textDisabled),
            ),
            const SizedBox(height: AdminDesign.s2),
            Text(mensaje,
                style: tt.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AdminDesign.s1),
            Text(sugerencia,
                style: tt.bodyMedium,
                textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AdminDesign.s3),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SNACKBAR HELPERS (Task 5.6)
// ══════════════════════════════════════════════════════════════════

/// SnackBar de éxito (verde) con ícono de check.
void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF2E7D32), // green.shade800
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminDesign.radiusCard)),
    ),
  );
}

/// SnackBar de error (fondo errorSoft, texto error).
void showErrorSnackBar(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        Icon(Icons.error_outline, color: cs.error, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(color: cs.onErrorContainer))),
      ]),
      backgroundColor: cs.errorContainer,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radiusCard),
        side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// STATUS CHIP (reutilizable en tablas y listas)
// ══════════════════════════════════════════════════════════════════

class AdminStatusChip extends StatelessWidget {
  final bool   activo;
  final String label;

  const AdminStatusChip({
    super.key,
    required this.activo,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AdminDesign.s1, vertical: 2),
        decoration: BoxDecoration(
          color: activo ? AppColors.accentSoft : AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(AdminDesign.radiusChip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: activo ? AppColors.accentDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
