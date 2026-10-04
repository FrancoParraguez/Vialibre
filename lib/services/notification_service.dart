// lib/services/notification_service.dart
// Gestiona notificaciones push (FCM) y notificaciones locales para alertas hands-free.

import 'package:flutter/painting.dart' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

// Handler para mensajes en background (debe ser top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase se inicializa automáticamente en el isolate de background
}

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _alertChannelId = 'via_libre_alerts';
  static const _alertChannelName = 'Alertas de Emergencia';

  // ── Inicialización ────────────────────────────────────────────
  Future<void> initialize() async {
    // Permisos FCM (web los gestiona el navegador vía getToken)
    if (!kIsWeb) {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
    }

    // Canal Android de alta prioridad
    if (!kIsWeb) {
      const androidChannel = AndroidNotificationChannel(
        _alertChannelId,
        _alertChannelName,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      // Inicializar plugin local (no soportado en web)
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      );
      await _localNotifications.initialize(initSettings);
    }

    // Handler para mensajes en background
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Mensaje recibido en foreground → mostrar notificación local
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  // ── Token FCM ─────────────────────────────────────────────────
  Future<String?> getToken() async {
    if (kIsWeb) {
      // En web se requiere el VAPID key configurado en Firebase Console
      return _fcm.getToken(
        vapidKey:
            'TU_VAPID_KEY_AQUI', // reemplaza con tu clave pública VAPID
      );
    }
    return _fcm.getToken();
  }

  /// Guarda el token FCM del usuario en Firestore para que el backend
  /// pueda enviarle notificaciones push dirigidas.
  Future<void> saveTokenToFirestore(String userId) async {
    final token = await getToken();
    if (token == null) return;

    await _firestore
        .collection(AppConstants.colUsers)
        .doc(userId)
        .update({'fcm_token': token});

    // Renovar token automáticamente cuando Firebase lo refresque
    _fcm.onTokenRefresh.listen((newToken) {
      _firestore
          .collection(AppConstants.colUsers)
          .doc(userId)
          .update({'fcm_token': newToken});
    });
  }

  // ── Mostrar alerta local de emergencia (hands-free) ───────────
  /// Muestra una notificación de máxima prioridad cuando el conductor
  /// entra en el radio de un vehículo de emergencia.
  Future<void> mostrarAlertaEmergencia({
    required String titulo,
    required String cuerpo,
  }) async {
    // En web, flutter_local_notifications no está soportado.
    // FCM en web ya muestra la notificación del sistema automáticamente
    // cuando llega un mensaje con bloque `notification`.
    if (kIsWeb) return;

    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        _alertChannelName,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true, // muestra en pantalla aunque esté bloqueada
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFD32F2F), // rojo emergencia
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    );

    await _localNotifications.show(
      0,
      titulo,
      cuerpo,
      notificationDetails,
    );
  }

  Future<void> cancelarAlertas() async {
    if (kIsWeb) return;
    await _localNotifications.cancelAll();
  }

  // ── Handler foreground ────────────────────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    mostrarAlertaEmergencia(
      titulo: notification.title ?? '🚨 Vía Libre',
      cuerpo: notification.body ?? 'Vehículo de emergencia cercano',
    );
  }
}