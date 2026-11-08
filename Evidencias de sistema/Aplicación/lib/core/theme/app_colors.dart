// lib/core/theme/app_colors.dart
// Design system "Vía Libre" — paleta canónica del spec .kiro/specs/colors.md
// NUNCA usar Color(0xFF...) directamente en widgets. Siempre AppColors.X

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Fondos y superficies ──────────────────────────────────────
  static const Color background   = Color(0xFFFFFFFF); // blanco puro — spec §3
  static const Color surface      = Color(0xFFFFFFFF); // tarjetas, formularios
  static const Color surfaceTint  = Color(0xFFF3F6FA); // chips inactivos, filas alternas
  static const Color divider      = Color(0xFFE1E5EA); // bordes decorativos
  static const Color inputBorder  = Color(0xFF8591A3); // borde de campos (3:1 sobre blanco)

  // ── Marca y acentos ───────────────────────────────────────────
  static const Color primary    = Color(0xFF12355B); // botones ppal, app bar, marca
  static const Color onPrimary  = Color(0xFFFFFFFF); // texto/ícono sobre primary
  static const Color accent     = Color(0xFF2F6FDE); // acción destacada, foco, switch
  static const Color onAccent   = Color(0xFFFFFFFF); // texto/ícono sobre accent
  static const Color accentDark = Color(0xFF1B4FA8); // texto de estado activo sobre accentSoft
  static const Color accentSoft = Color(0xFFE3ECFB); // fondo chip estado activo
  static const Color info       = Color(0xFF4C8DDB); // mapa, telemetría, marcadores
  static const Color link       = Color(0xFF1B4FA8); // enlaces, acciones de texto — spec §3

  // ── Texto ─────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF101C2B); // 17:1 sobre blanco
  static const Color textSecondary = Color(0xFF5B6677); // 5.8:1 sobre blanco
  static const Color textDisabled  = Color(0xFF8A94A3); // 3:1 — solo elementos deshabilitados

  // ── Alertas (uso EXCLUSIVO para vehículos de emergencia) ──────
  /// Amarillo — anticipación (30-45 s). Texto encima: textPrimary (NUNCA blanco).
  static const Color alertAnticipation = Color(0xFFFFC400);
  /// Bermellón — crítico (radio inminente). Texto encima: blanco.
  static const Color alertCritical     = Color(0xFFF0322A);

  // ── Error de sistema (no es alerta) ──────────────────────────
  static const Color error     = Color(0xFFB3261E); // validaciones, fallos, botón eliminar
  static const Color errorSoft = Color(0xFFFCE8E6); // fondo de mensajes de error
}

// ── Enum de nivel de alerta ───────────────────────────────────────
/// Usado en AlertOverlay y EmergencyFab.
/// Nunca pasar Color directamente: usar AlertLevel.
enum AlertLevel { anticipation, critical }

extension AlertLevelStyle on AlertLevel {
  Color get color => switch (this) {
        AlertLevel.anticipation => AppColors.alertAnticipation,
        AlertLevel.critical     => AppColors.alertCritical,
      };

  /// Anticipación: texto oscuro sobre amarillo (nunca blanco — spec regla 3).
  /// Crítica: blanco sobre bermellón.
  Color get onColor => switch (this) {
        AlertLevel.anticipation => AppColors.textPrimary,
        AlertLevel.critical     => Colors.white,
      };

  IconData get icon => switch (this) {
        AlertLevel.anticipation => Icons.warning_amber_rounded,
        AlertLevel.critical     => Icons.emergency_share,
      };

  String get label => switch (this) {
        AlertLevel.anticipation => 'Vehículo de emergencia cerca',
        AlertLevel.critical     => 'EMERGENCIA INMINENTE',
      };
}
