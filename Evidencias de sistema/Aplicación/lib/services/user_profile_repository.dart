// lib/services/user_profile_repository.dart
// Gestiona la lectura y escritura de los campos de aviso de privacidad
// en el documento users/{uid} de Firestore y localmente en SharedPreferences
// para usuarios particulares sin sesión iniciada (modo invitado/anónimo).
// Solo toca privacy_notice_version y privacy_notice_ack_at, nunca otros campos.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class UserProfileRepository {
  final FirebaseFirestore _firestore;

  UserProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Devuelve la versión del aviso de privacidad aceptada localmente en el dispositivo.
  Future<int> getLocalPrivacyNoticeVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(AppConstants.prefPrivacyNoticeAcceptedVersion) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Guarda localmente en SharedPreferences que el usuario aceptó la versión [version].
  Future<void> acknowledgeLocalPrivacyNotice(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefPrivacyNoticeAcceptedVersion, version);
  }

  /// Devuelve la versión del aviso de privacidad aceptada por el usuario.
  /// Retorna el máximo entre la versión local y la de Firestore (0 si no existe).
  Future<int> getPrivacyNoticeVersion(String uid) async {
    final localVersion = await getLocalPrivacyNoticeVersion();
    try {
      final doc = await _firestore
          .collection(AppConstants.colUsers)
          .doc(uid)
          .get();

      if (!doc.exists) return localVersion;

      final data = doc.data();
      if (data == null) return localVersion;

      final remoteVersion = (data['privacy_notice_version'] as int?) ?? 0;
      return remoteVersion > localVersion ? remoteVersion : localVersion;
    } catch (_) {
      return localVersion;
    }
  }

  /// Guarda en SharedPreferences y en Firestore (si hay uid válido) que el
  /// usuario aceptó la versión [version] del aviso de privacidad en [DateTime.now()].
  /// Usa SetOptions(merge: true) para no sobreescribir otros campos.
  Future<void> acknowledgePrivacyNotice(String uid, int version) async {
    await acknowledgeLocalPrivacyNotice(version);
    if (uid.isEmpty) return;

    await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .set(
          {
            'privacy_notice_version': version,
            'privacy_notice_ack_at': DateTime.now().toIso8601String(),
          },
          SetOptions(merge: true),
        );
  }
}
