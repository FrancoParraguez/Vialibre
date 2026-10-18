// Modelo de estado de preparación del conductor particular.
// Requisito R3.1 del spec alerta-proximidad-particular.

enum ItemStatus {
  ok,          // activo y funcionando
  missing,     // falta acción del usuario
  unavailable, // no disponible en esta plataforma
}

class ReadinessState {
  final ItemStatus locationRealtime;
  final ItemStatus backgroundExec;
  final ItemStatus notifications;

  const ReadinessState({
    required this.locationRealtime,
    required this.backgroundExec,
    required this.notifications,
  });

  bool get isReady =>
      locationRealtime == ItemStatus.ok &&
      backgroundExec == ItemStatus.ok &&
      notifications == ItemStatus.ok;

  // Estado inicial conservador
  static const ReadinessState unknown = ReadinessState(
    locationRealtime: ItemStatus.missing,
    backgroundExec: ItemStatus.missing,
    notifications: ItemStatus.missing,
  );

  ReadinessState copyWith({
    ItemStatus? locationRealtime,
    ItemStatus? backgroundExec,
    ItemStatus? notifications,
  }) {
    return ReadinessState(
      locationRealtime: locationRealtime ?? this.locationRealtime,
      backgroundExec: backgroundExec ?? this.backgroundExec,
      notifications: notifications ?? this.notifications,
    );
  }
}
