# Resumen Matutino + Alertas Predictivas

## Objetivo

Cada mañana al despertar, el usuario recibe una notificación local con un resumen de cómo durmió y un consejo personalizado. Opcionalmente, alertas predictivas durante el día basadas en patrones detectados.

## Componentes

### 1. Resumen Matutino (notificación local diaria)

**Cuándo:** Cada mañana, 30 minutos después de la hora de despertar predicha (o a las 08:00 si no hay predicción).

**Contenido:** 2-3 líneas con:
- Duración de la noche anterior: "Dormiste 7.2h"
- Estado del ritmo: "Tu ritmo está estable" o "Tu ritmo empeoró — intenta acostarte más temprano"
- Consejo basado en ExpressionRules/HealthInsightRules: "Hoy evita café después de las 15h" (si el café afecta su sueño)

**Generación del texto:** Función `MorningSummaryBuilder` que toma el `SleepRecord` de anoche + `SleepDNAProfile` + `SpiralConsistencyScore` y genera el resumen. Reglas deterministas, sin LLM.

**Scheduling:** Cada noche, cuando se detecta el último episodio de sueño (o en background task), se programa la notificación del día siguiente. Se cancela la anterior y se reprograma con los datos frescos.

### 2. Alertas Predictivas (notificación local condicional)

**Cuándo:** A las 18:00 (tarde), solo si se detecta un patrón de riesgo.

**Condiciones para disparar:**
- La semana actual se parece (DTW similarity > 0.6) a una semana histórica que terminó con mala calidad
- O hay una mutación "nonsense" (cambio significativo) en curso
- O el drift acumulado de esta semana supera 1.5h

**Contenido:** "Basado en tu patrón de esta semana, mañana podrías dormir peor. Hoy sería buen día para ejercicio y evitar café tardío."

**Scheduling:** Se evalúa en el background task diario (BGProcessingTask). Si ninguna condición se cumple, no se envía nada.

### 3. Toggle en Ajustes

En Settings > sección de notificaciones:
- `Resumen matutino` — toggle ON/OFF (default: ON)
- `Alertas predictivas` — toggle ON/OFF (default: ON)
- Al activar cualquiera, se pide permiso de notificaciones si no se ha concedido

## Archivos

| Acción | Archivo | Descripción |
|--------|---------|-------------|
| Crear | `Services/MorningSummaryBuilder.swift` | Genera texto del resumen matutino |
| Crear | `Services/PredictiveAlertBuilder.swift` | Evalúa condiciones + genera texto de alerta |
| Modificar | `Services/NotificationManager.swift` | Añadir scheduling de morning summary + predictive alert |
| Modificar | `Services/BackgroundTaskManager.swift` | Llamar a MorningSummary/PredictiveAlert en BGTask |
| Modificar | `Services/SpiralStore.swift` | Añadir `morningSummaryEnabled` + `predictiveAlertsEnabled` |
| Modificar | `Views/Tabs/SettingsTab.swift` | Toggles de notificaciones |
| Modificar | `Localizable.xcstrings` | Claves para los textos de notificaciones |

## Lógica del MorningSummaryBuilder

```
Input: lastNightRecord, dnaProfile?, consistency?
Output: (title: String, body: String)

1. Title: "Buenos días" (o "Buenas tardes" si despertó después de las 12)
2. Body parts:
   a. "Dormiste Xh" (lastNightRecord.sleepDuration)
   b. IF consistency.deltaVsPreviousWeek > 2: "Tu ritmo mejoró ↑"
      ELIF < -2: "Tu ritmo empeoró ↓"
      ELSE: "Tu ritmo está estable →"
   c. IF dnaProfile has ExpressionRule with delta > 0.05 for caffeine:
      "Hoy evita café después de las 15h"
      ELIF high fragmentation alert:
      "Evita pantallas 1h antes de dormir"
      ELSE: pick top recommendation from analysis
```

## Lógica del PredictiveAlertBuilder

```
Input: currentWeekRecords, dnaProfile, alignments
Output: (shouldAlert: Bool, body: String)

1. Find best DTW alignment for current partial week
2. IF best similar week's next day had quality < 0.4:
   shouldAlert = true
   body = "Basado en tu patrón, mañana podrías dormir peor. Buen día para ejercicio."
3. ELIF current week has nonsense mutation:
   shouldAlert = true
   body = "Tu patrón de sueño cambió significativamente esta semana. Intenta regularizar horarios."
4. ELIF weekly drift > 1.5h:
   shouldAlert = true
   body = "Tu horario se está desplazando. Intenta fijar la hora de despertar."
5. ELSE: shouldAlert = false
```

## Scheduling

- **Morning summary:** `UNCalendarNotificationTrigger` programado cada noche. La hora se calcula: `predictedWakeHour + 0.5h` o fallback `08:00`.
- **Predictive alert:** `UNCalendarNotificationTrigger` para las 18:00, solo se programa si `PredictiveAlertBuilder.shouldAlert == true`.
- **IDs:** `"spiral.morning.summary"` y `"spiral.predictive.alert"` — se cancelan y reprograman cada vez.
- **Background:** `BackgroundTaskManager` llama a ambos builders al ejecutar el BGProcessingTask nocturno.

## Permisos

Al activar cualquier toggle por primera vez, se llama a `NotificationManager.requestPermission()`. Si denegado, se muestra un alert con botón para abrir Settings del sistema.
