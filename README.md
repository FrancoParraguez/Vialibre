# Vía Libre 

Plataforma movil de geolocalización en tiempo real con **geofencing predictivo** para optimizar los tiempos de respuesta de vehículos de emergencia (ambulancias, bomberos, carabineros) en entornos urbanos.

---

## ¿Qué es Vía Libre?

Vía Libre es una aplicación móvil y web desarrollada en Flutter que conecta a conductores particulares con vehículos de emergencia en tránsito. Cuando una ambulancia o carro de bomberos activa una alerta preventiva, el sistema calcula en tiempo real un radio de alerta dinámico basado en la velocidad del vehículo de emergencia y la del conductor particular. Si el conductor particular se encuentra dentro de ese radio, recibe una alerta inmediata para que ceda el paso anticipadamente.

El objetivo es reducir los tiempos de respuesta eliminando la reacción tardía al escuchar una sirena, dándole al conductor unos segundos de anticipación para reaccionar de forma segura.

---
## Innovación y Diferenciación frente a Waze

A diferencia de plataformas como **Waze**, cuyo diseño se centra en la navegación GPS general y depende de reportes comunitarios estáticos ingresados manualmente por los usuarios, **Vía Libre** propone un paradigma automatizado y especializado en la seguridad vial y la respuesta crítica ante emergencias[cite: 4]. En plataformas colaborativas tradicionales, un vehículo de emergencia en desplazamiento rara vez logra ser reportado con oportunidad debido a su alta velocidad y continuo cambio de ubicación, lo que deja al conductor particular expuesto únicamente a las sirenas y balizas físicas cuando la unidad ya se encuentra a escasos metros[cite: 4]. En contraste, Vía Libre elimina la dependencia de terceros al conectar directamente la fuente de la emergencia con la ciudadanía: el conductor de la unidad (SAMU, Bomberos o Carabineros) activa una baliza digital que transmite su telemetría GPS segundo a segundo (1 Hz), automatizando por completo la detección y el aviso preventivo en ruta[cite: 3, 4].

La principal innovación tecnológica de la plataforma radica en su motor de **geofencing predictivo dinámico**, que supera los límites de los radios de proximidad fijos empleados por los mapas convencionales[cite: 4]. En lugar de utilizar una distancia estática, Vía Libre recalcula cada segundo un radio de alerta personalizado en función de las velocidades relativas de ambos vehículos ($d = T \times \frac{V_e - V_c}{3.6}$) combinado con la distancia geodésica de Haversine[cite: 3, 4]. Esta arquitectura matemática garantiza una ventana de anticipación constante de **30 segundos** antes del cruce, disparando notificaciones push de máxima prioridad capaces de interrumpir incluso en segundo plano y desplegando un *overlay* visual de alto contraste que desaparece automáticamente con margen de histéresis una vez que la unidad se aleja, evitando distracciones innecesarias al volante[cite: 3, 4].

Finalmente, mientras Waze opera exclusivamente como una aplicación de consumo masivo sin vínculo formal con los organismos de urgencia, Vía Libre incorpora una capa de **gestión y trazabilidad institucional** a través de un panel web administrativo dedicado[cite: 3, 4]. Desde esta interfaz, las instituciones pueden administrar su flota vehicular, asignar conductores autorizados mediante control de acceso basado en roles y auditar métricas operativas en tiempo real —como la cantidad de conductores alertados por evento y el registro histórico de emergencias—, posicionando a la plataforma como una herramienta integral de coordinación ciudadana e institucional[cite: 3, 4].

##  Requerimientos del Sistema

### Requerimientos Funcionales (RF)

| Código | Requerimiento | Descripción | Actor / Rol |
| :--- | :--- | :--- | :--- |
| **RF-01** | **Registro e inicio de sesión** | Permite a conductores particulares crear una cuenta e iniciar sesión desde la app móvil. Conductores de emergencia y administradores ingresan con credenciales creadas por su institución (sin autoregistro). | Todos |
| **RF-02** | **Autenticación por rol** | Identifica el perfil del usuario al iniciar sesión (`particular`, `emergencia`, `administrador`) y lo redirige a su interfaz correspondiente, aislando permisos. | Todos |
| **RF-03** | **Mapa en tiempo real** | Muestra la ubicación actual del conductor particular sobre un mapa actualizado en tiempo real como interfaz principal de alertas. | Conductor particular |
| **RF-04** | **Activación de emergencia** | Permite iniciar y finalizar una sesión de emergencia. Al activarla transmite GPS en vivo; al desactivarla detiene el envío y purga los datos temporales. | Conductor emergencia |
| **RF-05** | **Transmisión de telemetría** | Envía de forma continua la posición GPS, velocidad y dirección del vehículo mientras la emergencia permanece activa. | Conductor emergencia |
| **RF-06** | **Radio de alerta dinámico** | Calcula y recalcula en tiempo real el perímetro crítico de proximidad considerando la velocidad del vehículo de emergencia y la del conductor particular. | Sistema |
| **RF-07** | **Emisión de alerta** | Dispara una notificación inmediata (tipo de vehículo y distancia aproximada) al ingresar al radio crítico, operando incluso con la app en segundo plano o pantalla bloqueada. | Sistema / Particular |
| **RF-08** | **Cierre automático de alerta** | Oculta automáticamente la notificación cuando el vehículo de emergencia se aleja y sale del radio crítico, sin requerir interacción manual. | Sistema / Particular |
| **RF-09** | **Gestión de flota institucional** | Permite agregar, activar, desactivar y eliminar vehículos de la institución desde el panel web (especificando tipo y patente). | Administrador |
| **RF-10** | **Gestión de conductores** | Permite crear cuentas para conductores de emergencia vinculadas a la institución desde el panel web sin cerrar la sesión administrativa activa. | Administrador |
| **RF-11** | **Asignación conductor–vehículo** | Permite vincular un conductor a un vehículo específico de la flota institucional (relación 1 a 1 por vehículo activo). | Administrador |

---

### Requerimientos No Funcionales (RNF)

| Código | Atributo | Criterio de Aceptación y Especificación |
| :--- | :--- | :--- |
| **RNF-01** | **Rendimiento** | El sistema debe calcular y emitir la alerta al conductor particular en un tiempo máximo de **2 segundos** desde que el vehículo de emergencia ingresa al radio crítico. |
| **RNF-02** | **Disponibilidad** | Operatividad mínima del **99,5% mensual**, con manejo de estado local y reconexión automática ante pérdida de conectividad para evitar la pérdida silenciosa de alertas. |
| **RNF-03** | **Seguridad y privacidad** | Control de acceso estricto basado en roles (RBAC), aislamiento de datos institucionales y eliminación inmediata de datos de geolocalización al finalizar la emergencia. |
| **RNF-04** | **Escalabilidad** | Arquitectura serverless capaz de soportar la incorporación de nuevas flotas, instituciones y ciudades sin requerir rediseño estructural. |
| **RNF-05** | **Usabilidad** | Interfaz de alerta de alto contraste y lectura rápida, comprensible y accionable en **menos de 3 segundos** sin requerir interacción táctil durante la conducción. |
| **RNF-06** | **Compatibilidad** | Operación garantizada en condiciones reales de uso (dispositivo bloqueado, pantalla apagada y app en segundo plano) cubriendo los dispositivos móviles más utilizados en Chile. |
| **RNF-07** | **Confiabilidad** | Comportamiento consistente y predecible en los cálculos de distancia esférica y radio dinámico bajo cualquier escenario de velocidad, dirección o densidad vehicular. |
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

## Metodología de Desarrollo

El proyecto utiliza **Scrum** como marco de trabajo ágil, organizado en **3 sprints de 2 semanas** con ceremonias formales: **Sprint Planning**, **Daily Scrum**, **Sprint Review** y **Sprint Retrospective**.

### Justificación del Marco de Trabajo
Se seleccionó Scrum debido a que el motor de *geofencing* predictivo exigió ciclos continuos de ajuste empírico —calibración de umbrales de velocidad, márgenes de alerta y latencia de notificaciones—, donde la retroalimentación temprana al cierre de cada iteración permitió corregir desviaciones con rapidez. Asimismo, la estructura de un equipo de **2 desarrolladores** y un horizonte de **12 semanas** favoreció la adaptabilidad de un marco ligero frente a procesos tradicionales más rígidos.

El seguimiento operativo diario se complementó con un tablero **Kanban de 4 columnas** (`Por hacer` → `En progreso` → `En revisión` → `Terminado`), garantizando trazabilidad y visibilidad continua sobre el estado de cada tarea dentro del sprint activo.

### Artefactos Generados

* **Product Vision:** Define la problemática central (conductores particulares que no reciben anticipación suficiente para ceder el paso), el segmento de usuarios objetivo, el alcance funcional de la versión `v1.0` y los criterios de éxito medibles, destacando una **latencia de notificación inferior a 2 segundos** y un **tiempo de anticipación promedio de al menos 25 segundos**.
* **Product Backlog:** Compuesto por **15 historias de usuario** estructuradas en **8 épicas** (*Autenticación, Geofencing, Interfaz Conductor Particular, Interfaz Conductor Emergencia, Panel Admin, Notificaciones, Infraestructura Firebase y Calidad*). Cada historia incorpora criterios de aceptación bajo formato *Given-When-Then* y estimación mediante *story points* en escala Fibonacci, totalizando **62 puntos**.
* **Sprint Backlog y Definition of Done (DoD):** Desglosa las tareas técnicas de cada iteración con responsable asignado, estimación en horas y estado de avance. La *Definition of Done* exige el cumplimiento estricto de cuatro condiciones para cerrar una historia:
  1. Código fuente limpio y libre de *warnings*.
  2. Pruebas unitarias ejecutadas y aprobadas.
  3. *Pull Request* revisado y aprobado por el otro integrante del equipo.
  4. Verificación funcional manual en dispositivo físico.
* **Retrospectivas:** Documentan las métricas de cierre y los acuerdos de mejora continua adoptados al finalizar cada sprint, abordando aspectos de comunicación interna, precisión en las estimaciones y cobertura de pruebas.
---

### 1. Especificación y Estimación de Requerimientos

* **Formulación de Requerimientos**: Cada funcionalidad se documenta como una historia de usuario estructurada bajo la sintaxis de Desarrollo Guiado por el Comportamiento (*Dado que*, *Cuando*, *Entonces*), lo que garantiza criterios de aceptación verificables tanto a nivel de código como en pruebas de campo.
* **Puntos de Esfuerzo**: La complejidad de cada requerimiento se estima mediante la secuencia matemática de Fibonacci, ponderando la dificultad algorítmica, el volumen de código y la incertidumbre tecnológica[cite: 3, 6].
* **Control de Iteraciones**: El esfuerzo total del catálogo (62 puntos) se distribuye en ciclos de dos semanas. A la fecha, con la culminación de las dos primeras iteraciones, se cuenta con un 85.5% de avance real verificado (53 puntos terminados)

---

### 2. Flujo de Trabajo y Control de Calidad (Criterios de Aceptación y Finalización)

Para que cualquier funcionalidad o tarea técnica sea declarada como **completada** e integrada en la rama principal, debe superar los siguientes controles técnicos:

1. **Calidad de Código**: Código fuente en Dart sin advertencias ni errores del analizador estático, siguiendo estrictamente las normas de nombrado formales y manteniendo las claves de conexión y credenciales fuera del repositorio mediante variables de configuración seguras
2. **Convención en el Registro de Cambios**: Registro de modificaciones estandarizado que indica el tipo de intervención realizada (`feat`, `fix`, `test`, `refactor`, `docs`) y asocia directamente el identificador del requerimiento abordado
3. **Flujo de Integración**: Se prohíben las modificaciones directas en la rama principal (`main`). Toda incorporación se realiza mediante solicitudes de integración que requieren la revisión y aprobación cruzada del otro miembro del equipo
4. **Validación y Pruebas**: Cobertura de pruebas automáticas de unidad para los módulos críticos (cálculos de semiverseno y algoritmos de proximidad dinámica) y validación manual directa en dispositivos físicos.

## Arquitectura del Sistema

El software adopta un patrón arquitectónico en tres capas desacopladas, asegurando la separación estricta entre presentación, lógica de negocio y entidades de dominio:

<img width="805" height="602" alt="image" src="https://github.com/user-attachments/assets/998b05f0-ed7c-4d1e-90e2-e83b796932da" />



1. Capa de Presentación

DriverScreen & MapOverlay: Interfaz civil para renderizado cartográfico con GoogleMapController, visualización reactiva del estado de alerta (isAlertActive), animación visual pulsante y descarte contextual fuera del radio crítico.

EmergencyScreen: Consola institucional para gestión del ciclo de la baliza (isTransmitting), monitoreo de telemetría en tiempo real (velocidad y radio dinámico) y registro acumulado de conductores advertidos.

AdminDashboardScreen: Panel SPA en Flutter Web que consume flujos reactivos de Firestore (fleetStream, driversStream), gestionando la flota vehicular y el aprovisionamiento de cuentas vía Identity Toolkit REST API.

2. Capa de Servicios de Negocio

GeofencingService: Procesamiento geodésico mediante la fórmula de Haversine y cálculo del radio predictivo dinámico según velocidades relativas de aproximación.

LocationService: Ingesta de telemetría geoespacial a 1 Hz con umbral de desplazamiento de 5 metros, sincronización efímera hacia Firebase Realtime Database y purgado automático al cesar la baliza.

AuthService: Proveedor de autenticación, control de acceso basado en roles (particular, emergencia, admin) y guardianes de navegación.

NotificationService: Despacho de notificaciones locales con canal de máxima prioridad e interrupción crítica a nivel de sistema operativo en Android e iOS.

3. Capa de Dominio y Modelos

User: Entidad de usuario con UID, credenciales, rol asignado e institución asociada.

Vehicle: Modelo de flota institucional indexado por placa patente, tipo de móvil y clave foránea al conductor asignado.

Emergency: Modelo de sesión crítica que vincula vehículo, chofer, estado de la baliza y total de conductores alertados.

LocationData: Objeto de valor que encapsula latitud, longitud, rumbo, velocidad instantánea en km/h y marca temporal.
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

## Diagrama de Clases

<img width="975" height="531" alt="image" src="https://github.com/user-attachments/assets/19b97f13-8659-47b9-818b-16775b2b0c0e" />


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
## Plan Integral de Pruebas (QA)

El aseguramiento de la calidad de **Vía Libre** abarca tanto la aplicación móvil multiplataforma (**Flutter**) como el panel web administrativo (**Flutter Web**), respaldados por una arquitectura *serverless* en **Firebase**[cite: 8]. El plan de pruebas organiza la validación del sistema en seis niveles[cite: 8]:

* **L1 — Pruebas Unitarias:** Verificación aislada de la lógica de negocio crítica en `GeofencingService` (cálculo de radio dinámico, distancia Haversine e histéresis), `LocationService` y `AuthService`[cite: 8].
* **L2 — Pruebas de Integración:** Validación de flujos de registro y roles, escritura/limpieza de balizas en Realtime Database, disparo de alertas y reglas de seguridad en Firestore mediante Firebase Emulators[cite: 8].
* **L3 — Pruebas de Widget / UI:** Comprobación del renderizado condicional de mapas y *overlays* de alerta (`DriverScreen`, `EmergencyScreen`) y validaciones de formularios[cite: 8].
* **L4 — Pruebas de Rendimiento:** Medición de latencia de notificaciones push (`P95 ≤ 2.000 ms`) y consumo energético en segundo plano (`≤ 15 %` en 60 minutos)[cite: 8].
* **L5 — Seguridad Básica (OWASP Mobile Top 10):** Auditoría de credenciales y secretos en Git, cifrado HTTPS, ofuscación ProGuard en *release* y control de acceso por rol en Firestore Rules[cite: 8].
* **L6 — Pruebas de Aceptación (UAT):** Validación end-to-end en dispositivos físicos y entorno *staging* de los flujos críticos de conductores particulares, unidades de emergencia y administración web[cite: 8].
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
