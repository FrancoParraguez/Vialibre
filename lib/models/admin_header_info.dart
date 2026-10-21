// lib/models/admin_header_info.dart
// Datos que muestra la barra superior corporativa del panel web.
// institucion: valor directo de users.institucion_id (almacena el nombre).

import 'package:equatable/equatable.dart';

class AdminHeaderInfo extends Equatable {
  final String nombre;
  final String institucion; // puede estar vacío → mostrar fallback

  const AdminHeaderInfo({
    required this.nombre,
    required this.institucion,
  });

  /// Hasta 2 iniciales en mayúscula. Respaldo "A" si no hay nombre.
  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return 'A';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }

  /// Institución o texto de respaldo.
  String get institucionLabel =>
      institucion.trim().isEmpty ? 'Institución no registrada' : institucion;

  /// true cuando no hay institución registrada.
  bool get sinInstitucion => institucion.trim().isEmpty;

  @override
  List<Object?> get props => [nombre, institucion];
}
