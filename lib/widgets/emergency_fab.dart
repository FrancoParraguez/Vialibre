// lib/widgets/emergency_fab.dart
// Botón de acción flotante para activar/desactivar el modo emergencia.
// Diseñado para ser grande, accesible y operable con una sola mano.

import 'package:flutter/material.dart';
import '../core/constants.dart';

class EmergencyFab extends StatefulWidget {
  final bool activo;
  final VoidCallback onPressed;

  const EmergencyFab({
    super.key,
    required this.activo,
    required this.onPressed,
  });

  @override
  State<EmergencyFab> createState() => _EmergencyFabState();
}

class _EmergencyFabState extends State<EmergencyFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(EmergencyFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activo) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.activo
        ? const Color(AppColors.accentRed)
        : const Color(AppColors.primaryBlue);

    final label = widget.activo ? 'DESACTIVAR' : 'ACTIVAR\nEMERGENCIA';
    final icon  = widget.activo ? Icons.emergency_share : Icons.emergency_share_outlined;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: widget.activo ? 24 : 12,
                spreadRadius: widget.activo ? 6 : 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
