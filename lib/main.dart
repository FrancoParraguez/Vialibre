// lib/main.dart
// Punto de entrada de Vía Libre.
// Inicializa Firebase, configura el router y el tema global.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/date_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/particular/home_screen.dart';
import 'screens/emergency/emergency_screen.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/particular/privacy_notice_screen.dart';

// Opciones generadas por: flutterfire configure
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación fija a vertical (más seguro mientras se conduce)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Inicializar locale es_CL para formateo de fechas corporativas
  await initializeDateFormatting('es_CL');

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ViaLibreApp());
}

// ── App root ──────────────────────────────────────────────────────
class ViaLibreApp extends StatelessWidget {
  const ViaLibreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<DateProvider>(create: (_) => DateProvider()),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light,   // light-first: nunca ThemeMode.system
        routerConfig: _router,
      ),
    );
  }
}

// ── Router ────────────────────────────────────────────────────────
final GoRouter _router = GoRouter(
  initialLocation: AppConstants.routeLogin,
  redirect: _authGuard,
  routes: [
    GoRoute(
      path: AppConstants.routeLogin,
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: AppConstants.routeRegister,
      builder: (_, __) => const RegisterScreen(),
    ),
    GoRoute(
      path: AppConstants.routeHomeParticular,
      builder: (_, __) => const HomeParticularScreen(),
    ),
    GoRoute(
      path: AppConstants.routeEmergency,
      builder: (_, __) => const EmergencyScreen(),
    ),
    GoRoute(
      path: AppConstants.routeAdmin,
      builder: (_, __) => const AdminScreen(),
    ),
    GoRoute(
      path: AppConstants.routePrivacyNotice,
      builder: (_, __) => const PrivacyNoticeScreen(),
    ),
  ],
);

/// Guarda de navegación: redirige al login si no hay sesión activa,
/// o a la pantalla correcta según el rol si ya está autenticado.
/// TASK-04: bloquea el acceso si el conductor tiene activo=false.
/// Redirige a la pantalla de aviso de privacidad si el usuario particular
/// no ha aceptado la versión actual del aviso.
Future<String?> _authGuard(BuildContext context, GoRouterState state) async {
  final authSvc  = AuthService();
  final fbUser   = authSvc.currentUser;
  final onAuth   = [AppConstants.routeLogin, AppConstants.routeRegister]
      .contains(state.matchedLocation);

  // No hay sesión activa → forzar login
  if (fbUser == null) {
    return onAuth ? null : AppConstants.routeLogin;
  }

  // Permitir acceso libre a la pantalla de aviso de privacidad
  if (state.matchedLocation == AppConstants.routePrivacyNotice) {
    return null;
  }

  // Ya autenticado intentando ir a login/register → redirigir a su pantalla
  if (onAuth) {
    try {
      final user = await authSvc.getUserById(fbUser.uid);
      // Cuenta deshabilitada por el admin: cerrar sesión y mostrar error
      if (!user.activo) {
        await authSvc.signOut();
        return AppConstants.routeLogin;
      }
      // Conductor particular: verificar aviso de privacidad antes de redirigir
      if (user.rol == UserRole.particular) {
        final privacyVersion =
            user.privacyNoticeVersion ?? 0;
        if (privacyVersion < AppConstants.privacyNoticeCurrentVersion) {
          return AppConstants.routePrivacyNotice;
        }
      }
      return _routeForRole(user.rol);
    } catch (_) {
      return null;
    }
  }

  // Pantalla protegida: verificar que la cuenta siga activa
  try {
    final user = await authSvc.getUserById(fbUser.uid);
    if (!user.activo) {
      await authSvc.signOut();
      return AppConstants.routeLogin;
    }
    // Conductor particular intentando acceder a home sin haber aceptado el aviso
    if (user.rol == UserRole.particular &&
        state.matchedLocation == AppConstants.routeHomeParticular) {
      final privacyVersion = user.privacyNoticeVersion ?? 0;
      if (privacyVersion < AppConstants.privacyNoticeCurrentVersion) {
        return AppConstants.routePrivacyNotice;
      }
    }
  } catch (_) {
    // Si falla la consulta, no interrumpir la navegación
  }

  return null; // Sin redirección
}

String _routeForRole(UserRole rol) {
  switch (rol) {
    case UserRole.particular:
      return AppConstants.routeHomeParticular;
    case UserRole.emergencia:
      return AppConstants.routeEmergency;
    case UserRole.admin:
      return AppConstants.routeAdmin;
  }
}
