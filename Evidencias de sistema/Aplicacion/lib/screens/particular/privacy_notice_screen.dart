// lib/screens/particular/privacy_notice_screen.dart
// Pantalla de aviso de privacidad para conductores particulares.
// Se muestra una vez, la primera vez que el conductor inicia sesión,
// antes de acceder a la pantalla principal.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/user_profile_repository.dart';

class PrivacyNoticeScreen extends StatefulWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  State<PrivacyNoticeScreen> createState() => _PrivacyNoticeScreenState();
}

class _PrivacyNoticeScreenState extends State<PrivacyNoticeScreen> {
  bool _loading = false;

  Future<void> _acknowledge() async {
    setState(() => _loading = true);

    try {
      final authSvc = context.read<AuthService>();
      final repo = UserProfileRepository();

      // Guardar aceptación siempre localmente (modo sin cuenta)
      // y en Firestore únicamente si tiene cuenta registrada activa.
      final registeredUid =
          authSvc.isRegisteredUser ? (authSvc.currentUser?.uid ?? '') : '';

      await repo.acknowledgePrivacyNotice(
        registeredUid,
        AppConstants.privacyNoticeCurrentVersion,
      );

      if (mounted) context.go(AppConstants.routeHomeParticular);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar la aceptación. Inténtalo de nuevo.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícono decorativo
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 40,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Título
              Text(
                'Tu privacidad en Vía Libre',
                style: textTheme.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Antes de continuar, queremos que sepas exactamente cómo usamos tu ubicación.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Punto 1
              const _PrivacyPoint(
                icon: Icons.location_on_outlined,
                text:
                    'Tu ubicación se usa solo para calcular si hay vehículos de emergencia cerca.',
              ),
              const SizedBox(height: 20),

              // Punto 2
              const _PrivacyPoint(
                icon: Icons.storage_outlined,
                text:
                    'Tu trayectoria no se almacena en ningún servidor ni base de datos.',
              ),
              const SizedBox(height: 20),

              // Punto 3
              const _PrivacyPoint(
                icon: Icons.people_outline,
                text:
                    'Tu ubicación no se comparte con otros conductores ni usuarios.',
              ),
              const SizedBox(height: 48),

              // Botón de aceptación
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _acknowledge,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.textDisabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text(
                          'Entendido y continuar al mapa',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.go(AppConstants.routeLogin),
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  label: const Text('Acceso Emergencias / Administración'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget auxiliar: punto de privacidad ──────────────────────────
class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PrivacyPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.accent, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
          ),
        ),
      ],
    );
  }
}
