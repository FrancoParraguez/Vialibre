// lib/widgets/alert_overlay.dart
// Overlay visual hands-free — conductor particular.
// Se muestra cuando entra en el radio de un vehículo de emergencia activo.
//
// Reglas del spec "Horizonte" (colors.md):
//  • Amarillo (#FFC400) para fase anticipación (≥ 30-45 s). Texto: #101C2B (nunca blanco).
//  • Bermellón (#F0322A) para fase crítica (radio inminente). Texto: blanco.
//  • Halo pulsante: color con alpha 0.35 — NO animar todo el fondo.
//  • Ícono mínimo 64 dp, texto mínimo 28 sp en negrita.
//  • Incluye ícono + texto (accesibilidad daltonismo).

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AlertOverlay extends StatefulWidget {
  /// Si `true`, muestra el overlay de alerta. Si `false`, lo oculta.
  final bool activo;

  /// Nivel de alerta según la distancia al vehículo.
  final AlertLevel nivel;

  /// Distancia en metros al vehículo de emergencia (puede ser null).
  final double? distanciaMetros;

  /// Radio de alerta calculado (puede ser null).
  final double? radioMetros;

  /// Dirección del vehículo (por ejemplo "por la izquierda"). Opcional.
  final String? direccion;

  const AlertOverlay({
    super.key,
    required this.activo,
    this.nivel = AlertLevel.anticipation,
    this.distanciaMetros,
    this.radioMetros,
    this.direccion,
  });

  @override
  State<AlertOverlay> createState() => _AlertOverlayState();
}

class _AlertOverlayState extends State<AlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _haloCtrl;
  late final Animation<double> _haloRadius;
  late final Animation<double> _haloOpacity;

  @override
  void initState() {
    super.initState();

    // Halo: 900 ms, repetición continua — spec: 800-1000 ms
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _haloRadius = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _haloCtrl, curve: Curves.easeOut),
    );

    _haloOpacity = Tween<double>(begin: 0.35, end: 0.0).animate(
      CurvedAnimation(parent: _haloCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _haloCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: widget.activo
          ? _buildBanner(key: const ValueKey('alert'))
          : const SizedBox.shrink(key: ValueKey('empty')),
    );
  }

  Widget _buildBanner({required Key key}) {
    final level      = widget.nivel;
    final bgColor    = level.color;
    final fgColor    = level.onColor;
    final haloColor  = bgColor.withValues(alpha: 0.35);

    return Positioned(
      key: key,
      top: 0,
      left: 0,
      right: 0,
      child: Semantics(
        label: '${level.label}. ${_subtitulo()}',
        liveRegion: true,
        child: AnimatedBuilder(
          animation: _haloCtrl,
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                // Halo pulsante como sombra exterior (spec: no animar fondo completo)
                boxShadow: [
                  BoxShadow(
                    color: haloColor.withValues(alpha: _haloOpacity.value),
                    blurRadius: 24 + 24 * _haloRadius.value,
                    spreadRadius: 4 + 8 * _haloRadius.value,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ícono grande (mín. 64 dp del spec)
                Icon(level.icon, color: fgColor, size: 64),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Título: mínimo 28 sp en negrita
                      Text(
                        level.label.toUpperCase(),
                        style: TextStyle(
                          color: fgColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitulo(),
                        style: TextStyle(
                          color: fgColor.withValues(alpha: 0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitulo() {
    final parts = <String>[];

    if (widget.distanciaMetros != null) {
      final dist = widget.distanciaMetros!.toStringAsFixed(0);
      parts.add('~$dist m');
    }
    if (widget.direccion != null) {
      parts.add(widget.direccion!);
    }

    if (parts.isNotEmpty) {
      return 'Vehículo de emergencia ${parts.join(' — ')}. Cede el paso.';
    }
    return 'Vehículo de emergencia en tu zona. Cede el paso.';
  }
}
