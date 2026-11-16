// lib/services/speed_estimator.dart
// Estimación filtrada de velocidad: mediana móvil + EMA, zona muerta,
// respaldo distancia/tiempo cuando Position.speed no es confiable.
//
// Diseñado para ser preciso a baja velocidad: sin "congelar" el último
// valor alto cuando dejan de llegar muestras.

import 'dart:math' as math;

// ── Muestra de velocidad ───────────────────────────────────────────
class SpeedSample {
  final DateTime timestamp;

  /// Velocidad Doppler del GPS en m/s. -1 si el dispositivo no la reporta.
  final double speedMs;

  /// Precisión de la velocidad en m/s (0 si no disponible).
  final double speedAccuracyMs;

  /// Precisión horizontal en metros.
  final double accuracyM;

  final double lat;
  final double lng;

  const SpeedSample({
    required this.timestamp,
    required this.speedMs,
    required this.speedAccuracyMs,
    required this.accuracyM,
    required this.lat,
    required this.lng,
  });
}

// ── Estimador ─────────────────────────────────────────────────────
class SpeedEstimator {
  /// Tamaño del buffer de mediana móvil.
  final int bufferSize;

  /// Alpha para EMA (0 < alpha ≤ 1). Más bajo = más suave.
  final double emaAlpha;

  /// Zona muerta: por debajo de este umbral (km/h) se reporta 0.
  final double deadZoneKmh;

  /// Segundos sin muestra válida tras los cuales se reporta 0.
  final double staleSeconds;

  SpeedEstimator({
    this.bufferSize = 3,
    this.emaAlpha = 0.5,
    this.deadZoneKmh = 1.5,
    this.staleSeconds = 3.0,
  });

  final List<double> _buffer = []; // velocidades en km/h
  SpeedSample? _prevSample;
  DateTime? _lastValidAt;
  double? _emaValue;

  /// Agrega una muestra y devuelve la velocidad estimada en km/h.
  /// Si no hay datos válidos recientes devuelve 0 (nunca un valor viejo).
  double addSample(SpeedSample sample) {
    final prev = _prevSample;

    // Sin datos válidos recientes → reiniciar y reportar 0
    if (_lastValidAt != null &&
        sample.timestamp.difference(_lastValidAt!).inMilliseconds / 1000.0 >
            staleSeconds) {
      _buffer.clear();
      _emaValue = null;
    }

    // 1. Descartar muestras de mala calidad
    if (sample.accuracyM > 50) {
      return _emaValue ?? 0.0;
    }

    final dtSec = prev == null
        ? null
        : sample.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dtSec != null && dtSec <= 0) {
      return _emaValue ?? 0.0;
    }

    // 2. Velocidad cruda
    final rawMs = _rawSpeedMs(sample, prev, dtSec);
    _prevSample = sample;
    if (rawMs == null) return _emaValue ?? 0.0;

    double speedKmh = rawMs * 3.6;
    if (speedKmh > 250) return _emaValue ?? 0.0; // absurdo

    // 3. Zona muerta (umbral fijo o ruido del propio Doppler)
    final noiseKmh = sample.speedAccuracyMs > 0 ? sample.speedAccuracyMs * 3.6 : 0.0;
    if (speedKmh < deadZoneKmh || speedKmh < noiseKmh * 0.5) speedKmh = 0.0;

    // 4. Mediana móvil
    _buffer.add(speedKmh);
    if (_buffer.length > bufferSize) _buffer.removeAt(0);
    final median = _median(_buffer);

    // 5. EMA; si frena fuerte (>50 %) o se detiene, seguir la mediana al instante
    final ema = _emaValue;
    if (ema == null || median == 0.0 || median < ema * 0.5) {
      _emaValue = median;
    } else {
      _emaValue = emaAlpha * median + (1 - emaAlpha) * ema;
    }

    _lastValidAt = sample.timestamp;
    return _emaValue!;
  }

  /// Limpia el estado interno (nueva misión).
  void reset() {
    _buffer.clear();
    _prevSample = null;
    _lastValidAt = null;
    _emaValue = null;
  }

  // ── Privado ───────────────────────────────────────────────────

  /// Velocidad cruda en m/s: prefiere Doppler si es válido,
  /// sino usa distancia/tiempo con Haversine.
  double? _rawSpeedMs(SpeedSample s, SpeedSample? prev, double? dtSec) {
    if (s.speedMs >= 0 && (s.speedAccuracyMs <= 0 || s.speedAccuracyMs < 2.0)) {
      return s.speedMs;
    }
    if (prev != null && dtSec != null && dtSec > 0) {
      final dist = _haversine(s.lat, s.lng, prev.lat, prev.lng);
      return dist / dtSec;
    }
    if (s.speedMs >= 0) return s.speedMs;
    return null;
  }

  /// Mediana de una lista (no vacía).
  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Haversine en metros.
  static double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
