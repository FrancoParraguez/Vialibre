// lib/core/theme.dart

import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(AppColors.primaryBlue),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(AppColors.surfaceLight),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(AppColors.primaryBlue),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(AppColors.primaryBlue),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(AppColors.primaryBlue), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(AppColors.textPrimary)),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(AppColors.textPrimary)),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(AppColors.textPrimary)),
      bodyLarge: TextStyle(fontSize: 16, color: Color(AppColors.textPrimary)),
      bodyMedium: TextStyle(fontSize: 14, color: Color(AppColors.textSecondary)),
    ),
  );

  // Tema para modo emergencia activo (overlay oscuro + rojo)
  static ThemeData get emergency => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(AppColors.accentRed),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(AppColors.backgroundDark),
  );
}
