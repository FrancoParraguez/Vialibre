// lib/screens/auth/register_screen.dart
// Spec §7 Login: fondo blanco, Card con borde del tema, campos del inputDecorationTheme.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _pass2Ctrl  = TextEditingController();
  final _authSvc    = AuthService();

  // Registro público: solo conductores particulares.
  // Conductores de emergencia los crea el admin desde el panel web.
  final UserRole _rolSeleccionado = UserRole.particular;
  bool _loading     = false;
  bool _obscurePass = true;
  String? _error;

  // ── Acciones ──────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await _authSvc.registerWithEmail(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text,
        nombre:   _nombreCtrl.text.trim(),
        rol:      _rolSeleccionado,
      );
      if (!mounted) return;
      context.go(AppConstants.routeHomeParticular);
    } catch (e) {
      setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String e) {
    if (e.contains('email-already-in-use'))
      return 'El correo ya está registrado.';
    if (e.contains('weak-password'))
      return 'La contraseña es muy débil.';
    return 'Error al registrar. Intenta nuevamente.';
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeLogin),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Crear cuenta', style: tt.titleLarge),
                        const SizedBox(height: 4),
                        Text('Regístrate como conductor particular.',
                            style: tt.bodyMedium),
                        const SizedBox(height: 24),

                        // Nombre
                        TextFormField(
                          controller: _nombreCtrl,
                          textCapitalization:
                              TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon:
                                Icon(Icons.person_outline),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Ingresa tu nombre'
                                  : null,
                        ),
                        const SizedBox(height: 16),

                        // Correo
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType:
                              TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            prefixIcon:
                                Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Ingresa tu correo';
                            if (!v.contains('@'))
                              return 'Correo inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Contraseña
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon:
                                const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() =>
                                  _obscurePass = !_obscurePass),
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
                        const SizedBox(height: 16),

                        // Confirmar contraseña
                        TextFormField(
                          controller: _pass2Ctrl,
                          obscureText: _obscurePass,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _register(),
                          decoration: const InputDecoration(
                            labelText: 'Confirmar contraseña',
                            prefixIcon:
                                Icon(Icons.lock_outline),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty)
                                  ? 'Confirma tu contraseña'
                                  : null,
                        ),

                        // Bloque de error — fondo errorContainer, texto error del tema
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Icon(Icons.error_outline,
                                  color: cs.error,
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: tt.bodySmall
                                        ?.copyWith(color: cs.error)),
                              ),
                            ]),
                          ),
                        ],

                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading ? null : _register,
                          child: _loading
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent))
                              : const Text('Crear cuenta'),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: () => context
                                .go(AppConstants.routeLogin),
                            child: const Text(
                                'Ya tengo cuenta → Ingresar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }
}
