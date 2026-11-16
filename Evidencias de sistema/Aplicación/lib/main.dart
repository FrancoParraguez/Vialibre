// lib/main.dart
// Punto de entrada de Vía Libre.
// Inicializa Firebase, configura el router y el tema global.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/user_profile_repository.dart';
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
        themeMode: ThemeMode.light,   // light-first: nunca ThemeMode.system
        routerConfig: _router,
      ),
    );
  }
}

// ── Router ────────────────────────────────────────────────────────
final GoRouter _router = GoRouter(
  initialLocation: AppConstants.routeHomeParticular,
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

/// Guarda de navegación:
/// - Permite acceso directo al mapa particular (sin inicio de sesión obligatorio).
/// - Redirige al aviso de privacidad si aún no fue aceptado (local o en Firestore).
/// - Protege estrictamente `/emergency` y `/admin` verificando cuenta activa y rol.
/// - Redirige automáticamente a `/emergency` o `/admin` si hay sesión institucional activa.
Future<String?> _authGuard(BuildContext context, GoRouterState state) async {
  final authSvc = AuthService();
  final profileRepo = UserProfileRepository();
  final loc = state.matchedLocation;

  final onAuth = [AppConstants.routeLogin, AppConstants.routeRegister]
      .contains(loc);
  final onProtected = [AppConstants.routeEmergency, AppConstants.routeAdmin]
      .contains(loc);

  // ── Caso 1: Usuario sin cuenta iniciada (invitado / anónimo) ──
  if (!authSvc.isRegisteredUser) {
    // Bloquear acceso no autorizado a rutas institucionales
    if (onProtected) {
      return AppConstants.routeLogin;
    }

    // Permitir login, registro y aviso de privacidad libremente
    if (onAuth || loc == AppConstants.routePrivacyNotice) {
      return null;
    }

    // En /home, verificar aceptación local del aviso de privacidad
    if (loc == AppConstants.routeHomeParticular) {
      final localVersion = await profileRepo.getLocalPrivacyNoticeVersion();
      if (localVersion < AppConstants.privacyNoticeCurrentVersion) {
        return AppConstants.routePrivacyNotice;
      }
    }

    return null;
  }

  // ── Caso 2: Usuario con cuenta autenticada ────────────────────
  final fbUser = authSvc.currentUser!;
  try {
    final user = await authSvc.getUserById(fbUser.uid);

    // TASK-04: Cuenta deshabilitada por el admin → cerrar sesión y enviar a login
    if (!user.activo) {
      await authSvc.signOut();
      return AppConstants.routeLogin;
    }

    // Servicios de emergencia y Administradores: acceso directo y aislamiento por rol
    if (user.rol == UserRole.emergencia || user.rol == UserRole.admin) {
      final targetRoute = _routeForRole(user.rol);
      if (loc != targetRoute) {
        return targetRoute;
      }
      return null;
    }

    // Conductor particular con cuenta iniciada:
    // Bloquear acceso a pantallas de emergencia o administración
    if (onProtected) {
      return AppConstants.routeHomeParticular;
    }

    if (loc == AppConstants.routePrivacyNotice) {
      return null;
    }

    final localVersion = await profileRepo.getLocalPrivacyNoticeVersion();
    final remoteVersion = user.privacyNoticeVersion ?? 0;
    final effectiveVersion =
        remoteVersion > localVersion ? remoteVersion : localVersion;

    if (effectiveVersion < AppConstants.privacyNoticeCurrentVersion) {
      return AppConstants.routePrivacyNotice;
    }

    if (onAuth) {
      return AppConstants.routeHomeParticular;
    }
  } catch (_) {
    // Si falla la lectura de perfil en una ruta protegida, exigir login
    if (onProtected) {
      return AppConstants.routeLogin;
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
