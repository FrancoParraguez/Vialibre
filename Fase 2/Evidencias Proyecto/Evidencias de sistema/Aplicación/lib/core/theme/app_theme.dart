// lib/core/theme/app_theme.dart
// Design system Vía Libre — spec .kiro/specs/colors.md §6.
// Principio rector: la interfaz es blanca y el texto es oscuro.
// light → única entrada para toda la app (ThemeMode.light en MaterialApp).

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const double _radiusField  = 12.0;
  static const double _radiusCard   = 16.0;
  static const double _radiusDialog = 20.0;

  static OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: BorderSide(color: color, width: width),
      );

  // ── Escala tipográfica — spec §5 ─────────────────────────────
  static const TextTheme _text = TextTheme(
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge:     TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium:    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    bodyLarge:      TextStyle(fontSize: 16, color: AppColors.textPrimary),
    bodyMedium:     TextStyle(fontSize: 14, color: AppColors.textSecondary),
    bodySmall:      TextStyle(fontSize: 12, color: AppColors.textSecondary),
    labelLarge:     TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
  );

  // ── Tema claro (única entrada) ────────────────────────────────
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: _text,

    colorScheme: const ColorScheme.light(
      primary:                 AppColors.primary,
      onPrimary:               AppColors.onPrimary,
      secondary:               AppColors.accent,
      onSecondary:             AppColors.onAccent,
      tertiary:                AppColors.info,
      onTertiary:              Colors.white,
      surface:                 AppColors.surface,
      onSurface:               AppColors.textPrimary,
      onSurfaceVariant:        AppColors.textSecondary,
      surfaceTint:             Colors.transparent,  // sin tinte M3
      surfaceContainerHighest: AppColors.surfaceTint,
      outline:                 AppColors.inputBorder,
      outlineVariant:          AppColors.divider,
      error:                   AppColors.error,
      onError:                 Colors.white,
      errorContainer:          AppColors.errorSoft,
      onErrorContainer:        AppColors.error,
    ),

    // ── App bar BLANCO con texto primary ─────────────────────────
    // Spec §7 (admin y todas las pantallas): app bar blanco, título primary.
    // Sin shape aquí: es incompatible con TabBar en bottom y produce overflow.
    // La línea inferior se pinta con systemOverlayStyle o con un Divider explícito.
    appBarTheme: const AppBarTheme(
      backgroundColor:        AppColors.background,
      foregroundColor:        AppColors.primary,
      surfaceTintColor:       Colors.transparent,
      elevation:              0,
      scrolledUnderElevation: 0,
      centerTitle:            true,
      iconTheme:              IconThemeData(color: AppColors.primary),
      actionsIconTheme:       IconThemeData(color: AppColors.primary),
      titleTextStyle: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.primary,
      ),
    ),

    // ── TabBar sobre fondo blanco ─────────────────────────────────
    // Spec §7: activa = primary + indicador accent; inactiva = textSecondary.
    tabBarTheme: const TabBarThemeData(
      labelColor:           AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor:       AppColors.accent,
      dividerColor:         AppColors.divider,
      labelStyle:           TextStyle(fontWeight: FontWeight.w600),
    ),

    // ── Tarjetas: borde divider, sin elevación ────────────────────
    cardTheme: CardThemeData(
      color:            AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation:        0,
      margin:           EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusCard),
        side: const BorderSide(color: AppColors.divider),
      ),
    ),

    // ── Inputs — estilo global; los widgets NO repiten estilos de campo ──
    inputDecorationTheme: InputDecorationTheme(
      filled:              true,
      fillColor:           AppColors.surface,
      contentPadding:      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle:          const TextStyle(color: AppColors.textSecondary),
      floatingLabelStyle:  const TextStyle(color: AppColors.primary),
      hintStyle:           const TextStyle(color: AppColors.textSecondary),
      helperStyle:         const TextStyle(color: AppColors.textSecondary),
      errorStyle:          const TextStyle(color: AppColors.error),
      prefixIconColor:     AppColors.textSecondary,
      suffixIconColor:     AppColors.textSecondary,
      border:              _border(AppColors.inputBorder),
      enabledBorder:       _border(AppColors.inputBorder),
      focusedBorder:       _border(AppColors.accent, 2),
      errorBorder:         _border(AppColors.error),
      focusedErrorBorder:  _border(AppColors.error, 2),
      disabledBorder:      _border(AppColors.divider),
    ),

    // ── FilledButton — acción principal (accent azul) ─────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize:     const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusField)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // ── ElevatedButton — acción secundaria ───────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        minimumSize:     const Size.fromHeight(52),
        elevation:       0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusField)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // ── OutlinedButton ────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize:     const Size.fromHeight(52),
        side:            const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusField)),
      ),
    ),

    // ── TextButton — enlaces y acciones de texto ─────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.link,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // ── FAB ───────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      elevation:       2,
    ),

    // ── Switch ───────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accent : AppColors.inputBorder),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),

    // ── Chips ─────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceTint,
      labelStyle:      const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      side:            BorderSide.none,
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),

    // ── ListTile ─────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
    ),

    // ── Íconos globales ───────────────────────────────────────────
    iconTheme: const IconThemeData(color: AppColors.textSecondary),

    // ── Divisores ────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color:     AppColors.divider,
      thickness: 1,
      space:     1,
    ),

    // ── Diálogos ─────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor:  AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusDialog)),
      titleTextStyle: const TextStyle(
        fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      ),
    ),

    // ── SnackBar claro — spec §6 ──────────────────────────────────
    // Fondo blanco, texto oscuro, borde divider, acción en link.
    snackBarTheme: SnackBarThemeData(
      backgroundColor:  AppColors.surface,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      actionTextColor:  AppColors.link,
      behavior:         SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
    ),
  );
}
