// lib/services/admin_header_repository.dart
// Lee solo el documento del usuario autenticado y construye AdminHeaderInfo.
// Requisito 7: solo datos del propio administrador.

import '../models/admin_header_info.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

class AdminHeaderRepository {
  final AuthService _authSvc;

  AdminHeaderRepository({AuthService? authService})
      : _authSvc = authService ?? AuthService();

  /// Obtiene los datos de encabezado del admin autenticado.
  /// Lanza excepción si no hay sesión activa.
  Future<AdminHeaderInfo> fetchHeaderInfo() async {
    final fbUser = _authSvc.currentUser;
    if (fbUser == null) throw Exception('Sin sesión activa');

    final user = await _authSvc.getUserById(fbUser.uid);
    return _fromUser(user);
  }

  /// Stream en tiempo real para actualizaciones del perfil.
  Stream<AdminHeaderInfo> watchHeaderInfo() {
    final fbUser = _authSvc.currentUser;
    if (fbUser == null) return const Stream.empty();

    return _authSvc
        .watchUserById(fbUser.uid)
        .map(_fromUser);
  }

  AdminHeaderInfo _fromUser(UserModel user) => AdminHeaderInfo(
        nombre:      user.nombre,
        institucion: user.institucionId ?? '',
      );
}
