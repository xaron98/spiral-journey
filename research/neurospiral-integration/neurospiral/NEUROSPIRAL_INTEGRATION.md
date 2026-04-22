# NEUROSPIRAL_INTEGRATION.md — Guía de Integración para Agente

## Objetivo

Integrar el paquete Swift `SpiralGeometry` en la app Spiral Journey y añadir un botón en la vista **DNA Insights** (esquina superior derecha) que abra una nueva vista **NeuroSpiral 4D** mostrando la trayectoria de sueño del usuario en un toro de Clifford con micro-estados del teseracto.

---

## 1. Paquete SpiralGeometry

### Qué es

Un Swift package con la matemática del toro de Clifford, teseracto 4D y distancias Bures-Wasserstein. Tres archivos source:

| Archivo | Contenido |
|---------|-----------|
| `Tesseract.swift` | 16 vértices `{±1}⁴`, discretizador `Q(x) = sgn(x)`, doble rotación `R(ω₁t, ω₂t)`, análisis de residence, distancias euclídea y geodésica tórica |
| `BuresWasserstein.swift` | Distancia W₂ en forma cerrada para matrices SPD 4×4 via Accelerate/LAPACK. O(1) — viable en Apple Watch |
| `WearableMapping.swift` | Puente HealthKit → ℝ⁴ → toro de Clifford. `WearableTo4DMapper`, `WearableSleepSample`, `SleepTrajectoryAnalysis` |

### Dónde ponerlo

Copiar la carpeta `SpiralGeometry/` a la raíz del proyecto Spiral Journey (al mismo nivel que el `.xcodeproj` o `Package.swift` si hay workspace). La estructura debe ser:

```
spiral-journey-project/
├── SpiralGeometry/
│   ├── Package.swift
│   ├── Sources/SpiralGeometry/
│   │   ├── Tesseract.swift
│   │   ├── BuresWasserstein.swift
│   │   └── WearableMapping.swift
│   └── Tests/SpiralGeometryTests/
├── SpiralJourney/                    ← app existente
│   ├── Views/
│   │   ├── DNAInsightsView.swift     ← vista donde añadir el botón
│   │   └── ...
│   ├── Models/
│   └── ...
└── SpiralJourney.xcodeproj (o Package.swift)
```

### Cómo añadir la dependencia

**Opción A — Si el proyecto usa SPM (Package.swift):**

```swift
dependencies: [
    .package(path: "../SpiralGeometry")  // o "./SpiralGeometry" según ubicación
]
```

Y en el target de la app:

```swift
.target(
    name: "SpiralJourney",
    dependencies: [
        .product(name: "SpiralGeometry", package: "SpiralGeometry")
    ]
)
```

**Opción B — Si el proyecto usa Xcode project:**

1. File → Add Package Dependencies → Add Local → seleccionar la carpeta `SpiralGeometry`
2. En el target de SpiralJourney → Frameworks → añadir `SpiralGeometry`

### Plataformas soportadas

El package está configurado para `.iOS(.v17)`, `.watchOS(.v10)`, `.macOS(.v14)`. Usa `simd` (nativo) y `Accelerate` (LAPACK) — ambos disponibles en todas las plataformas Apple sin dependencias externas.

---

## 2. Botón en DNA Insights

### Ubicación exacta

Añadir un botón con icono de cubo 4D en la esquina superior derecha de `DNAInsightsView`. El botón abre un `.sheet` o `.fullScreenCover` con la nueva vista `NeuroSpiralView`.

### Implementación del botón

Buscar la vista `DNAInsightsView` (o el nombre equivalente de la vista de insights/análisis de sueño). Añadir al `toolbar` o como overlay en la parte superior derecha:

```swift
import SpiralGeometry

struct DNAInsightsView: View {
    @State private var showNeuroSpiral = false

    var body: some View {
        // ... contenido existente de DNA Insights ...
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNeuroSpiral = true
                } label: {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel("NeuroSpiral 4D")
            }
        }
        .sheet(isPresented: $showNeuroSpiral) {
            NeuroSpiralView()
        }
    }
}
```

Si la vista no usa `NavigationStack`/`NavigationView`, colocar el botón como overlay:

```swift
.overlay(alignment: .topTrailing) {
    Button {
        showNeuroSpiral = true
    } label: {
        Image(systemName: "cube.transparent")
            .font(.system(size: 17, weight: .medium))
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
    }
    .padding(.top, 8)
    .padding(.trailing, 16)
}
```

El icono SF Symbol `cube.transparent` representa un cubo 3D con transparencia — la mejor aproximación visual a un teseracto disponible en SF Symbols. Alternativa: `cube` o `square.3.layers.3d`.

---

## 3. Vista NeuroSpiralView

### Archivo nuevo: `NeuroSpiralView.swift`

Crear este archivo en la carpeta `Views/` del proyecto (o donde estén las demás vistas). Esta es la vista completa que se abre desde el botón.

```swift
import SwiftUI
import SpiralGeometry

struct NeuroSpiralView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var analysis: SleepTrajectoryAnalysis?
    @State private var mapper = WearableTo4DMapper()
    @State private var isLoading = true
    @State private var selectedVertex: TesseractVertex?
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header card
                    headerCard

                    if isLoading {
                        ProgressView("Proyectando al toro de Clifford...")
                            .padding(40)
                    } else if let analysis {
                        // Torus projection (2D visualization of θ, φ)
                        torusProjectionView(analysis)

                        // Vertex residence chart
                        vertexResidenceCard(analysis)

                        // Angular velocities (ω₁, ω₂)
                        oscillatorCard(analysis)

                        // Transition graph
                        transitionCard(analysis)

                        // Dominant state info
                        dominantStateCard(analysis)
                    } else {
                        ContentUnavailableView(
                            "Sin datos de sueño",
                            systemImage: "moon.zzz",
                            description: Text("Registra al menos 3 noches para generar el análisis 4D")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("NeuroSpiral 4D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingInfo) {
                neuroSpiralInfoView
            }
            .task {
                await loadAndAnalyze()
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Trayectoria 4D")
                    .font(.headline)
                Spacer()
            }
            Text("Tu sueño mapeado en un toro de Clifford con 16 micro-estados del teseracto")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Torus projection (θ vs φ scatter plot)

    private func torusProjectionView(_ analysis: SleepTrajectoryAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proyección tórica (θ, φ)")
                .font(.subheadline.weight(.medium))

            // 2D plot: θ (horizontal) vs φ (vertical)
            // Each point is one sample projected onto the torus
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let padX: CGFloat = 20
                let padY: CGFloat = 20

                // Draw quadrant grid (the 16 tesseract cells)
                let gridColor = Color.secondary.opacity(0.15)
                for i in 0...4 {
                    let xFrac = CGFloat(i) / 4.0
                    let yFrac = CGFloat(i) / 4.0
                    let x = padX + xFrac * (w - 2 * padX)
                    let y = padY + yFrac * (h - 2 * padY)
                    // Vertical lines
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) },
                        with: .color(gridColor), lineWidth: 0.5
                    )
                    // Horizontal lines
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) },
                        with: .color(gridColor), lineWidth: 0.5
                    )
                }

                // Plot trajectory points
                for point in analysis.trajectory {
                    let (theta, phi) = CliffordTorus.angles(of: point)
                    // Map [-π, π] → [padX, w-padX]
                    let x = padX + ((theta + .pi) / (2 * .pi)) * (w - 2 * padX)
                    let y = padY + ((phi + .pi) / (2 * .pi)) * (h - 2 * padY)
                    let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(.purple.opacity(0.5)))
                }

                // Mark tesseract vertices
                for vertex in Tesseract.vertices {
                    let (vt, vp) = vertex.torusAngles
                    let x = padX + ((vt + .pi) / (2 * .pi)) * (w - 2 * padX)
                    let y = padY + ((vp + .pi) / (2 * .pi)) * (h - 2 * padY)
                    let rect = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
                    let isDominant = vertex.index == analysis.residence.dominantVertex.index
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(isDominant ? .green : .orange.opacity(0.6))
                    )
                }
            }
            .frame(height: 250)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 16) {
                Label("Muestras", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.purple)
                Label("Vértices", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                Label("Dominante", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Vertex residence

    private func vertexResidenceCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Residence de micro-estados")
                .font(.subheadline.weight(.medium))

            // Top 5 most visited vertices
            let sorted = analysis.vertexFractions.sorted { $0.value > $1.value }.prefix(5)
            ForEach(Array(sorted), id: \.key) { vertexIdx, fraction in
                let vertex = Tesseract.vertices[vertexIdx]
                HStack {
                    Text("V\(String(format: "%02d", vertexIdx))")
                        .font(.caption.monospaced())
                    Text(vertex.code.description)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.weight(.medium))

                    // Progress bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.purple.opacity(0.3))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(width: 60, height: 8)
                }
            }

            HStack {
                Label("Estabilidad", systemImage: "waveform.path")
                Spacer()
                Text(String(format: "%.0f%%", analysis.residence.stabilityScore * 100))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(analysis.residence.stabilityScore > 0.6 ? .green : .orange)
            }
            .font(.caption)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Oscillators ω₁ / ω₂

    private func oscillatorCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Osciladores biológicos")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 20) {
                VStack {
                    Text("ω₁")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.3f", analysis.omega1Mean))
                        .font(.title3.monospaced().weight(.medium))
                    Text("Proceso S")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack {
                    Text("ω₂")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.3f", analysis.omega2Mean))
                        .font(.title3.monospaced().weight(.medium))
                    Text("Proceso C")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack {
                    Text("ω₁/ω₂")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let ratio = analysis.windingRatio {
                        Text(String(format: "%.2f", ratio))
                            .font(.title3.monospaced().weight(.medium))
                    } else {
                        Text("—")
                            .font(.title3)
                    }
                    Text("Winding")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            }

            Text("ω₁ (homeostático) mide la presión de sueño delta. ω₂ (circadiano) mide el ritmo endógeno. Su ratio es el número de enroscamiento de la trayectoria en el toro.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Transitions

    private func transitionCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transiciones")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(analysis.residence.transitionCount) cambios")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Top 5 most common transitions
            let topEdges = analysis.edgeTraversals.sorted { $0.value > $1.value }.prefix(5)
            if topEdges.isEmpty {
                Text("Sin transiciones detectadas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topEdges), id: \.key) { edge, count in
                    HStack {
                        Text(edge)
                            .font(.caption.monospaced())
                        Spacer()
                        Text("×\(count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Transiciones Hamming-1 (un solo bit flip) indican progresión suave entre estados. Saltos Hamming ≥ 2 sugieren cambio brusco.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Dominant state

    private func dominantStateCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        let vertex = analysis.residence.dominantVertex
        let code = vertex.code

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Estado dominante")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("V\(String(format: "%02d", vertex.index))")
                    .font(.caption.monospaced().weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.2), in: Capsule())
            }

            // Decode the 4 dimensions
            VStack(alignment: .leading, spacing: 6) {
                dimensionRow("Profundidad autonómica (HRV)", value: code.x, positive: "Alta", negative: "Baja")
                dimensionRow("Quietud motora", value: code.y, positive: "Quieto", negative: "Movimiento")
                dimensionRow("Enlentecimiento cardíaco", value: code.z, positive: "Lento", negative: "Rápido")
                dimensionRow("Fase circadiana", value: code.w, positive: "Diurna", negative: "Nocturna")
            }

            Text(String(format: "Residencia: %.0f%% del tiempo en este micro-estado", analysis.residence.residenceFraction * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dimensionRow(_ label: String, value: Int, positive: String, negative: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value > 0 ? positive : negative)
                .font(.caption2.weight(.medium))
                .foregroundStyle(value > 0 ? .green : .orange)
            Image(systemName: value > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(value > 0 ? .green : .orange)
        }
    }

    // MARK: - Info sheet

    private var neuroSpiralInfoView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("¿Qué es esto?")
                            .font(.headline)
                        Text("NeuroSpiral 4D mapea tus datos de sueño del Apple Watch a un espacio matemático de 4 dimensiones llamado toro de Clifford. Este toro vive dentro de un teseracto (hipercubo 4D) con 16 vértices que representan micro-estados fisiológicos.")

                        Text("Las 4 dimensiones")
                            .font(.headline)
                        Text("Cada muestra de tu Apple Watch se transforma en un punto 4D usando: variabilidad cardíaca (HRV), quietud motora, frecuencia cardíaca y hora del día. Estos 4 valores definen tu posición en el toro.")

                        Text("Los osciladores ω₁ y ω₂")
                            .font(.headline)
                        Text("ω₁ mide cuán rápido se mueve tu estado en el plano homeostático (presión de sueño, dominada por ondas delta). ω₂ mide el ritmo circadiano. Su ratio (ω₁/ω₂) es el 'número de enroscamiento' — si es racional tu trayectoria se cierra (sueño regular), si es irracional nunca se repite exactamente (sueño irregular).")

                        Text("La estabilidad")
                            .font(.headline)
                        Text("Un score alto de estabilidad significa que pasas la mayor parte de la noche en un solo micro-estado (sueño consolidado). Estabilidad baja indica fragmentación — tu trayectoria salta entre muchos vértices del teseracto.")
                    }
                    .font(.subheadline)

                    Divider()

                    Text("Basado en: geometría del toro de Clifford (S¹×S¹ ⊂ S³), discretización tesseractal Q(x) = sgn(x), y el modelo de dos procesos de Borbély (1982).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Sobre NeuroSpiral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { showingInfo = false }
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadAndAnalyze() async {
        isLoading = true

        // INTEGRACIÓN CON TUS DATOS:
        // Reemplaza este bloque con la obtención real de datos de sueño
        // de tu modelo de datos existente (HealthKit o manual).
        //
        // Lo que necesitas es construir un array de WearableSleepSample
        // a partir de tus datos de la última semana (o el rango que prefieras).
        //
        // Ejemplo de integración con HealthKit (adaptar a tu código existente):
        //
        //   let samples = await fetchHealthKitSleepData(days: 7)
        //   let wearableSamples = samples.map { sample in
        //       WearableSleepSample(
        //           hrv: sample.hrv,
        //           heartRate: sample.heartRate,
        //           motionIntensity: sample.motion,
        //           respiratoryRate: sample.respiratoryRate,
        //           sleepStage: mapToSleepStage(sample.stage),
        //           timestamp: sample.date
        //       )
        //   }
        //
        // Ejemplo de integración con datos manuales:
        //
        //   let entries = myDataModel.recentSleepEntries(days: 7)
        //   let wearableSamples = entries.flatMap { entry in
        //       generateSamplesFromManualEntry(entry)
        //   }

        // --- DATOS DE DEMOSTRACIÓN (reemplazar con datos reales) ---
        let demoSamples = generateDemoSamples(nights: 5)
        // --- FIN DEMO ---

        // Analizar con el mapper
        let result = mapper.analyzeNight(demoSamples)
        
        await MainActor.run {
            analysis = result
            isLoading = false
        }
    }

    /// Genera datos de demostración para testing.
    /// ELIMINAR cuando se conecten datos reales.
    private func generateDemoSamples(nights: Int) -> [WearableSleepSample] {
        var samples: [WearableSleepSample] = []
        let calendar = Calendar.current
        let now = Date()

        for night in 0..<nights {
            let bedtime = calendar.date(byAdding: .day, value: -night, to: now)!
            let bedHour = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: bedtime)!

            for epoch in 0..<240 {  // 240 × 30s = 2 hours
                let timestamp = bedHour.addingTimeInterval(Double(epoch) * 30)
                let progress = Double(epoch) / 240.0

                // Simulate sleep deepening then lightening
                let depthCurve = sin(progress * .pi)
                let hrvBase = 45 + depthCurve * 25 + Double.random(in: -5...5)
                let hrBase = 62 - depthCurve * 12 + Double.random(in: -3...3)
                let motion = max(0, 0.1 - depthCurve * 0.08 + Double.random(in: -0.02...0.05))

                samples.append(WearableSleepSample(
                    hrv: hrvBase,
                    heartRate: hrBase,
                    motionIntensity: motion,
                    timestamp: timestamp
                ))
            }
        }
        return samples
    }
}

// MARK: - SIMD4 description helper

extension SIMD4 where Scalar == Int {
    var description: String {
        "[\(x > 0 ? "+" : "")\(x), \(y > 0 ? "+" : "")\(y), \(z > 0 ? "+" : "")\(z), \(w > 0 ? "+" : "")\(w)]"
    }
}
```

---

## 4. Conexión con datos reales

### Si usas HealthKit

En el método `loadAndAnalyze()` de `NeuroSpiralView`, reemplaza los datos de demostración con tu fetch real de HealthKit. El mapper necesita `WearableSleepSample` con estos campos:

```swift
WearableSleepSample(
    hrv: Double,              // RMSSD en ms (HKQuantityType.heartRateVariabilitySDNN)
    heartRate: Double,         // BPM (HKQuantityType.heartRate)
    motionIntensity: Double,   // 0-1 (derivado de accelerometer/activityLevel)
    respiratoryRate: Double?,  // opcional (HKQuantityType.respiratoryRate)
    sleepStage: SleepStage?,   // .awake/.core/.deep/.rem (HKCategoryValueSleepAnalysis)
    timestamp: Date
)
```

Las muestras deben tener resolución de ~30 segundos para que la trayectoria en el toro sea suave. Si tus datos de HealthKit vienen en intervalos más largos, interpolar linealmente.

### Si usas datos manuales

Para entradas manuales (bedtime/waketime sin datos de sensores), generar muestras sintéticas con un modelo simplificado:

```swift
func generateSamplesFromManualEntry(
    bedtime: Date,
    waketime: Date
) -> [WearableSleepSample] {
    let duration = waketime.timeIntervalSince(bedtime)
    let epochCount = Int(duration / 30)

    return (0..<epochCount).map { i in
        let t = Double(i) / Double(epochCount)
        let timestamp = bedtime.addingTimeInterval(Double(i) * 30)

        // Modelo simplificado: curva sinusoidal de profundidad
        let depth = sin(t * .pi)

        return WearableSleepSample(
            hrv: 40 + depth * 20,
            heartRate: 65 - depth * 10,
            motionIntensity: max(0, 0.1 - depth * 0.08),
            timestamp: timestamp
        )
    }
}
```

Esto produce una trayectoria 4D menos precisa que datos de sensores, pero sigue siendo útil para la visualización y el análisis de patrones entre noches.

### Personalización del baseline

El `WearableTo4DMapper` usa un baseline personal para normalizar los datos. Actualizar con datos de vigilia del usuario:

```swift
var mapper = WearableTo4DMapper()

// Actualizar con muestras de vigilia (ej: datos diurnos de la última semana)
let wakeSamples = await fetchWakeData(days: 7)
mapper.updateBaseline(from: wakeSamples)

// Guardar baseline para persistencia
let baseline = mapper.baseline
UserDefaults.standard.set(baseline.hrvMean, forKey: "neuro_hrv_mean")
// ... etc
```

---

## 5. Estilo y diseño

### Principios de diseño

- Usar `.ultraThinMaterial` para cards (coherente con el estilo vidrioso de la app)
- Colores principales: `.purple` para datos del toro, `.teal` para circadiano, `.orange` para alertas
- Tipografía monoespaciada para valores numéricos y códigos de vértice
- Dark theme (heredado de la app existente)
- Animaciones sutiles con `.animation(.spring, value:)` en transiciones de estado

### Adaptación a pantallas

La vista ya usa `ScrollView` + `VStack`, así que se adapta a iPhone y iPad. Para macOS, considerar layout horizontal con la proyección tórica a la izquierda y las cards a la derecha usando un `HStack` condicional.

---

## 6. Resumen de archivos a crear/modificar

| Acción | Archivo | Qué hacer |
|--------|---------|-----------|
| Copiar | `SpiralGeometry/` (carpeta entera) | Copiar al root del proyecto |
| Modificar | `Package.swift` o Xcode project | Añadir dependencia local de SpiralGeometry |
| Modificar | `DNAInsightsView.swift` | Añadir `@State var showNeuroSpiral` + botón toolbar + `.sheet` |
| Crear | `Views/NeuroSpiralView.swift` | El código completo de la sección 3 |
| Modificar | Conexión de datos | Reemplazar `generateDemoSamples()` con datos reales en `loadAndAnalyze()` |

---

## 7. Contexto matemático (para que el agente entienda qué está implementando)

### ¿Por qué un toro de Clifford?

El sueño humano está gobernado por dos osciladores: el homeostático (Proceso S de Borbély, dominado por la presión de sueño delta) y el circadiano (Proceso C, ritmo endógeno de ~24h). Dos osciladores acoplados generan trayectorias en un toro 𝕋² = S¹ × S¹. El toro de Clifford es este 𝕋² embebido en la hiperesfera S³ ⊂ ℝ⁴, satisfaciendo x²+y² = R² y z²+w² = R².

### ¿Por qué un teseracto?

Los 16 vértices del teseracto `{±1}⁴` son la discretización intrínseca del toro de Clifford. Cada vértice corresponde a un cuadrante angular en los planos (θ, φ). La función Q(x) = sgn(x) mapea cualquier punto del toro al vértice más cercano, particionando el espacio en 16 micro-estados. Las aristas del teseracto (Hamming distance = 1) representan transiciones suaves donde solo un marcador fisiológico cambia.

### ¿Por qué Bures-Wasserstein?

Las matrices de covarianza de las trayectorias de sueño viven en un colector riemanniano (el cono de matrices SPD). La distancia euclídea entre covarianzas "corta" a través del interior del cono — caminos que no corresponden a covarianzas válidas. La distancia Bures-Wasserstein W₂ sigue geodésicas en el colector, respetando la geometría. Para matrices 4×4 tiene forma cerrada (eigendecomposition de 4 valores) → O(1), viable en Apple Watch.

### ¿Qué son ω₁ y ω₂?

Son las velocidades angulares estimadas de la trayectoria en cada plano del toro. ω₁ = dθ/dt (velocidad en el plano xy, correlacionada con Proceso S). ω₂ = dφ/dt (velocidad en el plano zw, correlacionada con Proceso C). Su ratio ω₁/ω₂ es el número de enroscamiento: racional → órbita cerrada (sueño regular), irracional → órbita densa (sueño irregular/fragmentado).
