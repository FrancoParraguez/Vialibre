// lib/services/auth_service.dart
// Gestiona autenticación con Firebase Auth y sincronización de perfil en Firestore.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../firebase_options.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Stream del estado de autenticación ────────────────────────
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // ── Registro ──────────────────────────────────────────────────
  Future<UserModel> registerWithEmail({
    required String email,
    required String password,
    required String nombre,
    required UserRole rol,
    String? institucionId,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = UserModel(
      uid: credential.user!.uid,
      nombre: nombre,
      email: email,
      rol: rol,
      institucionId: institucionId,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.colUsers)
        .doc(user.uid)
        .set(user.toMap());

    return user;
  }

  // ── Login ─────────────────────────────────────────────────────
  Future<UserModel> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return getUserById(credential.user!.uid);
  }

  // ── Obtener perfil de Firestore ───────────────────────────────
  Future<UserModel> getUserById(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .get();

    if (!doc.exists) throw Exception('Usuario no encontrado');

    return UserModel.fromMap({'uid': doc.id, ...doc.data()!});
  }

  // ── Crear conductor (rol emergencia) para una institución ─────
  /// Usa la REST API de Firebase Auth para crear el usuario sin
  /// afectar la sesión activa del admin (funciona en web y móvil).
  Future<UserModel> createConductor({
    required String email,
    required String password,
    required String nombre,
    required String institucionId,
  }) async {
    // API key de la plataforma actual
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final url = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
    );

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': false,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errorMsg = (body['error']?['message'] as String?) ?? 'ERROR_DESCONOCIDO';
      throw Exception(errorMsg);
    }

    final uid = body['localId'] as String;

    final conductor = UserModel(
      uid: uid,
      nombre: nombre,
      email: email,
      rol: UserRole.emergencia,
      institucionId: institucionId,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .set(conductor.toMap());

    return conductor;
  }

  // ── Stream de conductores de una institución ──────────────────
  Stream<List<UserModel>> getConductoresByInstitucion(String institucionId) {
    return _firestore
        .collection(AppConstants.colUsers)
        .where('rol', isEqualTo: UserRole.emergencia.name)
        .where('institucion_id', isEqualTo: institucionId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => UserModel.fromMap({'uid': d.id, ...d.data()}))
            .toList());
  }

  // ── Asignar conductor a vehículo ─────────────────────────────
  /// Actualiza el campo conductor_asignado_uid en el documento del vehículo.
  /// Pasa null para desasignar.
  Future<void> asignarConductor({
    required String vehiculoId,
    required String? conductorUid,
  }) async {
    await _firestore
        .collection(AppConstants.colVehicles)
        .doc(vehiculoId)
        .update({'conductor_asignado_uid': conductorUid});
  }

  // ── Activar / desactivar conductor ────────────────────────────
  Future<void> setConductorActivo(String uid, bool activo) async {
    await _firestore
        .collection(AppConstants.colUsers)
        .doc(uid)
        .update({'activo': activo});
  }

  // ── Eliminar conductor de Firestore (no borra Auth) ───────────
  Future<void> deleteConductor(String uid) async {
    await _firestore.collection(AppConstants.colUsers).doc(uid).delete();
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> signOut() => _auth.signOut();

  // ── Recuperar contraseña ──────────────────────────────────────
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}
