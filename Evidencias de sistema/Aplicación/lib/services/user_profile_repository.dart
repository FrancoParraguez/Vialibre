// lib/services/user_profile_repository.dart
// Gestiona la lectura y escritura de los campos de aviso de privacidad
// en el documento users/{uid} de Firestore.
// Solo toca privacy_notice_version y privacy_notice_ack_at, nunca otros campos.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class UserProfileRepository {
  final FirebaseFirestore _firestore;

  UserProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Devuelve la versión del aviso de privacidad aceptada por el usuario.
  /// Retorna 0 si el campo no existe o el documento no existe.
  Future<int> getPrivacyNoticeVersion(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .get();

    if (!doc.exists) return 0;

    final data = doc.data();
    if (data == null) return 0;

    return (data['privacy_notice_version'] as int?) ?? 0;
  }

  /// Guarda en Firestore que el usuario [uid] aceptó la versión [version]
  /// del aviso de privacidad en [DateTime.now()].
  /// Usa SetOptions(merge: true) para no sobreescribir otros campos.
  Future<void> acknowledgePrivacyNotice(String uid, int version) async {
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
