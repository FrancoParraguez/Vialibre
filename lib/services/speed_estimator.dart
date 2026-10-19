// lib/services/speed_estimator.dart
// Estimación filtrada de velocidad: mediana móvil + EMA, zona muerta,
// respaldo distancia/tiempo cuando Position.speed no es confiable.
//
// Spec: ruta-emergencia-progreso — Task 3

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

  SpeedEstimator({
    this.bufferSize = 5,
    this.emaAlpha   = 0.3,
    this.deadZoneKmh = 2.0,
  });

  final List<double> _buffer = []; // velocidades filtradas en km/h
  SpeedSample? _prevSample;
  double? _emaValue;

  /// Agrega una muestra y devuelve la velocidad estimada en km/h,
  /// o null si no hay dato válido en los últimos 3 s.
  double? addSample(SpeedSample sample) {
    // ── 1. Descartar muestras de mala calidad ─────────────────
    if (sample.accuracyM > 50) return _checkTimeout(sample);

    if (_prevSample != null) {
      final dtSec = sample.timestamp
          .difference(_prevSample!.timestamp)
          .inMilliseconds / 1000.0;

      if (dtSec <= 0 || dtSec > 10) {
        _prevSample = sample;
        return _checkTimeout(sample);
      }

      // Aceleración físicamente imposible > 10 m/s²
      final rawSpeedMs = _rawSpeedMs(sample, _prevSample!, dtSec);
      if (rawSpeedMs != null) {
        final prevSpeedMs = _prevRawSpeedMs(_prevSample!);
        if (prevSpeedMs != null) {
          final accel = (rawSpeedMs - prevSpeedMs).abs() / dtSec;
          if (accel > 10) {
            _prevSample = sample;
            return _checkTimeout(sample);
          }
        }

        // Velocidad absurda > 250 km/h
        if (rawSpeedMs * 3.6 > 250) {
          _prevSample = sample;
          return _checkTimeout(sample);
        }
      }
    }

    // ── 2. Obtener velocidad en km/h ──────────────────────────
    final dtSec = _prevSample == null
        ? null
        : sample.timestamp
                .difference(_prevSample!.timestamp)
                .inMilliseconds /
            1000.0;

    final double? rawMs = _rawSpeedMs(sample, _prevSample, dtSec);
    if (rawMs == null) {
      _prevSample = sample;
      return _checkTimeout(sample);
    }

    double speedKmh = rawMs * 3.6;

    // ── 3. Zona muerta ────────────────────────────────────────
    if (speedKmh < deadZoneKmh) speedKmh = 0.0;

    // ── 4. Buffer + mediana móvil ─────────────────────────────
    _buffer.add(speedKmh);
    if (_buffer.length > bufferSize) _buffer.removeAt(0);

    final median = _median(_buffer);

    // ── 5. EMA ────────────────────────────────────────────────
    if (_emaValue == null || _buffer.length < 2) {
      _emaValue = median;
    } else {
      _emaValue = emaAlpha * median + (1 - emaAlpha) * _emaValue!;
    }

    _prevSample = sample;
    return _emaValue;
  }

  /// Limpia el estado interno (nueva misión).
  void reset() {
    _buffer.clear();
    _prevSample = null;
    _emaValue = null;
  }

  // ── Privado ───────────────────────────────────────────────────

  /// Devuelve null si la última muestra tiene más de 3 s.
  double? _checkTimeout(SpeedSample current) {
    if (_prevSample == null) return null;
    final dt = current.timestamp
        .difference(_prevSample!.timestamp)
        .inMilliseconds / 1000.0;
    return dt > 3.0 ? null : _emaValue;
  }

  /// Velocidad cruda en m/s: prefiere Doppler si es válido,
  /// sino usa distancia/tiempo con Haversine.
  double? _rawSpeedMs(
      SpeedSample s, SpeedSample? prev, double? dtSec) {
    // Doppler válido
    if (s.speedMs >= 0 && s.speedAccuracyMs < 2.0) {
      return s.speedMs;
    }
    // Respaldo distancia/tiempo
    if (prev != null && dtSec != null && dtSec > 0) {
      final dist = _haversine(s.lat, s.lng, prev.lat, prev.lng);
      return dist / dtSec;
    }
    // Solo Doppler sin filtro de precisión si no hay prev
    if (s.speedMs >= 0) return s.speedMs;
    return null;
  }

  double? _prevRawSpeedMs(SpeedSample s) {
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
