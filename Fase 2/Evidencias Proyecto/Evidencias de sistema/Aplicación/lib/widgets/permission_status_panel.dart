// lib/widgets/permission_status_panel.dart
// Panel visual que comunica al conductor particular el estado de preparación
// del sistema de alertas.
// Requisito R3.3 del spec alerta-proximidad-particular.

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/readiness_state.dart';

class PermissionStatusPanel extends StatefulWidget {
  const PermissionStatusPanel({
    super.key,
    required this.readiness,
    this.onRequestPermissions,
  });

  final ReadinessState readiness;
  final VoidCallback? onRequestPermissions;

  @override
  State<PermissionStatusPanel> createState() => _PermissionStatusPanelState();
}

class _PermissionStatusPanelState extends State<PermissionStatusPanel> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: widget.readiness.isReady
            ? _buildReadyRow()
            : _buildNotReadyColumn(),
      ),
    );
  }

  // ── Estado listo ─────────────────────────────────────────────
  Widget _buildReadyRow() {
    return const Row(
      children: [
        Icon(
          Icons.verified_user,
          color: AppColors.accent,
        ),
        SizedBox(width: 12),
        Text(
          'Protección activa',
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Estado no listo ──────────────────────────────────────────
  Widget _buildNotReadyColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Las alertas no funcionarán hasta completar los permisos',
          style: TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildPermissionTile(
          status: widget.readiness.locationRealtime,
          title: 'Ubicación en tiempo real',
        ),
        _buildPermissionTile(
          status: widget.readiness.backgroundExec,
          title: 'Ejecución en segundo plano',
        ),
        _buildPermissionTile(
          status: widget.readiness.notifications,
          title: 'Notificaciones',
        ),
      ],
    );
  }

  // ── ListTile individual ──────────────────────────────────────
  Widget _buildPermissionTile({
    required ItemStatus status,
    required String title,
  }) {
    final IconData iconData;
    final Color iconColor;

    switch (status) {
      case ItemStatus.ok:
        iconData = Icons.check_circle;
        iconColor = Colors.green;
      case ItemStatus.missing:
        iconData = Icons.warning_amber;
        iconColor = AppColors.alertAnticipation;
      case ItemStatus.unavailable:
        iconData = Icons.info_outline;
        iconColor = AppColors.textSecondary;
    }

    final Widget? trailing = status == ItemStatus.missing
        ? SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: widget.onRequestPermissions,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Corregir'),
            ),
          )
        : null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(iconData, color: iconColor),
      title: Text(title),
      trailing: trailing,
    );
  }
}
