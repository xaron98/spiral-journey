# Poisson & Hawkes Process Analysis Layer

## Objetivo

Añadir una capa de análisis estocástico al motor SleepDNA que formalice:
1. La tasa de fragmentación nocturna como proceso de Poisson
2. Los efectos retardados de eventos contextuales como proceso de Hawkes auto-excitado
3. Validación estadística mediante prueba χ²

## Componentes

### 1. FragmentationPoissonModel

Modela los despertares nocturnos como un proceso de Poisson con tasa λ.

**Input:** Array de SleepRecord (últimas 14-28 noches)

**Output:**
```swift
struct PoissonFragmentationResult: Codable, Sendable {
    let baselineRate: Double        // λ promedio de despertares por noche
    let nightlyRates: [DayRate]     // λ por noche
    let anomalousNights: [Int]      // días con tasa > 2σ sobre baseline
    let chiSquaredPValue: Double    // p-value de bondad de ajuste
    let followsPoisson: Bool        // true si p > 0.05
}

struct DayRate: Codable, Sendable {
    let day: Int
    let awakenings: Int             // conteo observado
    let expectedRate: Double        // λ esperada
    let pValue: Double              // probabilidad de observar >= awakenings dado λ
    let isAnomaly: Bool             // pValue < 0.05
}
```

**Cálculo:**
1. Contar despertares por noche (fases awake dentro del rango bedtime-wake)
2. Calcular λ_baseline = media de despertares
3. Por cada noche: P(X >= observed | λ) usando distribución de Poisson acumulada
4. χ² goodness-of-fit: comparar distribución observada vs Poisson teórica
5. Noches anómalas: aquellas con P(X >= observed) < 0.05

### 2. HawkesEventModel

Modela cómo los eventos contextuales (cafeína, estrés, etc.) afectan la tasa de fragmentación con retardo temporal.

**Input:** Array de CircadianEvent + Array de SleepRecord

**Output:**
```swift
struct HawkesAnalysisResult: Codable, Sendable {
    let baseIntensity: Double           // μ (tasa base sin excitación)
    let eventImpacts: [EventImpact]     // impacto por tipo de evento
    let decayHalfLife: Double           // horas hasta que el efecto decae 50%
}

struct EventImpact: Codable, Sendable {
    let eventType: EventType
    let excitationStrength: Double      // α — cuánto sube la tasa λ
    let delayHours: Double              // retardo medio hasta el efecto
    let significantEffect: Bool         // true si α > umbral mínimo
    let description: String             // "El estrés eleva tu fragmentación un 40% con 36h de retardo"
}
```

**Cálculo:**

La intensidad del proceso de Hawkes se define como:

```
λ(t) = μ + Σ_i α_i · g(t - t_i)
```

Donde:
- μ = tasa base (fragmentación sin eventos)
- α_i = fuerza de excitación del evento i
- g(t) = kernel de decay exponencial: exp(-β·t)
- t_i = momento del evento i

**Estimación de parámetros (μ, α, β):**
- Método de máxima verosimilitud simplificado
- Para cada tipo de evento, estimar α y β separadamente
- β = 1/decayHalfLife (inversamente proporcional a la duración del efecto)

**Simplificación práctica:**
- No resolver MLE completo (computacionalmente caro para on-device)
- Usar regresión lineal: para cada noche, contar despertares y calcular la suma de excitación de eventos previos
- Ajustar un modelo lineal: awakenings_night ~ μ + Σ_type (α_type · Σ_events_type g(delay))
- Probar lags de 0h, 12h, 24h, 36h, 48h, 72h para encontrar el decay óptimo

### 3. Integración con SleepDNAProfile

Añadir al `SleepDNAProfile`:
```swift
// Poisson fragmentation analysis
let poissonFragmentation: PoissonFragmentationResult?
// Hawkes event impact analysis
let hawkesAnalysis: HawkesAnalysisResult?
```

**Tier gating:**
- `PoissonFragmentation`: tier intermediate (4+ semanas, necesita ≥14 noches)
- `HawkesAnalysis`: tier full (8+ semanas, necesita suficientes eventos para estimar α)

### 4. Exposición en UI

**DNAInsightsView — nueva sección "Impacto temporal":**
- Muestra los EventImpacts con retardo: "El estrés eleva tu fragmentación un 40% con ~36h de retardo"
- Noches anómalas destacadas: "Anoche tuviste 5 despertares (lo normal para ti son 2)"
- Si followsPoisson = false: "Tus despertares no son aleatorios — hay un patrón que los causa"

## Archivos

| Acción | Archivo | Notas |
|--------|---------|-------|
| Crear | `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/PoissonFragmentation.swift` | Modelo de fragmentación |
| Crear | `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HawkesEventModel.swift` | Modelo de impacto temporal |
| Modificar | `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SleepDNAProfile.swift` | Añadir campos |
| Modificar | `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SleepDNAComputer.swift` | Ejecutar análisis |
| Crear | `SpiralKit/Tests/SpiralKitTests/SleepDNA/PoissonTests.swift` | Tests |
| Crear | `SpiralKit/Tests/SpiralKitTests/SleepDNA/HawkesTests.swift` | Tests |

## Matemáticas clave

**Probabilidad de Poisson:**
```
P(X = k) = (λ^k · e^(-λ)) / k!
```

**CDF complementaria (para anomalías):**
```
P(X >= k) = 1 - Σ_{i=0}^{k-1} P(X = i)
```

**Chi-cuadrado:**
```
χ² = Σ (O_i - E_i)² / E_i
```
Donde O_i = frecuencia observada, E_i = frecuencia esperada bajo Poisson(λ)

**Hawkes kernel:**
```
g(t) = exp(-t / halfLife)
excitation_night = Σ_events α · g(night_hour - event_hour)
```

## Dependencias

- No usa frameworks externos — matemáticas puras implementadas en Swift
- Accelerate/vDSP no necesario (operaciones simples, no vectorizadas)
- Compatible con on-device execution
