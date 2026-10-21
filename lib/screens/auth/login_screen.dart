// lib/screens/auth/login_screen.dart
// Spec §7 Login: fondo blanco, formulario directo sobre el blanco (sin Card),
// ancho máximo 440 dp, campos con borde visible del tema.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _authSvc   = AuthService();

  bool _loading     = false;
  bool _obscurePass = true;
  String? _error;

  // ── Acciones ──────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final user = await _authSvc.loginWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (!mounted) return;

      // TASK-04: bloquear acceso si la cuenta fue deshabilitada por el admin
      if (!user.activo) {
        await _authSvc.signOut();
        setState(() => _error =
            'Tu cuenta está suspendida. Contacta al administrador.');
        return;
      }

      switch (user.rol) {
        case UserRole.particular:
          context.go(AppConstants.routeHomeParticular);
        case UserRole.emergencia:
          context.go(AppConstants.routeEmergency);
        case UserRole.admin:
          context.go(AppConstants.routeAdmin);
      }
    } catch (e) {
      setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String e) {
    if (e.contains('user-not-found') || e.contains('wrong-password'))
      return 'Correo o contraseña incorrectos.';
    if (e.contains('too-many-requests'))
      return 'Demasiados intentos. Intenta más tarde.';
    return 'Error al iniciar sesión. Intenta nuevamente.';
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // Fondo blanco — spec §7
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              // Ancho máximo 440 dp — spec §5
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo de la app desde el SVG de diseño
                  SvgPicture.asset(
                    'assets/images/logo-app.svg',
                    width: 96,
                    height: 96,
                  ),
                  const SizedBox(height: 16),
                  Text('Via Libre: Una ruta libre en cada emergencia',
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium),
                  const SizedBox(height: 40),

                  // Formulario directo sobre fondo blanco — spec §7
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Iniciar sesión', style: tt.titleLarge),
                        const SizedBox(height: 24),

                        // Correo
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Ingresa tu correo';
                            if (!v.contains('@')) return 'Correo inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Contraseña
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Ingresa tu contraseña';
                            if (v.length < 6)
                              return 'Mínimo 6 caracteres';
                            return null;
                          },
                        ),

                        // Bloque de error — fondo errorSoft, texto error del tema
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Icon(Icons.error_outline,
                                  color: cs.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: tt.bodySmall
                                        ?.copyWith(color: cs.error)),
                              ),
                            ]),
                          ),
                        ],

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPassword,
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Botón principal — FilledButton accent (azul)
                        FilledButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent))
                              : const Text('Ingresar'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('¿No tienes cuenta? ', style: tt.bodyMedium),
                    TextButton(
                      onPressed: () =>
                          context.go(AppConstants.routeRegister),
                      child: const Text('Regístrate aquí'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPassword() {
    final emailCtrl =
        TextEditingController(text: _emailCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: 'Correo electrónico'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              try {
                await _authSvc
                    .sendPasswordReset(emailCtrl.text.trim());
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('Correo de recuperación enviado.')));
                }
              } catch (_) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('No se pudo enviar el correo.')));
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
