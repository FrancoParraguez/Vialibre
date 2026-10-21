// lib/services/date_provider.dart
// Proveedor de fecha que se actualiza automáticamente a medianoche
// sin recargar la página (temporizador hasta el siguiente día).
//
// Spec: web-admin-corporativo — Task 2.4

import 'dart:async';
import 'package:flutter/foundation.dart';

class DateProvider extends ChangeNotifier {
  DateTime _today;
  Timer?   _timer;

  DateProvider() : _today = DateTime.now() {
    _scheduleNextMidnight();
  }

  DateTime get today => _today;

  void _scheduleNextMidnight() {
    _timer?.cancel();
    final now  = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1); // medianoche
    final diff = next.difference(now);

    _timer = Timer(diff, () {
      _today = DateTime.now();
      notifyListeners();
      _scheduleNextMidnight(); // re-programar para la siguiente medianoche
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
