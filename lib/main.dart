// lib/main.dart
// Punto de entrada de Vía Libre.
// Inicializa Firebase, configura el router y el tema global.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/particular/home_screen.dart';
import 'screens/emergency/emergency_screen.dart';
import 'screens/admin/admin_screen.dart';

// Opciones generadas por: flutterfire configure
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación fija a vertical (más seguro mientras se conduce)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
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
  ],
);

/// Guarda de navegación: redirige al login si no hay sesión activa,
/// o a la pantalla correcta según el rol si ya está autenticado.
Future<String?> _authGuard(BuildContext context, GoRouterState state) async {
  final authSvc  = AuthService();
  final fbUser   = authSvc.currentUser;
  final onAuth   = [AppConstants.routeLogin, AppConstants.routeRegister]
      .contains(state.matchedLocation);

  // No hay sesión activa → forzar login
  if (fbUser == null) {
    return onAuth ? null : AppConstants.routeLogin;
  }

  // Ya autenticado intentando ir a login/register → redirigir a su pantalla
  if (onAuth) {
    try {
      final user = await authSvc.getUserById(fbUser.uid);
      return _routeForRole(user.rol);
    } catch (_) {
      return null; // Si falla, dejar pasar al login
    }
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
