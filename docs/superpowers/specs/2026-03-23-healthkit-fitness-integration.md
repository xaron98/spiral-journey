# HealthKit Fitness Data Integration

## Objetivo

Ampliar la lectura de HealthKit de solo sueño+HRV a la jornada completa: pasos, FC, HRV, temperatura, luz natural, workouts, menstruación. Esto transforma la app de sleep tracker a cronobiógrafo personal.

## Datos a leer

### Prioridad 1 (impacto directo en análisis)
- `stepCount` — señal primaria para cosinor, actividad diurna
- `heartRate` — ritmo circadiano cardíaco, nadir nocturno
- `heartRateVariabilitySDNN` — ya se pide, pero no se usa completamente
- `appleSleepingWristTemperature` — proxy de fase circadiana
- `appleExerciseTime` — marcador PRC formal

### Prioridad 2 (enriquecimiento)
- `timeInDaylight` (iOS 17+) — zeitgeber primario
- `environmentalAudioExposure` — ruido nocturno
- `restingHeartRate` — tendencia diaria
- `activeEnergyBurned` — intensidad de actividad

### Prioridad 3 (ciclo menstrual, opcional)
- `menstrualFlow` — marcador de periodicidad ~28d
- `ovulationTestResult` — transición folicular→lútea

## Modelo de datos

```swift
/// Complete 24h health profile for one day.
public struct DayHealthProfile: Codable, Sendable {
    public let day: Int
    public let date: Date

    // Activity (24 hourly values, normalized 0-1)
    public let hourlySteps: [Double]
    public let totalSteps: Int
    public let exerciseMinutes: Double
    public let activeCalories: Double

    // Cardio
    public let restingHR: Double?
    public let avgNocturnalHRV: Double?
    public let hrNadirHour: Double?       // hour of minimum HR

    // Temperature
    public let wristTempDeviation: Double? // vs baseline

    // Environment
    public let daylightMinutes: Double?

    // Cycle
    public let menstrualFlow: Int?        // 0=none, 1=light, 2=medium, 3=heavy

    // Computed
    public let cosinorFromSteps: CosinorResult?
}
```

## Archivos

| Acción | Archivo | Notas |
|--------|---------|-------|
| Modificar | `HealthKitManager.swift` | Ampliar readTypes + nuevos fetch methods |
| Crear | `SpiralKit/Models/DayHealthProfile.swift` | Modelo de jornada completa |
| Crear | `SpiralKit/Analysis/DayHealthProfileBuilder.swift` | Construye perfiles desde datos raw |
| Modificar | `SpiralStore.swift` | Almacenar perfiles de salud |
| Modificar | `Localizable.xcstrings` | Permisos y textos |

## Permisos

Al solicitar autorización, pedir TODOS los tipos de una vez. Si el usuario deniega alguno, los campos correspondientes quedan nil — sin error.

## Frecuencia de fetch

- **Background task diario** (4AM, junto con DNA refresh): fetch datos del día anterior
- **Al abrir la app**: fetch datos de hoy hasta la hora actual
- **Observer query**: solo para sueño (ya existe) y workouts (nuevo)
