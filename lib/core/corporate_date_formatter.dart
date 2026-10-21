// lib/core/corporate_date_formatter.dart
// Formato corporativo de fecha en español de Chile.
// "Lunes, 19 de octubre de 2026" — inicial mayúscula en el día.
//
// Spec: web-admin-corporativo — Task 2.2

import 'package:intl/intl.dart';

/// Formatea [date] como "Lunes, 19 de octubre de 2026" en es_CL.
/// Requiere que se haya llamado initializeDateFormatting('es_CL') previamente.
String formatCorporateDate(DateTime date) {
  final raw = DateFormat("EEEE, d 'de' MMMM 'de' y", 'es_CL').format(date);
  // Capitalizar primera letra del día de la semana
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

/// Formato abreviado para pantallas medianas: "19 oct 2026".
String formatCorporateDateShort(DateTime date) {
  return DateFormat("d MMM y", 'es_CL').format(date);
}
