// lib/core/admin_design.dart
// Constantes de diseño corporativo del panel web — sistema de diseño único.
// Espaciado en múltiplos de 8 dp. Puntos de quiebre responsive.
// Spec: web-admin-corporativo — Tasks 1.2, 6.1

class AdminDesign {
  AdminDesign._();

  // ── Espaciado (cuadrícula de 8 dp) ────────────────────────────
  static const double s1  =  8.0;
  static const double s2  = 16.0;
  static const double s3  = 24.0;
  static const double s4  = 32.0;
  static const double s5  = 40.0;
  static const double s6  = 48.0;

  // ── Barra superior ────────────────────────────────────────────
  static const double topBarHeight    = 64.0;
  static const double topBarElevation =  0.0;

  // ── Navegación lateral ────────────────────────────────────────
  static const double sideNavWidthExpanded  = 240.0;
  static const double sideNavWidthCollapsed =  64.0;

  // ── Contenido ─────────────────────────────────────────────────
  static const double contentMaxWidth = 1440.0;
  static const double contentPadding  =   24.0;

  // ── Radios ────────────────────────────────────────────────────
  static const double radiusCard   = 12.0;
  static const double radiusChip   = 999.0;
  static const double radiusAvatar =  20.0; // para CircleAvatar 40 px

  // ── Puntos de quiebre (Task 6.1) ─────────────────────────────
  /// < 720 dp: solo iconos en nav, barra compacta
  static const double breakpointCompact = 720.0;
  /// 720–1100 dp: fecha abreviada, nav colapsada
  static const double breakpointMedium  = 1100.0;
  /// > 1100 dp: layout completo
}
