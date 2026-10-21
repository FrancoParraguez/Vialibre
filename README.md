# Vía Libre 

Plataforma movil de geolocalización en tiempo real con **geofencing predictivo** para optimizar los tiempos de respuesta de vehículos de emergencia (ambulancias, bomberos, carabineros) en entornos urbanos.

---

## ¿Qué es Vía Libre?

Vía Libre es una aplicación móvil y web desarrollada en Flutter que conecta a conductores particulares con vehículos de emergencia en tránsito. Cuando una ambulancia o carro de bomberos activa una alerta preventiva, el sistema calcula en tiempo real un radio de alerta dinámico basado en la velocidad del vehículo de emergencia y la del conductor particular. Si el conductor particular se encuentra dentro de ese radio, recibe una alerta inmediata para que ceda el paso anticipadamente.

El objetivo es reducir los tiempos de respuesta eliminando la reacción tardía al escuchar una sirena, dándole al conductor unos segundos de anticipación para reaccionar de forma segura.

---

## Funcionalidades

### Conductor particular
- Visualización del mapa en tiempo real con su posición actual
- Recepción de alertas cuando un vehículo de emergencia entra en su radio de proximidad
- Overlay de alerta con información del vehículo (tipo, distancia aproximada)

### Conductor de emergencia
- Transmisión de ubicación en tiempo real al trazar una ruta de emergencia
- El radio de alerta se ajusta automáticamente según la velocidad del vehículo

### Panel de administración (web)
- Gestión de flota: agregar, activar/desactivar y eliminar vehículos por institución
- Gestión de conductores: crear cuentas de conductores de emergencia directamente desde el panel sin afectar la sesión del administrador
- Asignación de conductor a vehículo con selector visual
- Toda la información se actualiza en tiempo real via Firestore

---


### Stack tecnológico

| Capa | Tecnología |
|---|---|
| Framework | Flutter 3 (Dart 3) |
| Autenticación | Firebase Auth |
| Base de datos principal | Cloud Firestore |
| Base de datos en tiempo real | Firebase Realtime Database |
| Mensajería push | Firebase Cloud Messaging (FCM) |
| Mapas | Google Maps Flutter |
| Geolocalización | Geolocator |
| Navegación | GoRouter |
| Estado | Provider |

---

## Motor de Geofencing Predictivo

El corazón de Vía Libre es su algoritmo de geofencing dinámico. A diferencia de un geofence estático (círculo fijo), el radio de alerta se recalcula continuamente según las velocidades de ambos vehículos.

**Fórmula:**
```
d = T × ((Ve - Vc) / 3.6)
```

Donde:
- `d` = radio de alerta en metros
- `T` = tiempo de anticipación (30 segundos por defecto)
- `Ve` = velocidad del vehículo de emergencia en km/h
- `Vc` = velocidad del conductor particular en km/h

**Ejemplo:** si la ambulancia va a 80 km/h y el particular a 40 km/h, el radio de alerta es `30 × (40 / 3.6) ≈ 333 metros`. El conductor recibirá la alerta cuando la ambulancia se encuentre a 333 metros o menos.

La distancia entre los dos vehículos se calcula con la **fórmula de Haversine**, que mide distancias exactas sobre la superficie terrestre considerando su curvatura.

---

## Roles de usuario

| Rol | Acceso | Registro |
|---|---|---|
| `particular` | App móvil — pantalla de mapa y alertas | Autoregistro desde la app |
| `emergencia` | App móvil — pantalla de mapa de ruta emergencia y transmisión | Creado por el administrador desde el panel web |
| `admin` | Panel web — gestión de flota y conductores | Creado manualmente en Firestore |

---

## Firebase — Estructura de datos

### Firestore Collections

**`users`**
```json
{
  "uid": "string",
  "nombre": "string",
  "email": "string",
  "rol": "particular | emergencia | admin",
  "institucion_id": "string | null",
  "activo": true,
  "created_at": "ISO8601"
}
```

**`vehicles`**
```json
{
  "id": "string",
  "patente": "string",
  "tipo": "ambulancia | bomberos | carabineros | otro",
  "institucion_id": "string",
  "institucion_nombre": "string",
  "conductor_asignado_uid": "string | null",
  "activo": true,
  "created_at": "ISO8601"
}
```

**`emergencies`**
```json
{
  "id": "string",
  "vehicle_id": "string",
  "conductor_uid": "string",
  "estado": "activa | inactiva",
  "conductores_alertados": 0,
  "timestamp_inicio": "ISO8601",
  "timestamp_fin": "ISO8601 | null"
}
```

### Realtime Database Paths

```
active_emergencies/
  {conductor_uid}/
    emergency_id: "string"
    timestamp: "ISO8601"

active_locations/
  {conductor_uid}/
    lat: number
    lng: number
    speed_kmh: number
    timestamp: "ISO8601"
```

### Índices compuestos requeridos en Firestore

| Colección | Campo 1 | Campo 2 |
|---|---|---|
| `users` | `rol` ASC | `institucion_id` ASC |
| `vehicles` | `institucion_id` ASC | — |

---

## Configuración inicial

### Prerrequisitos
- Flutter SDK `>=3.0.0`
- Proyecto en Firebase con Firestore, Auth y Realtime Database habilitados
- Google Maps API Key con facturación habilitada en Google Cloud

### Instalación

```bash
flutter run -d chrome   # Web (panel admin)
flutter run             # Android/iOS (app conductores)
```


## Flujo operativo

```
Admin (web)
  └── Crea vehículos de la institución
  └── Crea conductores de emergencia (nombre, email, contraseña)
  └── Asigna conductor ↔ vehículo

Conductor de emergencia (app móvil)
  └── Inicia sesión con credenciales creadas por el admin
  └── Transmite ubicación GPS en tiempo real → Firebase RTDB

Motor de Geofencing (corre en app de conductores particulares)
  └── Escucha active_emergencies en RTDB
  └── Por cada emergencia activa, calcula distancia y radio
  └── Si conductor entra al radio → dispara alerta local

Conductor particular (app móvil)
  └── Recibe overlay de alerta con instrucción de ceder el paso
  └── La alerta desaparece cuando el vehículo se aleja
```

---

## Licencia

Proyecto académico Capstone Ingeniria Informatica —  DUOC UC Valparaiso.
