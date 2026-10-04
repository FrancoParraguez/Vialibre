// lib/widgets/alert_overlay.dart
// Overlay visual hands-free que se muestra cuando el conductor particular
// está dentro del radio de una emergencia activa.

import 'package:flutter/material.dart';
import '../core/constants.dart';

class AlertOverlay extends StatefulWidget {
  /// Si `true`, muestra el overlay de alerta. Si `false`, lo oculta.
  final bool activo;

  /// Distancia en metros al vehículo de emergencia (puede ser null).
  final double? distanciaMetros;

  /// Radio de alerta calculado (puede ser null).
  final double? radioMetros;

  const AlertOverlay({
    super.key,
    required this.activo,
    this.distanciaMetros,
    this.radioMetros,
  });

  @override
  State<AlertOverlay> createState() => _AlertOverlayState();
}

class _AlertOverlayState extends State<AlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: widget.activo ? _buildAlert() : const SizedBox.shrink(),
    );
  }

  Widget _buildAlert() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ScaleTransition(
        scale: _pulseAnim,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(AppColors.accentRed),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(AppColors.accentRed).withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.emergency, color: Colors.white, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🚨 EMERGENCIA CERCANA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitulo(),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitulo() {
    if (widget.distanciaMetros != null) {
      final dist = widget.distanciaMetros!.toStringAsFixed(0);
      return 'Vehículo de emergencia a ~$dist m. Cede el paso.';
    }
    return 'Vehículo de emergencia en tu zona. Cede el paso.';
  }
}
